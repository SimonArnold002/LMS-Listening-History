#!/usr/bin/env perl
# Tracker.pm end to end: fake players play fake tracks through the REAL subscription
# callback and timers, and the assertions read what landed in a real SQLite store.
#
# Every grouping rule is asserted by its OUTCOME in the database (entry kinds, counts, which
# urls were logged), never by reading Tracker's private state, so a tracker that recorded
# nothing, or everything, fails here.
use strict;
use warnings;
use FindBin;
require "$FindBin::Bin/t_stubs.pl";

main::lh_require(qw(DB Sources Tracker));
main::lh_tempdb();
Slim::Utils::Prefs::set_test_pref('plugin.listeninghistory', $_->[0], $_->[1])
    for [played_threshold => 90], [session_gap_min => 30], [record_radio => 1];

Plugins::ListeningHistory::Tracker->init();
my ($CB) = map { $_->[0] } @Slim::Control::Request::SUBSCRIBED;
ok('the tracker subscribes to playlist events', ref $CB eq 'CODE');

# --- fakes -----------------------------------------------------------------------------
{ package FakeClient;  sub new { my ($c, $id, $name) = @_; bless { id => $id, name => $name, elapsed => 0 }, $c }
  sub id { $_[0]{id} } sub name { $_[0]{name} } sub playingSong { $_[0]{song} } sub songElapsedSeconds { $_[0]{elapsed} } }
# Like LMS: songElapsedSeconds counts from the start of the current STREAM; where a stream
# started inside the track (a resume, a seek) is the song's startOffset.
{ package FakeSong;    sub duration { $_[0]{duration} } sub track { $_[0]{track} } sub startOffset { $_[0]{startOffset} } }
{ package FakeTrack;   sub url { $_[0]{url} } sub title { $_[0]{title} } sub artistName { $_[0]{artist} }
  sub album { $_[0]{album} } sub albumname { $_[0]{albumname} } sub remote { $_[0]{remote} } }
{ package FakeAlbum;   sub id { $_[0]{id} } sub title { $_[0]{title} } sub year { $_[0]{year} }
  sub artwork { $_[0]{artwork} } sub contributor { my $n = $_[0]{artist}; bless { n => $n }, 'FakeContrib' } }
{ package FakeContrib; sub name { $_[0]{n} } }
{ package FakeRequest; sub client { $_[0]{client} }
  sub isCommand { my ($s, $spec) = @_; return scalar grep { $_ eq $s->{cmd} } @{ $spec->[1] } } }

my %ALB;
sub libAlbum {
    my ($id, $title, $artist, $n) = @_;
    Slim::Schema::add_test_album($id, map { [ "T$_", "file:///m/$id/$_.flac" ] } 1 .. $n);
    return $ALB{$id} = bless { id => $id, title => $title, artist => $artist, year => 2001, artwork => "c$id" }, 'FakeAlbum';
}
sub libTrack {
    my ($albumId, $n) = @_;
    my $a = $ALB{$albumId};
    return bless { url => "file:///m/$albumId/$n.flac", title => "T$n", artist => $a->{artist},
                   album => $a, remote => 0 }, 'FakeTrack';
}
sub remoteTrack { my (%t) = @_; return bless { remote => 1, %t }, 'FakeTrack' }

sub event { my ($client, $cmd) = @_; $CB->(bless { client => $client, cmd => $cmd }, 'FakeRequest') }

# Start a track. With listen => 1 (the default) it then plays past the threshold and the
# pending timer fires; with listen => 0 it is left pending.
sub play {
    my ($client, $track, %o) = @_;
    my $dur = exists $o{duration} ? $o{duration} : 200;
    $client->{song}    = bless { duration => $dur, track => $track }, 'FakeSong';
    $client->{elapsed} = 0;
    event($client, 'newsong');
    return unless $o{listen} // 1;
    $client->{elapsed} = $dur * 0.95;
    Slim::Utils::Timers::fire_timer($client);
}

