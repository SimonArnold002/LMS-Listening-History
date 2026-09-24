#!/usr/bin/env perl
# Browse.pm, the context menu, and Settings: the shelf's shape and size, what each row type
# is, how an album row resolves (whole album vs the recorded tracks), search dispatch, and
# the settings clamps.
use strict;
use warnings;
use FindBin;
use POSIX ();
require "$FindBin::Bin/t_stubs.pl";

main::lh_require(qw(DB Sources Browse Settings HomeExtras));
main::lh_tempdb();
my $B = 'Plugins::ListeningHistory::Browse';
no warnings "once";

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
is('station row: the name alone, no "by"', $row{'Jazz FM'}{name}, 'Jazz FM');
is('album row: has the "…" menu', $albumRow->{itemActions}{info}{command}[1], 'contextmenu');
# A single track: the web skins get it named the way LMS names one (a favourite track reads "Live By
# You by Actress from Radical Frame"); Material gets "Title from Album" over the artist, the artist
# on the second line as on an album row (Simon, 2026-09-21).
my $solo = $row{'Solo FROM Local LP'};
is('track row: the web-skin name is "Title by Artist from Album"', $solo->{name}, 'Solo BY Lib FROM Local LP');
is('track row: Material\'s top line is "Title from Album"', $solo->{line1}, 'Solo FROM Local LP');
is('track row: the artist underneath, and only the artist', $solo->{line2}, 'Lib');
is('track row: type audio', $solo->{type}, 'audio');
is('track row: plays its url', $solo->{url}, 'file:///a/3');
is('station row: type audio', $row{'Jazz FM'}{type}, 'audio');
is('station row: plays the station', $row{'Jazz FM'}{url}, 'http://jazz/stream');
ok('station row: no second line (a station has no artist)', !exists $row{'Jazz FM'}{line2});

# --- service badge (extid) and no service name in line2 ---------------------------------------------
{
    my $R = sub { Plugins::ListeningHistory::Browse::entryRow(undef, { kind => 'track', played_at => 1, %{ $_[0] } }) };
    ok('library row: no extid (no badge)', !exists $albumRow->{extid} && !exists $solo->{extid});
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
    my $qt = $R->({ source => 'qobuz', url => 'qobuz://1.flac', title => 'T', artist => 'Q Artist', player_name => 'Kitchen' });
    is('track name: no service, no player, no time', $qt->{name}, 'T BY Q Artist');
    is('track line2: the artist, no service, player or time', $qt->{line2}, 'Q Artist');
    is('track with no album: the "from" clause is dropped', $qt->{name}, 'T BY Q Artist');
    is('track with no album: the top line is the title alone', $qt->{line1}, 'T');
    my $na = $R->({ source => 'qobuz', url => 'qobuz://3.flac', title => 'T', album => 'LP' });
    is('track with no artist: the "by" clause is dropped', $na->{name}, 'T FROM LP');
    ok('track with no artist: no second line', !exists $na->{line1} && !exists $na->{line2});
    my $bare = $R->({ source => 'qobuz', url => 'qobuz://2.flac', title => 'Bare' });
    ok('no artist or album: the title alone, no second line', $bare->{name} eq 'Bare' && !exists $bare->{line2} && !exists $bare->{line1});
    my $alb = $R->({ kind => 'album', source => 'qobuz', url => 'qobuz://4.flac', album => 'LP', artist => 'Q Artist' });
    ok('CONTROL: an album row is still album over artist', $alb->{line1} eq 'LP' && $alb->{line2} eq 'Q Artist');
    Plugins::ListeningHistory::DB::remove($qa);
}

