package Plugins::ListeningHistory::Tracker;

# Watches every player and records what was actually listened to.
#
#   A track COUNTS once played_threshold % of it has played (default 90), or after 60s when
#   it reports no length. The timer is re-checked against real playback progress, so a
#   pause or a seek backwards delays it, and the next song cancels it — a skipped track is
#   never recorded. (The event handling is Listen Later's Played.pm pattern.)
#
#   Tracks are GROUPED per player into a session. A counted track from the same album as
#   the session's, not already heard in it, and starting within session_gap_min of the
#   last one, joins the session: the second such track turns the entry into an ALBUM entry
#   and every later one bumps its count. Anything else starts a new session with a TRACK
#   entry. A stop or a cleared playlist ends the session.
#
#   A radio station is recorded ONCE per session, after 60s. The stream's title changes
#   arrive as newsong events on the same url and are ignored.
#
#   Sessions live in memory, so a server restart would forget them: the album being played
#   would split in two when it is resumed, and a track already counted would be counted
#   again. So the FIRST newsong on each player after startup rebuilds its session from the
#   player's last entry in the database, when that ended within session_gap_min, and the
#   first play counted after that is dropped if it is the same url as the last play
#   recorded: that is the resumed track, heard once, not twice.

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

use Plugins::ListeningHistory::DB;
use Plugins::ListeningHistory::Sources;

my $log   = logger('plugin.listeninghistory');
my $prefs = preferences('plugin.listeninghistory');

# Listen time when a track or stream reports no length.
use constant FALLBACK_SECS => 60;

my %pending;   # per player: { client, url, target, started_at, station }
my %session;   # per player: { entry_id, kind, album_key, url, urls => {}, last_at, resumed_url }
my %restored;  # per player: 1 once the first newsong since startup has rebuilt its session

sub init {
    Slim::Control::Request::subscribe(\&_onChange, [['playlist'], ['newsong', 'stop', 'clear']]);
    $log->info('Listening History tracker subscribed');
    return;
}

sub shutdown {
    Slim::Control::Request::unsubscribe(\&_onChange);
    _cancel($_) for keys %pending;
    %session  = ();
    %restored = ();
    return;
}