sub entries { Plugins::ListeningHistory::DB::recent(1000) }
sub fresh {
    my $h = Plugins::ListeningHistory::DB::dbh();
    $h->do('DELETE FROM plays'); $h->do('DELETE FROM entries');
    Slim::Utils::Timers::clear();
    Plugins::ListeningHistory::Tracker->shutdown();
    Plugins::ListeningHistory::Tracker->init();
    ($CB) = map { $_->[0] } @Slim::Control::Request::SUBSCRIBED;
}

my $kitchen = FakeClient->new('aa:01', 'Kitchen');
my $lounge  = FakeClient->new('aa:02', 'Lounge');
libAlbum(10, 'Blue Album', 'Band A', 12);
libAlbum(20, 'Red Album',  'Band B', 8);

# --- one track --------------------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
my $e = entries();
is('one track: one entry', scalar @$e, 1);
is('one track: it is a TRACK entry', $e->[0]{kind}, 'track');
is('one track: titled by the track', $e->[0]{title}, 'T1');
is('one track: carries its album', $e->[0]{album}, 'Blue Album');
is('one track: the player is recorded', $e->[0]{player_name}, 'Kitchen');
is('one track: plays the file', $e->[0]{url}, 'file:///m/10/1.flac');

# --- an album, back to back ---------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, $_)) for 1 .. 3;
$e = entries();
is('album: three tracks make ONE entry', scalar @$e, 1);
is('album: promoted to an ALBUM entry', $e->[0]{kind}, 'album');
is('album: counts the tracks heard', $e->[0]{tracks_played}, 3);
is('album: knows the album length from the library', $e->[0]{track_total}, 12);
is('album: the track title is cleared', $e->[0]{title}, undef);
is('album: replays by library album id', $e->[0]{ref}{album_id}, 10);
is('album: all three plays are logged', scalar @{ Plugins::ListeningHistory::DB::plays($e->[0]{id}) }, 3);

# --- A, B, then A again -------------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2));
play($kitchen, libTrack(20, 1));
play($kitchen, libTrack(10, 3));
$e = entries();
is('A,A,B,A: three entries', scalar @$e, 3);
is('A,A,B,A: newest is the lone A track', join(',', map { $_->{kind} } @$e), 'track,track,album');

# --- stop ends the session ----------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
event($kitchen, 'stop');
play($kitchen, libTrack(10, 2));
is('stop between tracks: two entries', scalar @{ entries() }, 2);
is('stop between tracks: neither is an album', scalar(grep { $_->{kind} eq 'album' } @{ entries() }), 0);

# --- the same track twice -----------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 1));
$e = entries();
is('same url twice: not merged into one album of 2', scalar @$e, 2);
is('same url twice: both are track entries', join(',', map { $_->{kind} } @$e), 'track,track');

# --- the session gap ----------------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
TestClock::advance(2 * 3600);
play($kitchen, libTrack(10, 2));
is('two hours apart: two entries', scalar @{ entries() }, 2);

# --- two players --------------------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
play($lounge,  libTrack(10, 2));
play($kitchen, libTrack(10, 2));
$e = entries();
is('two players: one entry each', scalar @$e, 2);
my ($k) = grep { $_->{player_id} eq 'aa:01' } @$e;
my ($l) = grep { $_->{player_id} eq 'aa:02' } @$e;
is('two players: Kitchen became an album', $k->{kind}, 'album');
is('two players: Lounge stayed a track', $l->{kind}, 'track');

# --- a skipped track is never recorded ----------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1), listen => 0);
play($kitchen, libTrack(10, 2));
$e = entries();
is('skip: only the track listened to', scalar @$e, 1);
is('skip: and it is track 2', $e->[0]{title}, 'T2');

