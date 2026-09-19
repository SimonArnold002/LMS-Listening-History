#!/usr/bin/env perl
# Browse.pm, the context menu, and Settings: the shelf's shape and size, what each row type
# is, how an album row resolves (whole album vs the recorded tracks), search dispatch, and
# the checkbox that must be able to turn off.
use strict;
use warnings;
use FindBin;
use POSIX ();
require "$FindBin::Bin/t_stubs.pl";

main::lh_require(qw(DB Sources Browse Settings HomeExtras));
main::lh_tempdb();
my $B = 'Plugins::ListeningHistory::Browse';

sub add {
    my (%e) = @_;
    my $plays = delete $e{plays} || [ { url => $e{url}, title => $e{title} } ];
    my $id = Plugins::ListeningHistory::DB::addEntry({
        kind => 'track', source => 'library', player_id => 'p1', player_name => 'Kitchen',
        played_at => time(), %e }, shift @$plays);
    Plugins::ListeningHistory::DB::addToEntry($id, $_) for @$plays;
    return $id;
}
sub feed { my ($code, @args) = @_; my $out; $code->(undef, sub { $out = shift }, @args); return $out->{items} }
# The first line Material shows: Slim::Control::XMLBrowser sends (line1 || name) . "\n" . line2 when
# line2 is set, and the bare name otherwise. The web skins show `name` alone.
sub shown { my ($r) = @_; return defined $r->{line2} ? ($r->{line1} // $r->{name}) : $r->{name} }

# --- the shelf -----------------------------------------------------------------------------------
my $now = time();
add(title => "Song $_", artist => 'A', url => "file:///$_", played_at => $now) for 1 .. 60;
my $shelf = feed(\&Plugins::ListeningHistory::Browse::homeShelf, {});
is('shelf: exactly 50 of 60', scalar @$shelf, 50);
is('shelf: flat — no header or text rows', scalar(grep { ($_->{type} // '') =~ /header|text/ } @$shelf), 0);
is('shelf: newest first even when played_at ties', shown($shelf->[0]), "Song 60");
my $again = feed(\&Plugins::ListeningHistory::Browse::homeShelf, {});
is('shelf: the same order on every request', join('|', map { shown($_) } @$again), join('|', map { shown($_) } @$shelf));
my @ex = @Plugins::MaterialSkin::HomeExtraBase::INIT;
Plugins::ListeningHistory::HomeExtras->initPlugin;
my $reg = $Plugins::MaterialSkin::HomeExtraBase::INIT[-1];
is('home extra: registered under LHHome', $reg->{tag}, 'LHHome');

Plugins::ListeningHistory::DB::dbh()->do($_) for 'DELETE FROM plays', 'DELETE FROM entries';

# --- row types --------------------------------------------------------------------------------------
Slim::Schema::add_test_album(5, ['One', 'file:///a/1'], ['Two', 'file:///a/2'], ['Three', 'file:///a/3']);
my $lib = add(kind => 'album', artist => 'Lib', album => 'Local LP', url => 'file:///a/1', track_total => 3,
              tracks_played => 2, ref => { album_id => 5 },
              plays => [ { url => 'file:///a/1', title => 'One' }, { url => 'file:///a/2', title => 'Two' } ]);
my $trk = add(title => 'Solo', artist => 'Lib', album => 'Local LP', url => 'file:///a/3');
my $sta = add(kind => 'station', source => 'radio', title => 'Jazz FM', url => 'http://jazz/stream');
my %row = map { shown($_) => $_ } @{ feed(\&Plugins::ListeningHistory::Browse::_recent, {}) };

my $albumRow = $row{'Local LP'};
is('album row: type playlist', $albumRow->{type}, 'playlist');
ok('album row: a coderef url', ref $albumRow->{url} eq 'CODE');
# The same two lines as any release in LMS: title on top, artist underneath, nothing else.
is('album row: the album on top', $albumRow->{line1}, 'Local LP');
is('album row: the artist underneath, and only the artist', $albumRow->{line2}, 'Lib');
# The Default / Classic web skins draw `name` alone, so it keeps the artist, worded as LMS's own
# web lists word it (core string BY; the stub returns the token).
is('album row: the web-skin name keeps the artist', $albumRow->{name}, 'Local LP BY Lib');
is('track row: the web-skin name keeps the artist', $row{'Solo'}{name}, 'Solo BY Lib');
is('station row: the name alone, no "by"', $row{'Jazz FM'}{name}, 'Jazz FM');
is('album row: has the "…" menu', $albumRow->{itemActions}{info}{command}[1], 'contextmenu');
is('track row: type audio', $row{'Solo'}{type}, 'audio');
is('track row: plays its url', $row{'Solo'}{url}, 'file:///a/3');
is('track row: the artist underneath, and only the artist', $row{'Solo'}{line2}, 'Lib');
is('station row: type audio', $row{'Jazz FM'}{type}, 'audio');
is('station row: plays the station', $row{'Jazz FM'}{url}, 'http://jazz/stream');
ok('station row: no second line (a station has no artist)', !exists $row{'Jazz FM'}{line2});

# --- service badge (extid) and no service name in line2 ---------------------------------------------
{
    my $R = sub { Plugins::ListeningHistory::Browse::entryRow(undef, { kind => 'track', played_at => 1, %{ $_[0] } }) };
    ok('library row: no extid (no badge)', !exists $albumRow->{extid} && !exists $row{'Solo'}{extid});
    is('plain radio: no extid', $row{'Jazz FM'}{extid}, undef);
    is('qobuz track: badge prefix', $R->({ source => 'qobuz', url => 'qobuz://1.flac' })->{extid}, 'qobuz:');
    is('tidal track', $R->({ source => 'tidal', url => 'tidal://2.flc' })->{extid}, 'tidal:');
    is('spotify track', $R->({ source => 'spotify', url => 'spotify://track:x' })->{extid}, 'spotify:');
    is('deezer podcast wears the Deezer badge', $R->({ source => 'deezerpodcast', url => 'deezerpodcast://1' })->{extid}, 'deezer:');
    is('bandcamp track', $R->({ source => 'bandcamp', url => 'bandcamp://x' })->{extid}, 'bandcamp:');
    is('Radio Paradise station: badged from its url', $R->({ kind => 'station', source => 'radio', url => 'radioparadise://4.flac' })->{extid}, 'radioparadise:');
    is('BBC Sounds station: sounds:// maps to the bbc badge', $R->({ kind => 'station', source => 'radio', url => 'sounds://live:bbc_6music' })->{extid}, 'bbc:');
    is('a plain web track: no badge', $R->({ source => 'https', url => 'https://x/1.mp3' })->{extid}, undef);
    my $qa = add(kind => 'album', source => 'qobuz', artist => 'Q', album => 'Q LP', url => 'qobuz://9.flac',
                 ref => { svc_album_id => 'abc123', svc => 'qobuz' });
    my ($qrow) = grep { (shown($_) // '') eq 'Q LP' } @{ feed(\&Plugins::ListeningHistory::Browse::_recent, {}) };
    is('album row with the service album id: the real extid, through the DB', $qrow->{extid}, 'qobuz:album:abc123');
    is('album row with no id: bare prefix', $R->({ kind => 'album', source => 'deezer', url => 'deezer://1.mp3' })->{extid}, 'deezer:');
    my $qt = $R->({ source => 'qobuz', url => 'qobuz://1.flac', artist => 'Q Artist', player_name => 'Kitchen' });
    is('line2 is the artist alone: no service, no player, no time', $qt->{line2}, 'Q Artist');
    my $bare = $R->({ source => 'qobuz', url => 'qobuz://2.flac', title => 'Bare' });
    ok('no artist, no second line and no line1', !exists $bare->{line2} && !exists $bare->{line1});
    is('no artist: the web-skin name is the title alone', $bare->{name}, 'Bare');
    Plugins::ListeningHistory::DB::remove($qa);
}

# --- By album: a tile reads like a release and wears the badge of its latest play ---------------------
{
    my $old = add(kind => 'album', source => 'deezer', artist => 'M', album => 'Mix LP', url => 'deezer://1.mp3',
                  played_at => time() - 100);
    my $new = add(kind => 'album', source => 'qobuz', artist => 'M', album => 'Mix LP', url => 'qobuz://2.flac',
                  ref => { svc_album_id => 'mx9' }, played_at => time());
    my %t = map { shown($_) => $_ } @{ feed(\&Plugins::ListeningHistory::Browse::_albums, {}) };
    ok('by album: named by the album alone, no artist, no count', exists $t{'Mix LP'} && exists $t{'Local LP'});
    is('by album: the artist underneath', $t{'Mix LP'}{line2}, 'M');
    is('by album: the web-skin name keeps the artist', $t{'Mix LP'}{name}, 'Mix LP BY M');
    is('by album: the badge of the LATEST play, not the older one', $t{'Mix LP'}{extid}, 'qobuz:album:mx9');
    ok('CONTROL: a library album has no badge', !exists $t{'Local LP'}{extid});
    ok('by album: a station is not an album tile', !exists $t{'Jazz FM'});
    ok('by album: still drills into that album\'s plays', ref $t{'Mix LP'}{url} eq 'CODE');
    Plugins::ListeningHistory::DB::remove($_) for $old, $new;
}

# --- album resolution ----------------------------------------------------------------------------------
my $tracks = feed($albumRow->{url}, {}, $albumRow->{passthrough}[0]);
is('library album: the WHOLE album, not just what was played', join(',', map { $_->{url} } @$tracks),
   'file:///a/1,file:///a/2,file:///a/3');

my $dz = add(kind => 'album', source => 'deezer', artist => 'D', album => 'No Id', url => 'deezer://1', tracks_played => 2,
             plays => [ { url => 'deezer://1', title => 'D1' }, { url => 'deezer://2', title => 'D2' } ]);
$tracks = feed(\&Plugins::ListeningHistory::Browse::_entryTracks, {}, { id => $dz });
is('album with no service id: the recorded tracks, in order', join(',', map { $_->{url} } @$tracks), 'deezer://1,deezer://2');

# A Qobuz album the service CAN rebuild: its info rows are not tracks.
{ no strict 'refs'; no warnings 'once';
  *{'Plugins::Qobuz::Plugin::QobuzGetTracks'} = sub {
      my ($c, $cb, $a, $pt) = @_;
      return $cb->({ items => [] }) if $pt->{album_id} eq 'empty';
      $cb->({ items => [ { name => 'Credits' }, { name => 'Q1', type => 'audio', url => 'qobuz://1.flac' },
                         { name => 'Q2', type => 'audio', url => 'qobuz://2.flac' }, { name => 'Copyright' } ] });
  };
}
my $qb = add(kind => 'album', source => 'qobuz', album => 'Q', url => 'qobuz://1.flac', tracks_played => 2,
             ref => { svc => 'qobuz', svc_album_id => 'qa1' },
             plays => [ { url => 'qobuz://1.flac' }, { url => 'qobuz://9.flac' } ]);
$tracks = feed(\&Plugins::ListeningHistory::Browse::_entryTracks, {}, { id => $qb });
is('qobuz album: rebuilt from the service, info rows dropped', join(',', map { $_->{url} } @$tracks), 'qobuz://1.flac,qobuz://2.flac');
my $qe = add(kind => 'album', source => 'qobuz', album => 'Q', url => 'qobuz://1.flac', tracks_played => 2,
             ref => { svc => 'qobuz', svc_album_id => 'empty' },
             plays => [ { url => 'qobuz://1.flac' }, { url => 'qobuz://9.flac' } ]);
$tracks = feed(\&Plugins::ListeningHistory::Browse::_entryTracks, {}, { id => $qe });
is('qobuz album the service returns nothing for: the recorded tracks', join(',', map { $_->{url} } @$tracks), 'qobuz://1.flac,qobuz://9.flac');

# --- search dispatch ------------------------------------------------------------------------------------
my $res = feed(\&Plugins::ListeningHistory::Browse::topLevel, { params => { search => 'Jazz' } });
is('topLevel with a search param: results under the sort row', $res->[1]{name}, 'Jazz FM');
$res = feed(\&Plugins::ListeningHistory::Browse::topLevel, { params => { search => 'Jazz', item_id => '1' } });
is('topLevel with search AND item_id: the menu, not results', $res->[0]{name}, 'PLUGIN_LH_RECENT');
is('topLevel: the search row is type search', $res->[1]{type}, 'search');
ok('topLevel: has the By service tile', grep { ($_->{name} // '') eq 'PLUGIN_LH_BY_SERVICE' } @$res);
$res = feed(\&Plugins::ListeningHistory::Browse::topLevel, { params => { search => 'zzzz' } });
is('search with no match says so', $res->[0]{name}, 'PLUGIN_LH_NO_RESULTS');

# --- by date / artist / player menus ---------------------------------------------------------------------
my $months = feed(\&Plugins::ListeningHistory::Browse::_months, {});
is('by date: Today first', $months->[0]{name}, 'PLUGIN_LH_TODAY');
my $today = feed($months->[0]{url}, {}, $months->[0]{passthrough}[0]);
ok('by date: Today lists today\'s entries', scalar(grep { ($_->{name} // '') eq 'Jazz FM' } @$today));
my $players = feed(\&Plugins::ListeningHistory::Browse::_players, {});
like_('by player: one row per player with a count', $players->[0]{name}, qr/^Kitchen \(\d+\)$/);

# --- "Yesterday" across the spring clock change ---------------------------------------------------
# 00:30 on 30 March 2026 in London is 23 hours after 00:30 on 29 March: now-minus-86400 lands on
# the 28th. Yesterday must still be the 29th.
{
    local $ENV{TZ} = 'Europe/London';
    POSIX::tzset();
    my $when = POSIX::mktime(0, 30, 0, 30, 2, 126);      # 2026-03-30 00:30 local
    my $save = $TestClock::OFFSET;
    $TestClock::OFFSET = 0;
    TestClock::advance($when - time());
    my $m = feed(\&Plugins::ListeningHistory::Browse::_months, {});
    is('Yesterday across the clock change is the 29th', $m->[1]{passthrough}[0]{ymd}, '2026-03-29');
    is('Today is the 30th', $m->[0]{passthrough}[0]{ymd}, '2026-03-30');
    $TestClock::OFFSET = $save;
}
POSIX::tzset();

# --- the sort row ----------------------------------------------------------------------------------
{
    Plugins::ListeningHistory::DB::dbh()->do($_) for 'DELETE FROM plays', 'DELETE FROM entries';
    my $p = Slim::Utils::Prefs::preferences('plugin.listeninghistory');
    $p->set('sort', 'date');
    add(title => 'Zeta',  artist => 'Beta',  album => 'Alpha LP', url => 'file:///z', played_at => time() - 30);
    add(title => 'Alpha', artist => 'Alpha', album => 'Zulu LP',  url => 'file:///a', played_at => time() - 20);
    add(title => 'Mid',   artist => '',      album => 'Mid LP',   url => 'file:///m', played_at => time() - 10);
    my $names = sub { join ',', map { $_->{url} } grep { ($_->{type} // '') eq 'audio' } @{ feed(\&Plugins::ListeningHistory::Browse::_recent, {}) } };
    my $list  = feed(\&Plugins::ListeningHistory::Browse::_recent, {});
    like_('sort row: first in the list', $list->[0]{name}, qr/^Sorted by PLUGIN_LH_SORT_DATE/);
    is('sort row: refreshes the view in place', $list->[0]{nextWindow}, 'refresh');
    is('sort by date: newest first', $names->(), 'file:///m,file:///a,file:///z');
    feed($list->[0]{url}, {});
    is('tapping it moves to artist', $p->get('sort'), 'artist');
    is('sort by artist: A-Z, blank artist last', $names->(), 'file:///a,file:///z,file:///m');
    feed($list->[0]{url}, {});   # a STALE row: still steps from the live pref
    is('a stale row still steps forward from the live pref', $p->get('sort'), 'album');
    is('sort by album: A-Z', $names->(), 'file:///z,file:///m,file:///a');
    feed($list->[0]{url}, {});
    is('and round to date again', $p->get('sort'), 'date');
    my $mat = feed($list->[0]{url}, {});
    is('Material: the answer is EMPTY, so nextWindow re-walks in place', scalar @$mat, 0);
    my $web = feed($list->[0]{url}, { isWeb => 1 });
    is('web skin: still advances the sort', $p->get('sort'), 'album');
    is('web skin: one row, not a blank page', scalar @$web, 1);
    is('web skin: a textarea (a text row would be escaped)', $web->[0]{type}, 'textarea');
    like_('web skin: sends the browser back up to the list', $web->[0]{name}, qr/i\.splice\(-1,1\).*location\.replace/s);
    my $cli = feed($list->[0]{url}, { params => { feedMode => 1 } });
    is('web skin via CLI feedMode: bounces too', $cli->[0]{type}, 'textarea');
    $p->set('sort', 'date');
    $p->set('sort', 'artist');
    my $shelf = feed(\&Plugins::ListeningHistory::Browse::homeShelf, {});
    is('the home shelf ignores the sort and has no sort row', join(',', map { $_->{url} } @$shelf),
       'file:///m,file:///a,file:///z');
    $p->set('sort', 'bogus');
    is('an unknown sort pref falls back to date', $names->(), 'file:///m,file:///a,file:///z');
    $p->set('sort', 'date');
}

# --- by service ------------------------------------------------------------------------------------
{
    add(kind => 'station', source => 'radio', title => 'Jazz FM', url => 'http://jazz/stream');
    add(source => 'qobuz', title => 'Q', artist => 'Q', url => 'qobuz://1.flac');
    my $svc = feed(\&Plugins::ListeningHistory::Browse::_services, {});
    is('by service: one row per source, labelled and counted', join('|', map { $_->{name} } @$svc),
       'Library (3)|Qobuz (1)|Radio (1)');
    my ($q) = grep { $_->{name} =~ /^Qobuz/ } @$svc;
    my $rows = feed($q->{url}, {}, $q->{passthrough}[0]);
    is('by service: only that source', join(',', map { $_->{url} } grep { ($_->{type} // '') eq 'audio' } @$rows), 'qobuz://1.flac');
    add(source => 'deezer',        title => 'D',  artist => 'D', url => 'deezer://1.mp3');
    add(source => 'deezerpodcast', title => 'DP', artist => 'D', url => 'deezerpodcast://1');
    add(source => 'http',          title => 'H',  artist => 'H', url => 'http://x/1.mp3');
    add(source => 'https',         title => 'HS', artist => 'H', url => 'https://x/2.mp3');
    $svc = feed(\&Plugins::ListeningHistory::Browse::_services, {});
    is('by service: Deezer music and Deezer podcasts are told apart; http + https are ONE row',
       join('|', map { $_->{name} } @$svc),
       'Deezer (1)|Deezer podcasts (1)|Library (3)|Qobuz (1)|Radio (1)|Web stream (2)');
    my ($w) = grep { $_->{name} =~ /^Web stream/ } @$svc;
    $rows = feed($w->{url}, {}, $w->{passthrough}[0]);
    is('by service: a merged row lists every source it stands for',
       join(',', sort map { $_->{url} } grep { ($_->{type} // '') eq 'audio' } @$rows), 'http://x/1.mp3,https://x/2.mp3');
    my ($d) = grep { $_->{name} =~ /^Deezer \(/ } @$svc;
    $rows = feed($d->{url}, {}, $d->{passthrough}[0]);
    is('by service: Deezer holds no podcast episode', join(',', map { $_->{url} } grep { ($_->{type} // '') eq 'audio' } @$rows), 'deezer://1.mp3');
}

# --- date search ------------------------------------------------------------------------------------
{
    my $P = \&Plugins::ListeningHistory::Browse::parseDateSearch;
    my $day = sub { my ($d, $m, $y) = @_; POSIX::mktime(0, 0, 0, $d, $m - 1, $y - 1900) };
    my $range = sub { join '..', map { defined $_ ? $_ : 'none' } $P->($_[0]) };
    my $one = join '..', $day->(18, 9, 2026), $day->(19, 9, 2026);
    is("date search: $_", $range->($_), $one) for
        '18/09/2026', '18-09-2026', '18.09.2026', '18/9/26', '2026-09-18', '18 Sep 2026',
        '18 September 2026', '18th Sept 2026', '  18/09/2026 ';
    my $span = join '..', $day->(1, 9, 2026), $day->(16, 9, 2026);
    is("date range: $_", $range->($_), $span) for
        '01/09/2026 - 15/09/2026', '1/9/2026 to 15/9/2026', "01/09/2026 \x{2013} 15/09/2026",
        '15/09/2026 - 01/09/2026', '2026-09-01 - 2026-09-15';
    is("not a date: $_", $range->($_), '') for
        '31/02/2026', '13/13/2026', 'Radiohead', '2026', '18 Smarch 2026', '18/09/2026 - x',
        '01/09/2026 - 02/09/2026 - 03/09/2026';
    # 09/18/2026 is US order: month 18 does not exist, so it is text, not a wrong day.
    is('US month-first order is not guessed', $range->('09/18/2026'), '');

    Plugins::ListeningHistory::DB::dbh()->do($_) for 'DELETE FROM plays', 'DELETE FROM entries';
    add(title => 'Before', url => 'file:///b', played_at => $day->(31, 8, 2026) + 23 * 3600);
    add(title => 'First',  url => 'file:///f', played_at => $day->(1, 9, 2026));
    add(title => 'Last',   url => 'file:///l', played_at => $day->(15, 9, 2026) + 23 * 3600 + 3599);
    add(title => 'After',  url => 'file:///a', played_at => $day->(16, 9, 2026));
    my $hits = sub { join ',', sort map { $_->{url} } grep { ($_->{type} // '') eq 'audio' }
        @{ feed(\&Plugins::ListeningHistory::Browse::topLevel, { params => { search => $_[0] } }) } };
    is('searching a range lists both end days, nothing outside', $hits->('01/09/2026 - 15/09/2026'), 'file:///f,file:///l');
    is('searching a single date lists that day', $hits->('15/09/2026'), 'file:///l');
    is('a date with nothing on it says so',
       feed(\&Plugins::ListeningHistory::Browse::topLevel, { params => { search => '01/01/2020' } })->[0]{name},
       'PLUGIN_LH_NO_RESULTS');
}

# --- context menu + remove --------------------------------------------------------------------------------
main::lh_require('Plugin');
{ package FakeReq; sub new { bless { p => $_[1], loop => [] }, $_[0] }
  sub client {} sub getParam { $_[0]{p}{$_[1]} } sub setStatusDone { $_[0]{done} = 1 }
  sub addResult {} sub addResultLoop { my ($s, $l, $i, $k, $v) = @_; $s->{loop}[$i]{$k} = $v } }
my $req = FakeReq->new({ id => $trk });
Plugins::ListeningHistory::Plugin::_contextMenuQuery($req);
is('context menu: Remove', $req->{loop}[0]{text}, 'PLUGIN_LH_REMOVE');
is('context menu: refreshes the list in place', $req->{loop}[0]{nextWindow}, 'parent');
my $do = $req->{loop}[0]{actions}{do};
Plugins::ListeningHistory::Plugin::_removeCommand(FakeReq->new($do->{params}));
is('remove command: the row is gone', Plugins::ListeningHistory::DB::get($trk), undef);

# --- settings: an unticked checkbox turns the pref off ------------------------------------------------------
Slim::Utils::Prefs::set_test_pref('plugin.listeninghistory', record_radio => 1);
Plugins::ListeningHistory::Settings->handler(undef, { saveSettings => 1, pref_played_threshold => '250',
    pref_session_gap_min => 'x', pref_retention_days => '14' });
my $p = Slim::Utils::Prefs::preferences('plugin.listeninghistory');
is('settings: unticked record_radio stores 0, not undef', $p->get('record_radio'), 0);
is('settings: threshold clamped to 100', $p->get('played_threshold'), 100);
is('settings: junk gap falls back to 30', $p->get('session_gap_min'), 30);
is('settings: retention kept', $p->get('retention_days'), 14);

sub like_ { my ($d, $got, $re) = @_; is($d, (defined $got && $got =~ $re) ? 1 : 0, 1) or print "     ($got)\n" }
sub unlike_ { my ($d, $got, $re) = @_; is($d, (defined $got && $got !~ $re) ? 1 : 0, 1) or print "     (" . ($got // 'undef') . ")\n" }

main::done();
