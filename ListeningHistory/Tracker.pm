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
#   The track's LENGTH is read again at every check, the service's own figure first: a queued
#   streaming track can start before its service knows the length, and Radio Paradise plays every
#   song on ONE url, so at newsong LMS still holds the previous song's length.
#
#   A PAUSE stops the session clock: the time paused does not count towards session_gap_min.
#   A paused streaming track is resumed by LMS as a new stream from the pause point, which
#   arrives as a newsong on the same url. That is the same listen, not a new one: its mark stays,
#   and what was heard before the pause comes off it.
#
#   Radio STATIONS are not recorded (Simon, 2026-09-23). A stream with no length is timed as one
#   for 60s, in case it learns its length (a podcast, Radio Paradise's first song), and its title
#   changes, newsong events on the same url, are ignored. Radio Paradise's station breaks and DJ
#   talk are not recorded either: describe() declines them, and the session carries on untouched.
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
# How far a re-stream may start from the pause point and still be the resume (LMS seeks to the
# pause position, give or take the codec's seek granularity).
use constant RESUME_SLACK => 3;

my %pending;   # per player: { client, url, target, from, base, started_at, station, remote }
my %session;   # per player: { entry_id, kind, album_key, url, urls => {}, last_at, resumed_url, resumed_title }
my %restored;  # per player: 1 once the first newsong since startup has rebuilt its session
my %paused;    # per player: { at, url, pos } while it is paused

sub init {
    Slim::Control::Request::subscribe(\&_onChange, [['playlist'], ['newsong', 'stop', 'clear', 'pause']]);
    $log->info('Listening History tracker subscribed');
    return;
}

sub shutdown {
    Slim::Control::Request::unsubscribe(\&_onChange);
    _cancel($_) for keys %pending;
    %session  = ();
    %restored = ();
    %paused   = ();
    return;
}