# --- By release: type rows, each opening its releases (a tile reads like a release, wears the latest badge) ---
{
    my $old = add(kind => 'album', source => 'deezer', artist => 'M', album => 'Mix LP', url => 'deezer://1.mp3',
                  played_at => time() - 100);
    my $new = add(kind => 'album', source => 'qobuz', artist => 'M', album => 'Mix LP', url => 'qobuz://2.flac',
                  ref => { svc_album_id => 'mx9' }, played_at => time());
    my $ep  = add(kind => 'album', source => 'qobuz', artist => 'E', album => 'An EP', url => 'qobuz://3.flac',
                  ref => { svc_album_id => 'ep1', release_type => 'EP' });
    my $sg  = add(source => 'qobuz', artist => 'S', album => 'A Single', title => 'A Single', url => 'qobuz://4.flac',
                  ref => { svc_album_id => 'sg1', release_type => 'SINGLE' });
    $Slim::Schema::ALBUM_META{77} = { release_type => 'EP' };
    $Slim::Schema::ALBUM_META{78} = { release_type => 'ALBUM', compilation => 1 };
    my $lep = add(kind => 'album', source => 'library', artist => 'L', album => 'Lib EP', url => 'file:///lep',
                  ref => { album_id => 77 });
    my $cmp = add(kind => 'album', source => 'library', artist => 'V', album => 'Various', url => 'file:///cmp',
                  ref => { album_id => 78 });
    my $top = feed(\&Plugins::ListeningHistory::Browse::_releases, {});
    is('by release: one row per type, LMS order and names, with counts',
       join('|', map { $_->{name} } @$top), 'Albums (2)|EPs (2)|Compilations (1)|Singles (1)');
    my %by = map { ($_->{name} =~ /^(\w+)/)[0] => $_ } @$top;
    my $open = sub { my %t = map { shown($_) => $_ } @{ feed($by{$_[0]}{url}, {}, $by{$_[0]}{passthrough}[0]) }; \%t };
    my $t = $open->('Albums');
    ok('by release: Albums holds the untyped releases', exists $t->{'Mix LP'} && exists $t->{'Local LP'});
    ok('by release: and no EP', !exists $t->{'An EP'} && !exists $t->{'Lib EP'});
    is('by release: the artist underneath', $t->{'Mix LP'}{line2}, 'M');
    is('by release: the web-skin name keeps the artist', $t->{'Mix LP'}{name}, 'Mix LP BY M');
    is('by release: the badge of the LATEST play, not the older one', $t->{'Mix LP'}{extid}, 'qobuz:album:mx9');
    ok('CONTROL: a library album has no badge', !exists $t->{'Local LP'}{extid});
    ok('by release: a station is not a release', !exists $t->{'Jazz FM'});
    ok('by release: a tile still drills into that release\'s plays', ref $t->{'Mix LP'}{url} eq 'CODE');
    is('by release: EPs from Qobuz (stored) and the library (read live)',
       join(',', sort keys %{ $open->('EPs') }), 'An EP,Lib EP');
    is('by release: a single-track play sits under its release\'s type', join(',', keys %{ $open->('Singles') }), 'A Single');
    is('by release: a library compilation whose type is ALBUM is a Compilation (Material\'s rule)',
       join(',', keys %{ $open->('Compilations') }), 'Various');
    $Slim::Schema::ALBUM_META{77} = { release_type => 'ALBUM' };
    ok('by release: the library type is read LIVE (a retag moves it)',
       exists $open->('Albums')->{'Lib EP'});
    is('by release: an unknown type row opens empty', feed(\&Plugins::ListeningHistory::Browse::_releaseList, {}, { type => 'NOPE' })->[0]{name}, 'PLUGIN_LH_EMPTY');
    Plugins::ListeningHistory::DB::remove($_) for $old, $new, $ep, $sg, $lep, $cmp;
    delete @Slim::Schema::ALBUM_META{77, 78};
}
{
    my $S = 'Plugins::ListeningHistory::Sources';
    is('type order: Material\'s list first, others after A-Z',
       join(',', $S->can('sortReleaseTypes')->(qw(SINGLE ZINE EP ALBUM ALBUM_LIVE COMPILATION))),
       'ALBUM,EP,COMPILATION,SINGLE,ALBUM_LIVE,ZINE');
    is('type label: an unknown type is spelled out', $S->can('releaseTypeLabel')->(undef, 'ALBUM LIVE'), 'Album Live');
    is('type label: RELEASE_TYPE_ALBUMS is empty, so ALBUMS names it', $S->can('releaseTypeLabel')->(undef, 'ALBUM'), 'Albums');
    {
        no warnings 'once';
        local *Slim::Schema::Album::releaseTypeName = sub { my (undef, $t) = @_; $t eq 'EP' ? 'Extended plays' : $t };
        is('type label: LMS\'s own releaseTypeName wins when it names the type', $S->can('releaseTypeLabel')->(undef, 'EP'), 'Extended plays');
        is('type label: and when LMS only echoes the type back, the lookup still names it', $S->can('releaseTypeLabel')->(undef, 'SINGLE'), 'Singles');
    }
    is('releaseType: no entry is an album', $S->can('releaseType')->(undef), 'ALBUM');
    is('releaseType: Qobuz\'s "epmini" is an EP, even stored before the alias', $S->can('releaseType')->({ source => 'qobuz', ref => { release_type => 'EPMINI' } }), 'EP');
    is('releaseType: a stored type is upper-cased', $S->can('releaseType')->({ source => 'qobuz', ref => { release_type => ' ep ' } }), 'EP');
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
my $months = feed(\&Plugins::ListeningHistory::Browse::_dates, {});
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
    my $m = feed(\&Plugins::ListeningHistory::Browse::_dates, {});
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

# --- year search and By date years -------------------------------------------------------------
{
    my $Y = \&Plugins::ListeningHistory::Browse::parseYearSearch;
    my $jan = sub { POSIX::mktime(0, 0, 0, 1, 0, $_[0] - 1900) };
    my $yr = sub { join '..', map { defined $_ ? $_ : 'none' } $Y->($_[0]) };
    is("year search: $_->[0]", $yr->($_->[0]), $_->[1]) for
        ['2025',          join('..', $jan->(2025), $jan->(2026), '2025')],
        [' 2025 ',        join('..', $jan->(2025), $jan->(2026), '2025')],
        ['2024 - 2025',   join('..', $jan->(2024), $jan->(2026), "2024\x{2013}2025")],
        ['2025 to 2024',  join('..', $jan->(2024), $jan->(2026), "2024\x{2013}2025")];
    is("not a year: $_", $yr->($_), '') for '1234', '20255', '2025x', 'The 1975', '2024 - 2025 - 2026', '', '18/09/2026';

    Plugins::ListeningHistory::DB::dbh()->do($_) for 'DELETE FROM plays', 'DELETE FROM entries';
    my $mid = sub { POSIX::mktime(0, 0, 12, $_[2], $_[1] - 1, $_[0] - 1900) };
    add(title => 'NYE',   url => 'file:///nye',  played_at => $mid->(2024, 12, 31));
    add(title => 'Jan',   url => 'file:///jan',  played_at => POSIX::mktime(0, 0, 0, 1, 0, 125));
    add(title => 'Mar',   url => 'file:///mar',  played_at => $mid->(2025, 3, 10));
    add(title => 'Dec',   url => 'file:///dec',  played_at => POSIX::mktime(59, 59, 23, 31, 11, 125));
    add(title => 'Named', artist => 'The 2025 Band', url => 'file:///named', played_at => $mid->(2026, 5, 1));
    my $audio = sub { join ',', sort map { $_->{url} } grep { ($_->{type} // '') eq 'audio' } @{ $_[0] } };
    my $top = sub { feed(\&Plugins::ListeningHistory::Browse::topLevel, { params => { search => $_[0] } }) };

    my $res = $top->('2025');
    is('year search: the first row opens the year, with its count', $res->[0]{name}, 'Played in 2025 (3)');
    is('year search: the text matches follow it', $audio->($res), 'file:///named');
    is('year search: opening the row lists the whole year, both ends, nothing outside',
       $audio->(feed($res->[0]{url}, {}, $res->[0]{passthrough}[0])), 'file:///dec,file:///jan,file:///mar');
    $res = $top->('2024 - 2025');
    is('year range: one row covering both years', $res->[0]{name}, "Played in 2024\x{2013}2025 (4)");
    $res = $top->('2019');
    is('a year with nothing played and no text match says so', $res->[0]{name}, 'PLUGIN_LH_NO_RESULTS');
    is('and only that', scalar @$res, 1);
    $res = $top->('2026');
    is('CONTROL: a year with entries but no text match is just the year row', scalar @$res, 1);
    add(title => '2026 Song', url => 'file:///t2026', played_at => $mid->(2023, 1, 1));
    $res = $top->('2026');
    is('a number that is a name still finds the name', $audio->($res), 'file:///t2026');
    is('CONTROL: a plain text search adds no year row',
       scalar(grep { ($_->{name} // '') =~ /^Played in/ } @{ $top->('Named') }), 0);

    my $dates = feed(\&Plugins::ListeningHistory::Browse::_dates, {});
    is('by date: Today, Yesterday, then one row per year, newest first',
       join('|', map { $_->{name} } @$dates[2 .. $#$dates]), '2026 (1)|2025 (3)|2024 (1)|2023 (1)');
    my ($y25) = grep { $_->{name} eq '2025 (3)' } @$dates;
    my $in = feed($y25->{url}, {}, $y25->{passthrough}[0]);
    is('a year opens All of the year, then its months newest first',
       join('|', map { $_->{name} } @$in), 'All of 2025 (3)|December 2025 (1)|March 2025 (1)|January 2025 (1)');
    is('All of the year lists that year only', $audio->(feed($in->[0]{url}, {}, $in->[0]{passthrough}[0])),
       'file:///dec,file:///jan,file:///mar');
    my $days = feed($in->[2]{url}, {}, $in->[2]{passthrough}[0]);
    like_('a month still opens its days', $days->[0]{name}, qr/10 March \(1\)$/);
    is('a year with nothing in it says so',
       feed(\&Plugins::ListeningHistory::Browse::_months, {}, { y => '1999' })->[0]{name}, 'PLUGIN_LH_EMPTY');
}

# --- context menu + remove --------------------------------------------------------------------------------
main::lh_require('Plugin');
{
    my @before = @Slim::Control::Request::SUBSCRIBED;
    Slim::Utils::Timers::clear();
    Plugins::ListeningHistory::Plugin->postinitPlugin;
    my ($rescan) = grep { ref $_->[1] eq 'ARRAY' && ($_->[1][0][0] // '') eq 'rescan' } @Slim::Control::Request::SUBSCRIBED;
    ok('plugin: listens for the end of a rescan', $rescan && $rescan->[1][1][0] eq 'done');
    ok('plugin: a check is armed after startup',
       grep { $_->{cb} == \&Plugins::ListeningHistory::Sources::sweepTick && $_->{when} >= time() + 100 } @Slim::Utils::Timers::ARMED);
    Slim::Utils::Timers::clear();
    $rescan->[0]->();
    ok('plugin: a rescan arms the check', grep { $_->{cb} == \&Plugins::ListeningHistory::Sources::sweepTick } @Slim::Utils::Timers::ARMED);
    Plugins::ListeningHistory::Plugin->shutdownPlugin;
    ok('plugin: shutdown stops listening', !grep { $_->[0] == $rescan->[0] } @Slim::Control::Request::SUBSCRIBED);
    ok('plugin: … and disarms the check', !grep { $_->{cb} == \&Plugins::ListeningHistory::Sources::sweepTick } @Slim::Utils::Timers::ARMED);
    Slim::Utils::Timers::clear();
}
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

# --- settings: the numbers are clamped; radio is no longer a setting (1.0.15) ---------------------------------
Plugins::ListeningHistory::Settings->handler(undef, { saveSettings => 1, pref_played_threshold => '250',
    pref_session_gap_min => 'x', pref_retention_days => '14' });
my $p = Slim::Utils::Prefs::preferences('plugin.listeninghistory');
ok('settings: record_radio is gone from the page', !grep { $_ eq 'record_radio' } (Plugins::ListeningHistory::Settings->prefs)[1 .. 3]);
is('settings: threshold clamped to 100', $p->get('played_threshold'), 100);
is('settings: junk gap falls back to 30', $p->get('session_gap_min'), 30);
is('settings: retention kept', $p->get('retention_days'), 14);

sub like_ { my ($d, $got, $re) = @_; is($d, (defined $got && $got =~ $re) ? 1 : 0, 1) or print "     ($got)\n" }
sub unlike_ { my ($d, $got, $re) = @_; is($d, (defined $got && $got !~ $re) ? 1 : 0, 1) or print "     (" . ($got // 'undef') . ")\n" }

# --- a library album found again after a rescan (Sources::libraryAlbum) ----------------------------
# A rescan leaves ref.album_id pointing at NOTHING (albums.id is AUTOINCREMENT, never reused). Each
# step is isolated: its album sits where no earlier step can reach it (moved files, no MBID).
{
    my $S  = 'Plugins::ListeningHistory::Sources';
    my $DB = 'Plugins::ListeningHistory::DB';
    my $h  = $DB->can('dbh')->();
    my $row  = sub { my $r = $h->selectrow_hashref('SELECT * FROM entries WHERE id = ?', undef, $_[0]); join '|', map { "$_=" . ($r->{$_} // '') } sort keys %$r };
    my $plays = sub { join '|', map { join ':', @{$_}{qw(id url title played_at)} } @{ $DB->can('plays')->($_[0]) } };
    my $urls = sub { my $out; $S->can('resolveTracks')->(undef, $DB->can('get')->($_[0]), sub { $out = shift }); join ',', map { $_->{url} } @$out };
    my $M = 'aaaaaaaa-0000-0000-0000-000000000001';

    # step 2 — the album MBID. The files moved, so no url resolves; the type comes back.
    Slim::Schema::add_test_album(301, ['E1', 'file:///new/ep/1'], ['E2', 'file:///new/ep/2']);
    $Slim::Schema::ALBUM_META{301} = { release_type => 'EP', musicbrainz_id => $M, artwork => 'cv301' };
    my $a = add(kind => 'album', artist => 'X', album => 'Tagged EP', url => 'file:///old/ep/1', album_key => 'lib:900',
                ref => { album_id => 900, album_mbid => $M },
                plays => [ { url => 'file:///old/ep/1', title => 'E1' }, { url => 'file:///old/ep/2', title => 'E2' } ]);
    my $pa = $plays->($a);
    # a list render (By release asks releaseType of every release) reads the row id only: no search,
    # no write. The sweep after the rescan, or opening the entry, finds it again.
    my $ra0 = $row->($a);
    {
        my $calls = 0;
        no warnings 'redefine';
        local *Slim::Schema::search       = do { my $o = \&Slim::Schema::search;       sub { $calls++; $o->(@_) } };
        local *Slim::Schema::objectForUrl = do { my $o = \&Slim::Schema::objectForUrl; sub { $calls++; $o->(@_) } };
        is('CONTROL relink: a list render does not search for a stale album',
           $S->can('releaseType')->($DB->can('get')->($a)) . " after $calls lookups", 'ALBUM after 0 lookups');
    }
    is('CONTROL relink: and writes nothing', $row->($a), $ra0);
    is('relink album MBID: opening it replays the whole album', $urls->($a), 'file:///new/ep/1,file:///new/ep/2');
    is('relink album MBID: the type is back', $S->can('releaseType')->($DB->can('get')->($a)), 'EP');
    my $ea = $DB->can('get')->($a);
    is('relink album MBID: the row points at the new album', $ea->{ref}{album_id}, 301);
    is('relink album MBID: the session key follows', $ea->{album_key}, 'lib:301');
    is('relink album MBID: the cover is the new album\'s', $ea->{artwork}, '/music/cv301/cover');
    is('relink album MBID: the plays are untouched', $plays->($a), $pa);

    # step 2, one release split into two albums (a disc each): the one this entry played.
    my $M2 = 'aaaaaaaa-0000-0000-0000-000000000002';
    Slim::Schema::add_test_album(307, ['D1', 'file:///box/1/1']);
    Slim::Schema::add_test_album(308, ['D2', 'file:///box/2/1']);
    $Slim::Schema::ALBUM_META{$_} = { musicbrainz_id => $M2 } for 307, 308;
    my $d = add(artist => 'X', album => 'Box', title => 'D2', url => 'file:///box/2/1', ref => { album_id => 905, album_mbid => $M2 });
    is('relink album MBID, split release: the disc that was played', $S->can('libraryAlbum')->($DB->can('get')->($d))->id, 308);

    # step 3 — the files that were played (an untagged album after a wipe).
    Slim::Schema::add_test_album(302, ['R1', 'file:///r/1'], ['R2', 'file:///r/2'], ['R3', 'file:///r/3']);
    my $b = add(kind => 'album', artist => 'Y', album => 'Plain LP', url => 'file:///r/1', ref => { album_id => 901 },
                plays => [ { url => 'file:///r/1', title => 'R1' }, { url => 'file:///r/2', title => 'R2' } ]);
    is('relink files: the WHOLE album again, not just what was played', $urls->($b), 'file:///r/1,file:///r/2,file:///r/3');
    is('relink files: stored', $DB->can('get')->($b)->{ref}{album_id}, 302);

    # step 3 control — played files now on two different albums: no guess.
    Slim::Schema::add_test_album(306, ['S1', 'file:///s/1']);
    my $c = add(kind => 'album', artist => 'Y', album => 'Split', url => 'file:///r/3', ref => { album_id => 906 },
                plays => [ { url => 'file:///r/3', title => 'R3' }, { url => 'file:///s/1', title => 'S1' } ]);
    my $rc = $row->($c);
    is('CONTROL relink files: urls on two albums replay what was played', $urls->($c), 'file:///r/3,file:///s/1');
    is('CONTROL relink files: and the row is untouched', $row->($c), $rc);

    # step 4 — the track (recording) MBID, files moved.
    my $T = 'bbbbbbbb-0000-0000-0000-000000000001';
    Slim::Schema::add_test_album(303, ['M1', 'file:///moved/1'], ['M2', 'file:///moved/2']);
    $Slim::Schema::TRACK_MBID{'file:///moved/1'} = $T;
    my $t = add(artist => 'Z', album => 'Moved', title => 'M1', url => 'file:///gone/1', ref => { album_id => 902, track_mbid => $T });
    is('relink track MBID: found', scalar eval { $S->can('libraryAlbum')->($DB->can('get')->($t))->id }, 303);
    is('relink track MBID: stored', $DB->can('get')->($t)->{ref}{album_id}, 303);
    # … unless the recording is on a compilation too: a recording id is not an album.
    Slim::Schema::add_test_album(304, ['M1', 'file:///comp/9']);
    $Slim::Schema::TRACK_MBID{'file:///comp/9'} = $T;
    my $t2 = add(artist => 'Z', album => 'Moved', title => 'M1', url => 'file:///gone/1', ref => { album_id => 907, track_mbid => $T });
    my $rt2 = $row->($t2);
    ok('CONTROL relink track MBID: a recording on two albums finds nothing', !defined $S->can('libraryAlbum')->($DB->can('get')->($t2)));
    is('CONTROL relink track MBID: and writes nothing', $row->($t2), $rt2);

    # step 5 — LMS's own album url (how a favourite finds its album), for an untagged album whose
    # files moved. An entry recorded before the keys existed rebuilds it from its album + artist.
    Slim::Schema::add_test_album(305, ['N1', 'file:///n/1'], ['N2', 'file:///n/2']);
    $Slim::Schema::ALBUM_META{305} = { title => "Caf\x{e9} D\x{ed}a", artist => "M\x{f6}v\x{eb}r" };
    my $n = add(kind => 'album', artist => "M\x{f6}v\x{eb}r", album => "Caf\x{e9} D\x{ed}a", url => 'file:///was/1', ref => { album_id => 903 },
                plays => [ { url => 'file:///was/1', title => 'N1' }, { url => 'file:///was/2', title => 'N2' } ]);
    is('relink album name: an old album entry is found by LMS\'s own url', $urls->($n), 'file:///n/1,file:///n/2');
    is('relink album name: stored, with the url for next time', $DB->can('get')->($n)->{ref}{album_url},
       'db:album.title=Caf%C3%A9%20D%C3%ADa&contributor.name=M%C3%B6v%C3%ABr');
    my $nt = add(artist => "M\x{f6}v\x{eb}r", album => "Caf\x{e9} D\x{ed}a", title => 'N1', url => 'file:///was/1', ref => { album_id => 904 });
    ok('CONTROL relink album name: an old TRACK entry (its artist is the track\'s) does not guess',
       !defined $S->can('libraryAlbum')->($DB->can('get')->($nt)));
    my $nu = add(artist => "M\x{f6}v\x{eb}r", album => "Caf\x{e9} D\x{ed}a", title => 'N1', url => 'file:///was/1',
                 ref => { album_id => 908, album_url => 'db:album.title=Caf%C3%A9%20D%C3%ADa&contributor.name=M%C3%B6v%C3%ABr' });
    is('relink album name: a track entry with a stored url is found', scalar eval { $S->can('libraryAlbum')->($DB->can('get')->($nu))->id }, 305);

    # nothing resolves: exactly today's behaviour, nothing written.
    my $z = add(kind => 'album', artist => 'Q', album => 'Lost', url => 'file:///lost/1', ref => { album_id => 909, release_type => 'SINGLE' },
                plays => [ { url => 'file:///lost/1', title => 'L1' } ]);
    my $rz = $row->($z);
    is('CONTROL nothing resolves: the recorded tracks', $urls->($z), 'file:///lost/1');
    is('CONTROL nothing resolves: the stored type', $S->can('releaseType')->($DB->can('get')->($z)), 'SINGLE');
    is('CONTROL nothing resolves: the row is untouched', $row->($z), $rz);

    # a scan is running: answer from the live library, write nothing.
    my $sc = add(kind => 'album', artist => 'Y', album => 'Plain LP', url => 'file:///r/1', ref => { album_id => 910 },
                 plays => [ { url => 'file:///r/1', title => 'R1' } ]);
    my $rsc = $row->($sc);
    {
        local $Slim::Music::Import::SCANNING = 1;
        is('scan: still the whole album', $urls->($sc), 'file:///r/1,file:///r/2,file:///r/3');
        is('scan: nothing written', $row->($sc), $rsc);
    }

    # compare-and-set: the entry changed (a promotion) between the read and the write.
    my $cs = add(kind => 'album', artist => 'Y', album => 'Plain LP', url => 'file:///r/1', ref => { album_id => 911 },
                 plays => [ { url => 'file:///r/1', title => 'R1' } ]);
    my $stale = $DB->can('get')->($cs);
    $h->do(q{UPDATE entries SET ref_json = '{"album_id":302}' WHERE id = ?}, undef, $cs);
    my $rcs = $row->($cs);
    $S->can('libraryAlbum')->($stale);
    is('compare-and-set: a newer ref wins', $row->($cs), $rcs);

    # a valid id: never rewritten. Opening it stores the lasting keys; a list render does not.
    $Slim::Schema::ALBUM_META{302} = { title => 'Plain LP', artist => 'Y', musicbrainz_id => 'cccccccc-0000-0000-0000-000000000001' };
    $Slim::Schema::TRACK_MBID{'file:///r/1'} = 'dddddddd-0000-0000-0000-000000000001';
    my $v = add(kind => 'album', artist => 'Y', album => 'Plain LP', url => 'file:///r/1', album_key => 'lib:302', ref => { album_id => 302 },
                plays => [ { url => 'file:///r/1', title => 'R1' } ]);
    my $rv = $row->($v);
    $S->can('releaseType')->($DB->can('get')->($v));
    is('CONTROL valid id: a list render writes nothing', $row->($v), $rv);
    $urls->($v);
    my $ev = $DB->can('get')->($v);
    is('valid id: kept', $ev->{ref}{album_id}, 302);
    is('valid id: opening it stores the album MBID', $ev->{ref}{album_mbid}, 'cccccccc-0000-0000-0000-000000000001');
    is('valid id: and the track MBID', $ev->{ref}{track_mbid}, 'dddddddd-0000-0000-0000-000000000001');
    is('valid id: and LMS\'s album url', $ev->{ref}{album_url}, 'db:album.title=Plain%20LP&contributor.name=Y');
    is('valid id: the session key is unchanged', $ev->{album_key}, 'lib:302');

    # names follow the library (Simon, 2026-09-24): a retag renames the row. The play log keeps what
    # was heard.
    Slim::Schema::add_test_album(320, ['Renamed One', 'file:///rn/1'], ['Renamed Two', 'file:///rn/2']);
    $Slim::Schema::ALBUM_META{320} = { title => 'bollocks', artist => 'New Band', year => 2025, release_type => 'SINGLE' };
    $Slim::Schema::TRACK_ARTIST{'file:///rn/1'} = 'New Band feat. X';
    my $ra = add(kind => 'album', artist => 'Old Band', album => 'At Sea (Single)', year => 2019, url => 'file:///rn/1',
                 ref => { album_id => 912 },
                 plays => [ { url => 'file:///rn/1', title => 'Old One', album => 'At Sea (Single)' },
                            { url => 'file:///rn/2', title => 'Old Two', album => 'At Sea (Single)' } ]);
    my $pra = $plays->($ra);
    $urls->($ra);
    is('names: a relink (opened) brings the type back', $S->can('releaseType')->($DB->can('get')->($ra)), 'SINGLE');
    my $er = $DB->can('get')->($ra);
    is('names: the album entry takes the new title', $er->{album}, 'bollocks');
    is('names: … the album artist', $er->{artist}, 'New Band');
    is('names: … and the year', $er->{year}, 2025);
    ok('names: an album entry gets no track title', !defined $er->{title});
    is('names: the play log keeps what was heard', $plays->($ra), $pra);
    is('names: By artist finds it under the new name', scalar(grep { $_->{id} == $ra } @{ $DB->can('forArtist')->('New Band') }), 1);
    my $rt = add(artist => 'Old Band', album => 'At Sea (Single)', title => 'Old One', url => 'file:///rn/1', ref => { album_id => 913 });
    $S->can('libraryAlbum')->($DB->can('get')->($rt));
    my $et = $DB->can('get')->($rt);
    is('names: a track entry takes its track\'s new title', $et->{title}, 'Renamed One');
    is('names: … its track\'s artist', $et->{artist}, 'New Band feat. X');
    is('names: … and the album', $et->{album}, 'bollocks');
    # an album that is still there: renamed when OPENED (or swept), never on a list render.
    my $rl = add(kind => 'album', artist => 'Old Band', album => 'Old Name', url => 'file:///rn/1', album_key => 'lib:320',
                 ref => { album_id => 320, album_url => 'db:x' },
                 plays => [ { url => 'file:///rn/1', title => 'Old One' } ]);
    my $rrl = $row->($rl);
    $S->can('releaseType')->($DB->can('get')->($rl));
    is('CONTROL names: a list render does not rename a live album', $row->($rl), $rrl);
    $urls->($rl);
    is('names: opening it renames it', $DB->can('get')->($rl)->{album}, 'bollocks');
    is('names: the id is untouched', $DB->can('get')->($rl)->{ref}{album_id}, 320);
    is('names: an unchanged entry is not written again', scalar((sub { my $r = $row->($rl); $urls->($rl); $row->($rl) eq $r })->()), 1);
    $DB->can('remove')->($_) for $ra, $rt, $rl;

    # the sweep after a rescan: every library entry, in batches, without being opened.
    my $sw1 = add(kind => 'album', artist => 'Old Band', album => 'Swept', url => 'file:///rn/1', ref => { album_id => 914 },
                  plays => [ { url => 'file:///rn/1', title => 'Old One' } ]);                       # stale + renamed
    my $sw2 = add(kind => 'album', artist => 'New Band', album => 'bollocks', year => 2025, url => 'file:///rn/2',
                  ref => { album_id => 320, album_url => 'db:x' },
                  plays => [ { url => 'file:///rn/2', title => 'Renamed Two' } ]);                   # already right
    my $sw3 = add(kind => 'album', artist => 'Old Band', album => 'Live Old', url => 'file:///rn/2', ref => { album_id => 320 },
                  plays => [ { url => 'file:///rn/2', title => 'Renamed Two' } ]);                   # live, renamed, keys captured
    my $swq = add(kind => 'album', source => 'qobuz', artist => 'Q', album => 'Qob', url => 'qobuz://9.flac', ref => { svc_album_id => 'q9' });
    my @more = map { add(title => "Filler $_", artist => 'F', url => "file:///fill/$_", ref => { album_id => 5 }) } 1 .. 30;
    my ($r2, $rq) = ($row->($sw2), $row->($swq));
    Slim::Utils::Timers::clear();
    Slim::Utils::Log::clear();
    {
        local $Slim::Music::Import::SCANNING = 1;
        $S->can('startSweep')->(0);
        Slim::Utils::Timers::fire_timer(undef);
        is('sweep: waits while a scan runs', $DB->can('get')->($sw1)->{ref}{album_id}, 914);
        is('sweep: … and stays armed', scalar(@Slim::Utils::Timers::ARMED), 1);
    }
    my $ticks = 0;
    $ticks++ while Slim::Utils::Timers::fire_timer(undef) && $ticks < 50;
    ok('sweep: runs in batches, then stops', $ticks >= 2 && $ticks < 50 && !@Slim::Utils::Timers::ARMED);
    my $e1 = $DB->can('get')->($sw1);
    is('sweep: a stale album is found again', $e1->{ref}{album_id}, 320);
    is('sweep: … and renamed', "$e1->{album}|$e1->{artist}", 'bollocks|New Band');
    is('CONTROL sweep: an entry already right is not written', $row->($sw2), $r2);
    my $e3 = $DB->can('get')->($sw3);
    is('sweep: a live album is renamed', $e3->{album}, 'bollocks');
    is('sweep: … and gains its lasting keys', $e3->{ref}{album_url}, 'db:album.title=bollocks&contributor.name=New%20Band');
    is('CONTROL sweep: a streaming entry is left alone', $row->($swq), $rq);
    ok('sweep: says what it did (a warning, as it changed something)',
       grep { /^WARN .*library check done — \d+ entries, [1-9]\d* found their album again, 1 renamed/ } @Slim::Utils::Log::LINES);
    ok('sweep: no entry failed', !grep { /checking entry .* failed/ } @Slim::Utils::Log::LINES);
    $S->can('startSweep')->(0);
    $S->can('stopSweep')->();
    is('sweep: stopSweep disarms it', scalar(@Slim::Utils::Timers::ARMED), 0);
    $DB->can('remove')->($_) for $sw1, $sw2, $sw3, $swq, @more;
    delete $Slim::Schema::ALBUM_META{320}; delete $Slim::Schema::ALBUM_TRACKS{320};
    %Slim::Schema::TRACK_ARTIST = ();

    $DB->can('remove')->($_) for $a, $d, $b, $c, $t, $t2, $n, $nt, $nu, $z, $sc, $cs, $v;
    delete @Slim::Schema::ALBUM_META{301 .. 308};
    delete @Slim::Schema::ALBUM_TRACKS{301 .. 308};
    %Slim::Schema::TRACK_MBID = ();
}

main::done();
