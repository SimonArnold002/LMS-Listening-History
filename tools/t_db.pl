#!/usr/bin/env perl
# DB.pm against real SQLite: the schema and its version stamp, the promote-in-one-
# transaction write, removal and purge taking the plays with them, search treating % and _
# literally, and the browse indexes.
use strict;
use warnings;
use FindBin;
require "$FindBin::Bin/t_stubs.pl";

main::lh_require(qw(DB));
my $dir = main::lh_tempdb();
my $DB  = 'Plugins::ListeningHistory::DB';

my $h = $DB->can('dbh')->();
ok('the store opens', $h);
is('schema is stamped at version 1', ($h->selectrow_array('PRAGMA user_version'))[0], 1);

# Re-open the same file: the migration must be a no-op, not a failure.
$DB->can('_reset')->();
Slim::Utils::Prefs::set_test_pref('server', 'cachedir', $dir);
$h = $DB->can('dbh')->();
ok('re-opening an existing store works', $h);
is('and it is still version 1', ($h->selectrow_array('PRAGMA user_version'))[0], 1);

my $t0 = time() - 1000;
sub add {
    my (%e) = @_;
    my $play = { url => $e{url}, title => $e{title}, played_at => $e{played_at} };
    return Plugins::ListeningHistory::DB::addEntry({
        kind => 'track', source => 'library', player_id => 'p1', player_name => 'Kitchen', %e,
    }, $play);
}

# --- promote --------------------------------------------------------------------------------
my $id = add(title => 'Song 1', artist => 'Band', album => 'LP', url => 'file:///1', played_at => $t0,
             ref => { album_id => 7 });
ok('addEntry returns an id', $id);
ok('addToEntry promotes', Plugins::ListeningHistory::DB::addToEntry($id,
    { url => 'file:///2', title => 'Song 2', played_at => $t0 + 200 },
    { album => 'LP', artist => 'Band', track_total => 9, ref => { album_id => 7 } }));
my $e = Plugins::ListeningHistory::DB::get($id);
is('promoted: kind', $e->{kind}, 'album');
is('promoted: tracks_played', $e->{tracks_played}, 2);
is('promoted: track_total', $e->{track_total}, 9);
is('promoted: title cleared', $e->{title}, undef);
is('promoted: played_at moves to the latest play', $e->{played_at}, $t0 + 200);
is('promoted: ref decoded', $e->{ref}{album_id}, 7);
is('promoted: two plays behind it', scalar @{ Plugins::ListeningHistory::DB::plays($id) }, 2);
is('promoted: plays in play order', join(',', map { $_->{url} } @{ Plugins::ListeningHistory::DB::plays($id) }),
   'file:///1,file:///2');

ok('addToEntry on a missing entry answers false',
   !Plugins::ListeningHistory::DB::addToEntry(99999, { url => 'x', played_at => $t0 }));
is('and writes no orphan play', ($h->selectrow_array('SELECT COUNT(*) FROM plays WHERE entry_id = 99999'))[0], 0);

# --- order and the id tie-break ----------------------------------------------------------------
my @tie = map { add(title => "Tie $_", url => "file:///t$_", played_at => $t0 + 500) } 1 .. 3;
my $r = Plugins::ListeningHistory::DB::recent(3);
is('equal played_at: newest id first', join(',', map { $_->{id} } @$r), join(',', reverse @tie));

# --- search -------------------------------------------------------------------------------------
add(title => '50% Off', artist => 'Sale', url => 'file:///s1', played_at => $t0 + 10);
add(title => '50 Off',  artist => 'Sale', url => 'file:///s2', played_at => $t0 + 11);
add(title => 'a_b',     artist => 'X',    url => 'file:///s3', played_at => $t0 + 12);
add(title => 'axb',     artist => 'X',    url => 'file:///s4', played_at => $t0 + 13);
is('search: % is literal', join(',', map { $_->{title} } @{ Plugins::ListeningHistory::DB::search('50%') }), '50% Off');
is('search: _ is literal', join(',', map { $_->{title} } @{ Plugins::ListeningHistory::DB::search('a_b') }), 'a_b');
is('search: case-insensitive on artist', scalar @{ Plugins::ListeningHistory::DB::search('sale') }, 2);
is('search: finds a track inside an album entry', Plugins::ListeningHistory::DB::search('Song 2')->[0]{id}, $id);
is('search: by player name', scalar(@{ Plugins::ListeningHistory::DB::search('kitchen') }) > 0 ? 1 : 0, 1);
is('search: nothing for an empty term', scalar @{ Plugins::ListeningHistory::DB::search('') }, 0);