sub _onChange {
    my $request = shift;
    my $client  = $request->client or return;
    my $cid     = $client->id;

    if ($request->isCommand([['playlist'], ['stop', 'clear']])) {
        _cancel($cid);
        delete $session{$cid};
        delete $paused{$cid};
        return;
    }

    # ['playlist', 'pause', 1|0] (StreamingController _Pause / _Resume, LMS 9.1).
    if ($request->isCommand([['playlist'], ['pause']])) {
        if ($request->getParam('_newvalue')) {
            $paused{$cid} ||= { at => time(), url => eval { $client->playingSong->track->url },
                                pos => _position($client) };
        }
        else {
            _unpause($cid);
        }
        return;
    }

    my $song  = eval { $client->playingSong } or return;
    my $track = eval { $song->track }         or return;
    my $url   = eval { $track->url };
    return unless defined $url && length $url;

    my $first = !$restored{$cid}++;
    _restore($cid) if $first;

    # A paused REMOTE track is not resumed in place: once the player's buffer is full LMS stops
    # fetching (_CheckPaused), and the resume is a new stream from the pause point (_JumpOrResume
    # -> _JumpToTime), which sends a newsong on the same url and sends no ['playlist','pause',0].
    # It is the same listen: keep its mark, less what was heard before the pause. Only when the new
    # stream starts WHERE IT PAUSED: a seek made while paused, or the next song on a stream that
    # plays every song on one url, starts somewhere else. (Radio Paradise itself cannot pause: its
    # handler refuses, and LMS stops it instead — StreamingController::pause.)
    my $wasPaused = _unpause($cid);
    my $p = $pending{$cid};
    my $from = eval { $song->startOffset } || 0;
    if ($wasPaused && defined $wasPaused->{url} && $wasPaused->{url} eq $url
        && defined $wasPaused->{pos} && abs($from - $wasPaused->{pos}) <= RESUME_SLACK)
    {
        if ($p && $p->{url} eq $url && !$p->{station}) {
            # Credit only what played since THIS mark's stream began (`base`): after a seek the
            # stream began at the seek point, and what lies before it was never heard.
            $p->{from} += $from - ($p->{base} // 0);
            $p->{base}  = $from;
            eval { Slim::Utils::Timers::killTimers($client, \&_markTick) };
            _arm($client, $p, _owed($p) || FALLBACK_SECS);
            return;
        }
        # Already counted before the pause: the rest of it is still that one play.
        my $s = $session{$cid};
        return if $s && $s->{urls} && $s->{urls}{$url};
    }

    my $remote = eval { $track->can('remote') ? $track->remote : undef };
    $remote = ($url !~ m{^file:}i && $url =~ m{^\w+://}) ? 1 : 0 unless defined $remote;
    my $source  = $remote ? Plugins::ListeningHistory::Sources::sourceFromUrl($url) : 'library';
    my $dur     = _duration($client, $song, $url, $remote);
    my $station = Plugins::ListeningHistory::Sources::isStation($source, $dur, $remote);

    # A radio stream announces each new song title as a newsong on the SAME url. That is not a new
    # listen: keep the pending station mark, and never time the station again. Only while the url
    # still has no length: a song WITH one is a track (Radio Paradise's next song, when its first
    # was taken for a station because RP had not described it yet), or every later song is lost.
    if ($station) {
        return if $p && $p->{station} && $p->{url} eq $url;
        my $s = $session{$cid};
        return if $s && ($s->{kind} // '') eq 'station' && ($s->{url} // '') eq $url;
    }

    _cancel($cid);

    my $info = {
        client     => $client,
        url        => $url,
        target     => $station ? 0 : _target($dur),
        from       => 0,      # seconds credited before the current stream (a resume)
        base       => eval { $song->startOffset } || 0,   # where the current stream began in the track
        started_at => time(),
        station    => $station,
        remote     => $remote,
    };
    # The first track after a restart may be resumed where it stopped (local files are, in some
    # circumstances; streams start again from the top). What came before the resume point was
    # heard before the restart, so only the rest of the 90% is still owed. songElapsedSeconds
    # counts from the start of the STREAM, not the track, so it is the resume point, startOffset,
    # that comes off the target. Only here and on a resume from pause (above): a seek also starts
    # a new stream and a newsong, and must still be listened through.
    $info->{from} = eval { $song->startOffset } || 0 if $first;

    _arm($client, $info, _owed($info) || FALLBACK_SECS);
    return;
}

# Arm (or re-arm) the player's mark $wait seconds from now.
sub _arm {
    my ($client, $info, $wait) = @_;
    $wait = 5 if $wait < 5;
    $pending{ $client->id } = $info;
    Slim::Utils::Timers::setTimer($client, time() + $wait, \&_markTick, $info);
    return;
}

# Where in the track the player is, in seconds: LMS's own position (what _Pause stores as the
# resume time), else the stream's start point plus its elapsed.
sub _position {
    my ($client) = @_;
    my $pos = eval { $client->controller->playingSongElapsed };
    return $pos if defined $pos;
    return (eval { $client->playingSong->startOffset } || 0) + (eval { $client->songElapsedSeconds } || 0);
}

# Stream seconds still owed before the mark counts: the target, less what was heard before this
# stream started. 0 when there is no target (no length known).
sub _owed {
    my ($info) = @_;
    return 0 unless ($info->{target} // 0) > 0;
    my $owed = $info->{target} - ($info->{from} || 0);
    return $owed < 1 ? 1 : $owed;
}

# End a pause: the session clock stood still while it lasted, so the last play and the pending
# track's start move on by the time paused. Moving both keeps a pause INSIDE the pending track out
# of the gap, and takes a pause BETWEEN tracks out of it. Returns the pause, or undef.
sub _unpause {
    my ($cid) = @_;
    my $pz = delete $paused{$cid} or return undef;
    my $held = time() - $pz->{at};
    if ($held > 0) {
        my $s = $session{$cid};
        $s->{last_at} += $held if $s && defined $s->{last_at} && $s->{last_at} <= $pz->{at};
        my $p = $pending{$cid};
        $p->{started_at} += $held if $p && $p->{started_at} <= $pz->{at};
    }
    return $pz;
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
        last_at       => $e->{played_at},
        resumed_url   => $plays->[-1]{url},
        resumed_title => $plays->[-1]{title},
    };
    $log->info("Listening History: carrying on entry $e->{id} ($e->{kind}) on $cid after a restart");
    return;
}

# Timer body. A named sub, so killTimers can pair on the coderef.
sub _markTick {
    my ($client, $info) = @_;
    my $cid = $client->id;
    delete $pending{$cid};

    my $song   = eval { $client->playingSong };
    my $nowUrl = eval { $song->track->url };
    return unless defined $nowUrl && $nowUrl eq $info->{url};

    # The length again, at every check: the one read at newsong can be missing (a queued streaming
    # track the service has not described yet) or stale (Radio Paradise: every song on one url, and
    # LMS still holding the previous song's length). A stream armed as a station that has learnt a
    # length is a TRACK (a podcast episode, an http file): hand it to the 90% rule, or a skip one
    # minute in would be recorded as played.
    my $dur = _duration($client, $song, $info->{url}, $info->{remote});
    if ($dur > 0) {
        $info->{station} = 0;
        $info->{target}  = _target($dur);
    }
    elsif ($info->{remote} && !$info->{station} && !($info->{target} > 0)) {
        # A service track, never a station, with no length yet: wait for one rather than count it
        # at 60s. describe() refuses a service track with no length, so this is its only way in.
        return _arm($client, $info, FALLBACK_SECS);
    }

    # Trust playback progress, not the wall clock: re-arm for the shortfall after a pause.
    my $owed   = _owed($info);
    my $played = eval { $client->songElapsedSeconds } || 0;
    return _arm($client, $info, $owed - $played) if $owed > 0 && $played + 1 < $owed;

    eval { _record($client, $info); 1 }
        or $log->error("Listening History: recording a play failed: $@");
    return;
}

# The track's length in seconds, 0 if unknown: Sources::trackDuration, the same figure describe()
# records, so the timer here and the record there agree about what is a station.
sub _duration {
    my ($client, $song, $url, $remote) = @_;
    return Plugins::ListeningHistory::Sources::trackDuration($client, $song, $url, $remote);
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
    # resumed, and it may already be recorded. Only this one play is checked. On a stream that plays
    # every song on ONE url (Radio Paradise) the title decides too: a different song there is a new
    # play. Nowhere else: a service track's title can fall back to LMS's row name just after a
    # restart, and a mismatch there would count the resumed track twice.
    if (my $s = $session{$cid}) {
        my $resumed = delete $s->{resumed_url};
        my $rtitle  = delete $s->{resumed_title};
        if (defined $resumed && $resumed eq $d->{url}
            && (!defined $rtitle || !defined $d->{title} || $rtitle eq $d->{title}
                || !Plugins::ListeningHistory::Sources::sharesUrl($d->{url}, $song)))
        {
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

    # Radio stations are not recorded (Simon, 2026-09-23: a continuous stream says nothing to find
    # again later; Radio Paradise, which names each song, is recorded song by song as tracks, not its
    # station breaks or DJ talk, which describe() has already declined above). The
    # station still ends the album session, and its later title changes are ignored.
    if ($d->{is_station}) {
        $session{$cid} = { kind => 'station', url => $d->{url}, last_at => $now };
        $log->info("Listening History: not recording station '$d->{title}' on $player{player_name}");
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