# --- a pause delays the mark --------------------------------------------------------------
fresh();
play($kitchen, libTrack(10, 1), listen => 0);
$kitchen->{elapsed} = 30;                         # the timer comes round mid-track
Slim::Utils::Timers::fire_timer($kitchen);
is('pause: nothing recorded at 30s of 200', scalar @{ entries() }, 0);
ok('pause: the mark is re-armed', scalar @Slim::Utils::Timers::ARMED);
$kitchen->{elapsed} = 190;
Slim::Utils::Timers::fire_timer($kitchen);
is('pause: recorded once really played', scalar @{ entries() }, 1);

# --- streaming: grouped by the service album id -------------------------------------------
fresh();
$Slim::Player::ProtocolHandlers::META{qobuz} = {
    'qobuz://1.flac' => { title => 'Q1', artist => 'Q Band', album => 'Q Album', albumId => 'qa1', cover => 'https://img/q.jpg' },
    'qobuz://2.flac' => { title => 'Q2', artist => 'Q Band', album => 'Q Album', albumId => 'qa1', cover => 'https://img/q.jpg' },
};
play($kitchen, remoteTrack(url => 'qobuz://1.flac', title => 'Q1'));
play($kitchen, remoteTrack(url => 'qobuz://2.flac', title => 'Q2'));
$e = entries();
is('qobuz: one album entry', scalar @$e, 1);
is('qobuz: kind', $e->[0]{kind}, 'album');
is('qobuz: source', $e->[0]{source}, 'qobuz');
is('qobuz: replays by the service album id', $e->[0]{ref}{svc_album_id}, 'qa1');
is('qobuz: artwork from the handler', $e->[0]{artwork}, 'https://img/q.jpg');

# --- a service track started from a row keeps the SERVICE's title ------------------------------
# LMS stores the row's name as the track's title (`playlist play <url> <title>`). A Listening History
# track row, or an LMS favourite, is named "Title by Artist from Album": recorded as the title, the
# row then read "... by Artist from Album by Artist from Album".
fresh();
$Slim::Player::ProtocolHandlers::META{qobuz} = {
    'qobuz://n1.flac' => { title => 'Pylon', artist => 'beabadoobee', album => 'Pylon', albumId => 'qn1' },
    'qobuz://n2.flac' => { artist => 'N Band', album => 'N Album', albumId => 'qn2' },
};
play($kitchen, remoteTrack(url => 'qobuz://n1.flac', title => 'Pylon by beabadoobee from Pylon'));
is('service title: the handler\'s title, not the row name LMS stored', entries()->[0]{title}, 'Pylon');
is('service title: the play is logged with it too', Plugins::ListeningHistory::DB::plays(entries()->[0]{id})->[0]{title}, 'Pylon');
fresh();
play($kitchen, remoteTrack(url => 'qobuz://n2.flac', title => 'N Title'));
is('CONTROL service title: a handler with no title falls back to LMS\'s', entries()->[0]{title}, 'N Title');