# --- indexes ------------------------------------------------------------------------------------
add(title => 'Lower', artist => 'band', url => 'file:///c', played_at => $t0 + 20);
my ($band) = grep { lc $_->{artist} eq 'band' } @{ Plugins::ListeningHistory::DB::artists() };
is('artists: grouped case-insensitively', $band->{n}, 2);
is('forArtist: case-insensitive', scalar @{ Plugins::ListeningHistory::DB::forArtist('BAND') }, 2);
add(title => 'Later', player_id => 'p1', player_name => 'Kitchen Renamed', url => 'file:///r', played_at => $t0 + 900);
my ($p1) = grep { $_->{player_id} eq 'p1' } @{ Plugins::ListeningHistory::DB::players() };
is('players: named by the latest entry', $p1->{player_name}, 'Kitchen Renamed');
my @lt = localtime($t0 + 900);
my $ymd = sprintf '%04d-%02d-%02d', $lt[5] + 1900, $lt[4] + 1, $lt[3];
ok('forDay finds the entry on its local day', grep { ($_->{title} // q()) eq q(Later) } @{ Plugins::ListeningHistory::DB::forDay($ymd) });
ok('months lists that month', grep { $_->{ym} eq substr($ymd, 0, 7) } @{ Plugins::ListeningHistory::DB::months() });
ok('days lists that day', grep { $_->{ymd} eq $ymd } @{ Plugins::ListeningHistory::DB::days(substr($ymd, 0, 7)) });
is('forDay rejects a malformed day', scalar @{ Plugins::ListeningHistory::DB::forDay("x' OR 1=1 --") }, 0);

# --- remove and purge take the plays with them ---------------------------------------------------
is('remove: one entry', Plugins::ListeningHistory::DB::remove($id), 1);
is('remove: its plays go too', scalar @{ Plugins::ListeningHistory::DB::plays($id) }, 0);
is('remove: a missing id removes nothing', Plugins::ListeningHistory::DB::remove(99999), 0);

my $old = add(title => 'Ancient', url => 'file:///old', played_at => time() - 40 * 86400);
my $new = add(title => 'Fresh',   url => 'file:///new', played_at => time());
is('purge 0 keeps everything', Plugins::ListeningHistory::DB::purge(0), 0);
ok('purge 30 days removes the old entry', Plugins::ListeningHistory::DB::purge(30) >= 1);
is('purge: old entry gone', Plugins::ListeningHistory::DB::get($old), undef);
ok('purge: new entry kept', Plugins::ListeningHistory::DB::get($new));
is('purge: no orphan plays left', ($h->selectrow_array(
    'SELECT COUNT(*) FROM plays WHERE entry_id NOT IN (SELECT id FROM entries)'))[0], 0);

# --- a commit that fails is reported as a failure -----------------------------------------------
# The success flag used to be set INSIDE the transaction, before commit ran, so a busy/locked
# database rolled the write back while the caller was told it had landed.
{
    my $e1 = add(title => 'Keep me', url => 'file:///k', played_at => time());
    my $o  = add(title => 'Old', url => 'file:///o', played_at => time() - 90 * 86400);
    no warnings qw(redefine once);
    local *DBD::SQLite::db::commit = sub { die "database is locked\n" };
    ok('failed commit: addToEntry answers false',
       !Plugins::ListeningHistory::DB::addToEntry($e1, { url => 'file:///k2', played_at => time() }, { album => 'X' }));
    is('failed commit: remove answers 0', Plugins::ListeningHistory::DB::remove($e1), 0);
    is('failed commit: purge answers 0', Plugins::ListeningHistory::DB::purge(30), 0);
}
my ($k) = grep { ($_->{title} // '') eq 'Keep me' } @{ Plugins::ListeningHistory::DB::recent(1000) };
ok('failed commit: the entry is still there', $k);
ok('failed commit: the old entry purge rolled back is still there',
   grep { ($_->{title} // '') eq 'Old' } @{ Plugins::ListeningHistory::DB::recent(1000) });
is('failed commit: and still a track with one play', ($k->{kind} // '') . '/' . ($k->{tracks_played} // ''), 'track/1');

main::done();