sub _onChange {
    my $request = shift;
    my $client  = $request->client or return;
    my $cid     = $client->id;

    if ($request->isCommand([['playlist'], ['stop', 'clear']])) {
        _cancel($cid);
        delete $session{$cid};
        return;
    }

    my $song  = eval { $client->playingSong } or return;
    my $track = eval { $song->track }         or return;
    my $url   = eval { $track->url };
    return unless defined $url && length $url;

    my $first = !$restored{$cid}++;
    _restore($cid) if $first;

    # A radio stream announces each new song title as a newsong on the SAME url. That is
    # not a new listen: keep the pending station mark, and never log the station twice.
    my $p = $pending{$cid};
    return if $p && $p->{station} && $p->{url} eq $url;
    my $s = $session{$cid};
    return if $s && ($s->{kind} // '') eq 'station' && ($s->{url} // '') eq $url;

    _cancel($cid);

    my $remote = eval { $track->can('remote') ? $track->remote : undef };
    $remote = ($url !~ m{^file:}i && $url =~ m{^\w+://}) ? 1 : 0 unless defined $remote;
    my $source  = $remote ? Plugins::ListeningHistory::Sources::sourceFromUrl($url) : 'library';
    my $dur     = _duration($client, $song, $url, $remote);
    my $station = Plugins::ListeningHistory::Sources::isStation($source, $dur, $remote);

    my $info = {
        client     => $client,
        url        => $url,
        target     => $station ? 0 : _target($dur),
        started_at => time(),
        station    => $station,
        remote     => $remote,
    };
    # The first track after a restart may be resumed where it stopped (local files are; streams
    # start again from the top). What came before the resume point was heard before the restart,
    # so only the rest of the 90% is still owed. songElapsedSeconds counts from the start of the
    # STREAM, not the track, so it is the resume point, startOffset, that comes off the target.
    # Only here: a seek also starts a new stream and a newsong, and must still be listened through.
    if ($first && $info->{target} > 0) {
        my $from = eval { $song->startOffset } || 0;
        if ($from > 0) {
            $info->{target} -= $from;
            $info->{target} = 1 if $info->{target} < 1;
        }
    }

    my $wait = $info->{target} > 0 ? $info->{target} : FALLBACK_SECS;
    $wait = 5 if $wait < 5;
    $pending{$cid} = $info;
    Slim::Utils::Timers::setTimer($client, time() + $wait, \&_markTick, $info);
    return;
}

# Rebuild a player's session from its last entry, if that ended within the session gap.
# Deliberately NOT stopped by a stop or clear seen before it: what LMS sends around a restart
# is unmeasured, and the gap alone decides whether the last entry is still this listen.
sub _restore {
    my ($cid) = @_;
    my $e = eval { Plugins::ListeningHistory::DB::forPlayer($cid, 1)->[0] } or return;
    my $gap = ($prefs->get('session_gap_min') // 30) * 60;
    return if time() - $e->{played_at} > $gap;
    my $plays = Plugins::ListeningHistory::DB::plays($e->{id});
    return unless @$plays;
    $session{$cid} = {
        entry_id    => $e->{id},
        kind        => $e->{kind},
        album_key   => $e->{album_key},
        url         => $e->{url},
        urls        => { map { defined $_->{url} ? ($_->{url} => 1) : () } @$plays },
        last_at     => $e->{played_at},
        resumed_url => $plays->[-1]{url},
    };
    $log->info("Listening History: carrying on entry $e->{id} ($e->{kind}) on $cid after a restart");
    return;
}

# Timer body. A named sub, so killTimers can pair on the coderef.
sub _markTick {
    my ($client, $info) = @_;
    my $cid = $client->id;
    delete $pending{$cid};

    my $nowUrl = eval { $client->playingSong->track->url };
    return unless defined $nowUrl && $nowUrl eq $info->{url};

    # Armed as a station because no length was known at newsong. A stream that has learnt its
    # length since is a TRACK (a podcast episode, an http file): hand it to the 90% rule, or a
    # skip one minute in would be recorded as played.
    if ($info->{station}) {
        my $dur = _duration($client, $client->playingSong, $info->{url}, $info->{remote});
        if ($dur > 0) {
            $info->{station} = 0;
            $info->{target}  = _target($dur);
        }
    }

    # Trust playback progress, not the wall clock: re-arm for the shortfall after a pause.
    my $played = eval { $client->songElapsedSeconds } || 0;
    if ($info->{target} > 0 && $played + 1 < $info->{target}) {
        my $again = $info->{target} - $played;
        $again = 5 if $again < 5;
        $pending{$cid} = $info;
        Slim::Utils::Timers::setTimer($client, time() + $again, \&_markTick, $info);
        return;
    }

    eval { _record($client, $info); 1 }
        or $log->error("Listening History: recording a play failed: $@");
    return;
}

# The track's length in seconds, 0 if unknown. The song's own, else the protocol handler's —
# the same two sources, in the same order, that Sources::describe reads, so the timer here and
# the record there agree about what is a station.
sub _duration {
    my ($client, $song, $url, $remote) = @_;
    my $dur = eval { $song->duration } || 0;
    return $dur if $dur > 0 || !$remote;
    my $m = Plugins::ListeningHistory::Sources::playingMeta($client, $url)->{duration};
    return (defined $m && !ref $m && $m =~ /^[\d.]+$/ && $m > 0) ? $m : 0;
}

sub _target {
    my ($dur) = @_;
    return 0 unless $dur > 0;
    return $dur * ($prefs->get('played_threshold') || 90) / 100;
}

sub _cancel {
    my ($cid) = @_;
    my $p = delete $pending{$cid} or return;
    eval { Slim::Utils::Timers::killTimers($p->{client}, \&_markTick) };
    return;
}

sub _record {
    my ($client, $info) = @_;
    my $cid   = $client->id;
    my $song  = $client->playingSong;
    my $track = $song->track;

    my ($d, $why) = Plugins::ListeningHistory::Sources::describe($client, $song, $track, $info->{url});
    unless ($d) {
        $log->info("Listening History: not recording $info->{url} ($why)");
        return;
    }

    # The first play counted after a restart: the track that was playing when it went down is
    # resumed, and it may already be recorded. Only this one play is checked.
    if (my $s = $session{$cid}) {
        my $resumed = delete $s->{resumed_url};
        if (defined $resumed && $resumed eq $d->{url}) {
            $s->{last_at} = time();   # still this listen: the gap runs from here, not from before the restart
            $log->info("Listening History: not recording $d->{url} again, resumed after a restart");
            return;
        }
    }

    my $now = time();
    my %player = (
        player_id   => $cid,
        player_name => (eval { $client->name } // $cid),
    );

    if ($d->{is_station}) {
        return unless $prefs->get('record_radio');
        my $id = Plugins::ListeningHistory::DB::addEntry({
            %player,
            kind      => 'station',
            source    => 'radio',
            title     => $d->{title},
            artwork   => $d->{artwork},
            url       => $d->{url},
            album_key => $d->{album_key},
            played_at => $now,
        }, { url => $d->{url}, title => $d->{title}, played_at => $now }) or return;
        $session{$cid} = { entry_id => $id, kind => 'station', url => $d->{url}, last_at => $now };
        $log->info("Listening History: station '$d->{title}' on $player{player_name}");
        return;
    }

    my $play = {
        url       => $d->{url},
        title     => $d->{title},
        artist    => $d->{artist},
        album     => $d->{album},
        duration  => $d->{duration},
        played_at => $now,
    };

    my $s   = $session{$cid};
    my $gap = ($prefs->get('session_gap_min') // 30) * 60;
    if ($s && ($s->{kind} // '') ne 'station'
        && defined $d->{album_key} && defined $s->{album_key}
        && $s->{album_key} eq $d->{album_key}
        && !$s->{urls}{ $d->{url} }
        && $info->{started_at} - $s->{last_at} <= $gap)
    {
        my $promote = $s->{kind} eq 'track' ? {
            artist      => $d->{album_artist} // $d->{artist},
            album       => $d->{album},
            year        => $d->{year},
            artwork     => $d->{artwork},
            track_total => $d->{track_total},
            ref         => $d->{ref},
        } : undef;

        if (Plugins::ListeningHistory::DB::addToEntry($s->{entry_id}, $play, $promote)) {
            $s->{kind} = 'album';
            $s->{urls}{ $d->{url} } = 1;
            $s->{last_at} = $now;
            $log->info("Listening History: album '" . ($d->{album} // '') . "' on "
                . "$player{player_name}, " . scalar(keys %{ $s->{urls} }) . ' tracks');
            return;
        }
        # The entry was removed while the album played: start afresh below.
    }

    my $id = Plugins::ListeningHistory::DB::addEntry({
        %player,
        kind        => 'track',
        source      => $d->{source},
        artist      => $d->{artist},
        album       => $d->{album},
        title       => $d->{title},
        year        => $d->{year},
        artwork     => $d->{artwork},
        url         => $d->{url},
        album_key   => $d->{album_key},
        track_total => $d->{track_total},
        ref         => $d->{ref},
        played_at   => $now,
    }, $play) or return;

    # A Qobuz release states its type (album / EP / single) only on its album object: ask once,
    # and store it on the entry when the answer comes (Browse::_releases groups by it).
    if (!$d->{ref}{release_type} && $d->{ref}{svc_album_id}) {
        Plugins::ListeningHistory::Sources::fetchReleaseType($client, $d->{source}, $d->{ref}{svc_album_id}, sub {
            Plugins::ListeningHistory::DB::setReleaseType($id, $_[0]) if $_[0];
        });
    }

    $session{$cid} = {
        entry_id  => $id,
        kind      => 'track',
        album_key => $d->{album_key},
        url       => $d->{url},
        urls      => { $d->{url} => 1 },
        last_at   => $now,
    };
    $log->info("Listening History: track '$d->{title}' on $player{player_name}");
    return;
}

1;