# --- Qobuz release type: asked once per album, stored on the entry when it answers ---------------
{
    package FakeQobuzAPI;
    our (@CALLS, %TYPE, $DEFER, @PENDING);
    sub getAlbum { my ($s, $cb, $id) = @_; push @CALLS, $id;
                   my $ans = sub { $cb->({ id => $id, release_type => $TYPE{$id} }) };
                   $DEFER ? push(@PENDING, $ans) : $ans->() }
    no warnings 'once';
    *Plugins::Qobuz::Plugin::getAPIHandler = sub { bless {}, 'FakeQobuzAPI' };
}
fresh();
%FakeQobuzAPI::TYPE = (qe1 => 'epmini', qs1 => 'single');   # Qobuz's real spellings
$Slim::Player::ProtocolHandlers::META{qobuz} = {
    'qobuz://e1.flac' => { title => 'E1', artist => 'E Band', album => 'E EP', albumId => 'qe1' },
    'qobuz://e2.flac' => { title => 'E2', artist => 'E Band', album => 'E EP', albumId => 'qe1' },
    'qobuz://s1.flac' => { title => 'S1', artist => 'S Band', album => 'S1',   albumId => 'qs1' },
    'qobuz://s2.flac' => { title => 'S2', artist => 'S Band', album => 'S1',   albumId => 'qs1' },
};
$FakeQobuzAPI::DEFER = 1;
play($kitchen, remoteTrack(url => 'qobuz://e1.flac', title => 'E1'));
is('release type: Qobuz is asked for the album', join(',', @FakeQobuzAPI::CALLS), 'qe1');
play($kitchen, remoteTrack(url => 'qobuz://e2.flac', title => 'E2'));
is('release type: nothing stored before Qobuz answers', entries()->[0]{ref}{release_type}, undef);
$_->() for splice @FakeQobuzAPI::PENDING;
$e = entries();
is('release type: an answer after the album promotion lands on the entry', $e->[0]{ref}{release_type}, 'EP');
is('release type: and the album reference survives it', $e->[0]{ref}{svc_album_id}, 'qe1');
is('release type: an EP played through is ONE entry', scalar @$e, 1);
is('release type: asked once, not once per track', scalar @FakeQobuzAPI::CALLS, 1);
$FakeQobuzAPI::DEFER = 0;
fresh();
play($kitchen, remoteTrack(url => 'qobuz://e1.flac', title => 'E1'));
is('release type: a later play of the same album is not asked again', scalar @FakeQobuzAPI::CALLS, 1);
is('release type: it is stored straight away from the run\'s answer', entries()->[0]{ref}{release_type}, 'EP');
play($kitchen, remoteTrack(url => 'qobuz://s1.flac', title => 'S1'));
play($kitchen, remoteTrack(url => 'qobuz://s2.flac', title => 'S2'));
$e = entries();
is('release type: an answer BEFORE the promotion is kept through it', $e->[0]{ref}{release_type}, 'SINGLE');
is('release type: a two-track single is one entry', $e->[0]{kind}, 'album');
{
    my @got;
    my $F = \&Plugins::ListeningHistory::Sources::fetchReleaseType;
    @FakeQobuzAPI::CALLS = ();
    $F->($kitchen, 'qobuz', 'qs1', sub { push @got, $_[0] }) for 1, 2;
    is('fetchReleaseType: a known album answers from this run, no second call', scalar @FakeQobuzAPI::CALLS, 0);
    is('fetchReleaseType: both callers get the type', join(',', @got), 'SINGLE,SINGLE');
    $F->($kitchen, 'qobuz', 'qx9', sub { push @got, $_[0] // 'undef' });
    is('fetchReleaseType: an album Qobuz gives no type for answers undef', $got[-1], 'undef');
    $F->($kitchen, 'tidal', 'qs1', sub { push @got, $_[0] // 'undef' });
    is('fetchReleaseType: any other source answers undef at once', $got[-1], 'undef');
}
fresh();
@FakeQobuzAPI::CALLS = ();
$Slim::Player::ProtocolHandlers::META{deezer} = {
    'deezer://d1.mp3' => { title => 'D1', artist => 'D', album => 'D LP', albumId => 'dz1' } };
play($kitchen, remoteTrack(url => 'deezer://d1.mp3', title => 'D1'));
is('CONTROL: a Deezer album id asks nobody', scalar @FakeQobuzAPI::CALLS, 0);
is('CONTROL: and stores no type', entries()->[0]{ref}{release_type}, undef);

# --- streaming with no album id: grouped by album + FIRST credit ---------------------------
fresh();
$Slim::Player::ProtocolHandlers::META{deezer} = {
    'deezer://1' => { title => 'D1', artist => 'Kygo, Khalid', album => 'Golden Hour' },
    'deezer://2' => { title => 'D2', artist => 'Kygo',         album => 'Golden Hour' },
    'deezer://3' => { title => 'D3', artist => 'Other Act',    album => 'Golden Hour' },
};
play($kitchen, remoteTrack(url => 'deezer://1'));
play($kitchen, remoteTrack(url => 'deezer://2'));
play($kitchen, remoteTrack(url => 'deezer://3'));
$e = entries();
is('deezer: a feature credit still groups; another artist does not', scalar @$e, 2);
is('deezer: the grouped pair is an album of 2', (grep { $_->{kind} eq 'album' } @$e)[0]{tracks_played}, 2);

# --- Spotty's error answer is never recorded -----------------------------------------------
fresh();
$Slim::Player::ProtocolHandlers::META{spotify} = { title => 'Please authorize this player', artist => 'Please authorize this player', duration => 0 };
play($kitchen, remoteTrack(url => 'spotify://track:x'), duration => 0);
is('spotify error text (no duration): nothing recorded', scalar @{ entries() }, 0);
$Slim::Player::ProtocolHandlers::META{spotify} = { title => 'Real Song', artist => 'Real Artist', album => 'Real Album', duration => 180 };
play($kitchen, remoteTrack(url => 'spotify://track:y'), duration => 180);
is('spotify control: a real track IS recorded', scalar @{ entries() }, 1);

# --- radio: one station entry per session --------------------------------------------------
fresh();
$Slim::Player::ProtocolHandlers::META{http} = { title => 'Now: Some Song' };
my $station = remoteTrack(url => 'http://stream.example/radio', title => 'Radio Example');
play($kitchen, $station, duration => 0, listen => 0);
my $deadline = $Slim::Utils::Timers::ARMED[0]{when};
for (1 .. 3) { TestClock::advance(20); event($kitchen, q(newsong)) }   # stream title changes, same url
is(q(radio: title changes do not push the mark back), $Slim::Utils::Timers::ARMED[0]{when}, $deadline);
is('radio: title changes keep ONE pending mark', scalar @Slim::Utils::Timers::ARMED, 1);
Slim::Utils::Timers::fire_timer($kitchen);
event($kitchen, 'newsong');                       # another title change after it is logged
Slim::Utils::Timers::fire_timer($kitchen);
$e = entries();
is('radio: one entry', scalar @$e, 1);
is('radio: a station entry', $e->[0]{kind}, 'station');
is('radio: named after the station, not the song', $e->[0]{title}, 'Radio Example');
is('radio: plays the station url', $e->[0]{url}, 'http://stream.example/radio');

fresh();
Slim::Utils::Prefs::set_test_pref('plugin.listeninghistory', record_radio => 0);
play($kitchen, $station, duration => 0);
is('radio off: nothing recorded', scalar @{ entries() }, 0);
Slim::Utils::Prefs::set_test_pref('plugin.listeninghistory', record_radio => 1);

# --- a remote track whose length is not known at the start is NOT timed as radio ----------
# Song duration 0 at newsong, but the handler knows the length: the 90% rule applies.
fresh();
$Slim::Player::ProtocolHandlers::META{https} = { 'https://pod.example/ep1.mp3' =>
    { title => 'Episode 1', artist => 'A Podcast', album => 'The Show', duration => 300 } };
play($kitchen, remoteTrack(url => 'https://pod.example/ep1.mp3', title => 'Episode 1'), duration => 0, listen => 0);
ok('podcast, handler knows the length: not armed at the 60s radio fallback',
   ($Slim::Utils::Timers::ARMED[0]{when} // 0) - TestClock::now() > 200);

# Neither knows at the start; the song learns its length later. A skip at 61s must not count.
fresh();
$Slim::Player::ProtocolHandlers::META{https} = { 'https://pod.example/ep2.mp3' => { title => 'Episode 2' } };
play($kitchen, remoteTrack(url => 'https://pod.example/ep2.mp3', title => 'Episode 2'), duration => 0, listen => 0);
$kitchen->{song}{duration} = 300;                  # the stream reports its length once playing
$kitchen->{elapsed} = 61;
Slim::Utils::Timers::fire_timer($kitchen);
is('podcast learns its length: not recorded at 61s of 300', scalar @{ entries() }, 0);
$kitchen->{elapsed} = 280;
Slim::Utils::Timers::fire_timer($kitchen);
$e = entries();
is('podcast learns its length: recorded once really played', scalar @$e, 1);
is('podcast learns its length: as a TRACK, not a station', $e->[0]{kind} // '', 'track');

# --- an entry removed mid-album is not written into ----------------------------------------
fresh();
play($kitchen, libTrack(10, 1));
Plugins::ListeningHistory::DB::remove(entries()->[0]{id});
play($kitchen, libTrack(10, 2));
$e = entries();
is('removed mid-album: the next track starts a new entry', scalar @$e, 1);
is('removed mid-album: as a track, with its own title', $e->[0]{title}, 'T2');

# --- a server restart: the session is rebuilt from the database ---------------------------
# restart() is what a server restart does to the tracker: its memory goes, the database stays.
sub restart {
    Slim::Utils::Timers::clear();
    Plugins::ListeningHistory::Tracker->shutdown();
    Plugins::ListeningHistory::Tracker->init();
    ($CB) = map { $_->[0] } @Slim::Control::Request::SUBSCRIBED;
}
sub urlsOf { join ',', map { $_->{url} =~ m{/(\d+)\.flac$} ? $1 : $_->{url} } @{ Plugins::ListeningHistory::DB::plays($_[0]) } }

fresh();
play($kitchen, libTrack(10, $_)) for 1 .. 3;
restart();
play($kitchen, libTrack(10, 3));                  # resumed from Now Playing, already counted
play($kitchen, libTrack(10, 4));
$e = entries();
is('restart mid-album: still ONE entry', scalar @$e, 1);
is('restart mid-album: still an album', $e->[0]{kind}, 'album');
is('restart mid-album: the resumed track is not counted twice', $e->[0]{tracks_played}, 4);
is('restart mid-album: plays logged once each', urlsOf($e->[0]{id}), '1,2,3,4');

# Local music resumed part way through a track not yet counted: LMS streams from the resume
# point (startOffset 160) and songElapsedSeconds starts again at 0. Only the rest is owed, or
# the track ends before the mark and a track heard in full is never recorded.
fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2), listen => 0);     # down at 80% of track 2
restart();
$kitchen->{song}    = bless { duration => 200, track => libTrack(10, 2), startOffset => 160 }, 'FakeSong';
$kitchen->{elapsed} = 0;
event($kitchen, 'newsong');
my $due = ($Slim::Utils::Timers::ARMED[0]{when} // 1e12) - TestClock::now();
ok('resumed at 80%: the mark is due before the track ends (40s left)', $due <= 40);
$kitchen->{elapsed} = 38;
Slim::Utils::Timers::fire_timer($kitchen) if $due <= 40;
play($kitchen, libTrack(10, 3));
is('resumed at 80%: the resumed track is recorded', urlsOf(entries()->[0]{id}), '1,2,3');

# CONTROL: a seek in normal play also starts a new stream at an offset with a newsong. It is not
# a resume: the 90% is still owed, so seeking to the end is not a listen.
fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2), listen => 0);
$kitchen->{song}    = bless { duration => 200, track => libTrack(10, 2), startOffset => 190 }, 'FakeSong';
$kitchen->{elapsed} = 0;
event($kitchen, 'newsong');                       # the seek
$due = ($Slim::Utils::Timers::ARMED[0]{when} // 1e12) - TestClock::now();
ok('CONTROL seek to 95%: the mark is not shortened', $due > 10);
play($kitchen, libTrack(10, 3));
is('CONTROL seek to 95%: the sought track is not recorded', urlsOf(entries()->[0]{id}), '1,3');

# Streaming after a restart starts the track again from the top: heard in full, but already
# counted before the restart, so it is not counted twice and the album carries on.
fresh();
$Slim::Player::ProtocolHandlers::META{qobuz} = { map { ("qobuz://r$_.flac" =>
    { title => "R$_", artist => 'R Band', album => 'R Album', albumId => 'qr1' }) } 1 .. 3 };
play($kitchen, remoteTrack(url => "qobuz://r$_.flac", title => "R$_")) for 1, 2;
restart();
play($kitchen, remoteTrack(url => 'qobuz://r2.flac', title => 'R2'));
play($kitchen, remoteTrack(url => 'qobuz://r3.flac', title => 'R3'));
$e = entries();
is('streaming restart from the top: one entry', scalar @$e, 1);
is('streaming restart from the top: three tracks, the restarted one once', $e->[0]{tracks_played}, 3);

# A long track counted before the restart and heard again after it: the gap runs from the
# resume, not from the count before the restart, or the album splits again.
fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2), duration => 1500);
restart();
TestClock::advance(20 * 60);                      # restart time, then 20 minutes of track 2 again
play($kitchen, libTrack(10, 2), duration => 1500);
TestClock::advance(20 * 60);
play($kitchen, libTrack(10, 3));
$e = entries();
is('restart in a long track: the next track still joins the album', scalar @$e, 1);
is('restart in a long track: three tracks, the resumed one once', urlsOf($e->[0]{id}), '1,2,3');

fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2));
play($kitchen, libTrack(10, 3), listen => 0);     # down at half way through track 3
restart();
play($kitchen, libTrack(10, 3));
$e = entries();
is('restart before the track counted: it joins the album', scalar @$e, 1);
is('restart before the track counted: and IS counted', urlsOf($e->[0]{id}), '1,2,3');

fresh();
play($kitchen, libTrack(10, 1));
restart();
play($kitchen, libTrack(10, 1));
is('restart on a single track: not counted twice', scalar @{ entries() }, 1);
play($kitchen, libTrack(10, 2));
$e = entries();
is('restart on a single track: the next one makes it an album', $e->[0]{kind}, 'album');
is('restart on a single track: of two', $e->[0]{tracks_played}, 2);

fresh();
play($kitchen, libTrack(10, 1));
restart();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 1));                  # played again on purpose
is('restart: only the FIRST play is taken as the resume, a replay still counts', scalar @{ entries() }, 2);

fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2));
restart();
play($kitchen, libTrack(20, 1));                  # something else entirely
$e = entries();
is('restart then another album: a new entry', scalar @$e, 2);
is('restart then another album: the old one is untouched', $e->[1]{tracks_played}, 2);

fresh();
play($kitchen, libTrack(10, 1));
play($kitchen, libTrack(10, 2));
restart();
play($kitchen, libTrack(10, 3));
event($kitchen, 'stop');
play($kitchen, libTrack(10, 4));
$e = entries();
is('restart then stop: the stop still ends the session', scalar @$e, 2);
is('restart then stop: the album carried on before it', $e->[1]{tracks_played}, 3);

fresh();
play($kitchen, libTrack(10, 1));
TestClock::advance(2 * 3600);
restart();
play($kitchen, libTrack(10, 1));
is('CONTROL restart after the gap: a new listen', scalar @{ entries() }, 2);

fresh();
play($kitchen, libTrack(10, 1));
restart();
play($lounge, libTrack(10, 1));
is('restart: another player does not carry on Kitchen\'s entry', scalar @{ entries() }, 2);

fresh();
play($kitchen, $station, duration => 0);
restart();
play($kitchen, $station, duration => 0);
Slim::Utils::Timers::fire_timer($kitchen);
is('restart on radio: the station is not logged again', scalar @{ entries() }, 1);

main::done();
