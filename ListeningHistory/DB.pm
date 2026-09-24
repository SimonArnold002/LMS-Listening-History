package Plugins::ListeningHistory::DB;

# The plugin's own SQLite store. Two tables:
#
#   entries  one row per thing the user SEES in the history: a track, an album (two or
#            more tracks of it played back to back), or a radio station. It carries the
#            display metadata and the replay reference, so a list renders without asking
#            any service anything.
#   plays    the raw per-track log behind an entry, one row per track that counted. It is
#            what an album entry falls back to when its service cannot rebuild the whole
#            album (Deezer and Spotify publish no album id at play time), and what search
#            reads to find a track inside an album entry.
#
# Every list is ordered `played_at DESC, id DESC`. The id tie-break is not decoration:
# XMLBrowser addresses a row by its POSITION (item_id), re-read against a freshly built
# list, so two rows sharing a second would otherwise swap places and a tap would play the
# wrong one.
#
# Leaf module: it `use`s nothing of the plugin's. The package names match the INSTALLED
# layout (Plugins/ListeningHistory/…), so a `use` of a sibling dies at BEGIN in a checkout
# and takes every test suite with it.

use strict;
use warnings;

use DBI;
use JSON::XS ();

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log  = logger('plugin.listeninghistory');
my $JSON = JSON::XS->new->utf8->canonical;

my $dbh;      # lazily-opened handle
my $broken;   # latched once the DB cannot be opened: complain once, then degrade

# Bumped when _migrate gains a step. `PRAGMA user_version` records what a file has been
# migrated TO; a step is stamped only after it succeeded.
use constant SCHEMA_VERSION => 1;

# The most rows any one browse list returns. A list longer than this says so and points at
# By date, rather than silently stopping.
use constant LIST_CAP => 1000;

sub _path {
    my $dir = preferences('server')->get('cachedir') || '/tmp';
    return "$dir/listeninghistory.db";
}

sub dbh {
    return undef if $broken;
    return $dbh if $dbh && eval { $dbh->ping };

    my $path = _path();
    $dbh = eval {
        my $h = DBI->connect("dbi:SQLite:dbname=$path", '', '', {
            RaiseError     => 1,
            PrintError     => 0,
            AutoCommit     => 1,
            sqlite_unicode => 1,
        });
        $h->do('PRAGMA journal_mode=WAL');
        _migrate($h);
        $h;
    };

    unless ($dbh) {
        # DEGRADE, NEVER DIE. Without the store the plugin records nothing and lists
        # nothing, but playback and every other plugin carry on untouched.
        $broken = 1;
        $log->error("Listening History store unavailable at $path ($@) — history is off");
        return undef;
    }
    return $dbh;
}

# For the test suites: drop the cached handle so the next dbh() opens whatever cachedir
# now says. Never called by the plugin itself.
sub _reset {
    eval { $dbh->disconnect } if $dbh;
    undef $dbh;
    undef $broken;
    return;
}

# ---------------------------------------------------------------------------
# Schema. A throwing step leaves user_version untouched and latches $broken through the
# eval in dbh(), so a half-applied schema is never recorded as complete.
# ---------------------------------------------------------------------------
sub _migrate {
    my ($h) = @_;
    my ($have) = $h->selectrow_array('PRAGMA user_version');
    $have ||= 0;
    return if $have >= SCHEMA_VERSION;

    if ($have < 1) {
        _migrate_1($h);
        $h->do('PRAGMA user_version = 1');
    }

    # Future steps: `if ($have < N) { _migrate_N($h); PRAGMA user_version = N }`.
    return;
}

sub _migrate_1 {
    my ($h) = @_;
    $h->do(<<'SQL');
CREATE TABLE IF NOT EXISTS entries (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    kind          TEXT    NOT NULL,
    source        TEXT    NOT NULL,
    player_id     TEXT,
    player_name   TEXT,
    artist        TEXT,
    album         TEXT,
    title         TEXT,
    year          INTEGER,
    artwork       TEXT,
    url           TEXT,
    album_key     TEXT,
    track_total   INTEGER,
    tracks_played INTEGER NOT NULL DEFAULT 1,
    ref_json      TEXT,
    started_at    INTEGER NOT NULL,
    played_at     INTEGER NOT NULL
)
SQL
    $h->do(<<'SQL');
CREATE TABLE IF NOT EXISTS plays (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id  INTEGER NOT NULL,
    url       TEXT,
    title     TEXT,
    artist    TEXT,
    album     TEXT,
    duration  REAL,
    played_at INTEGER NOT NULL
)
SQL
    $h->do('CREATE INDEX IF NOT EXISTS entries_played ON entries (played_at DESC, id DESC)');
    $h->do('CREATE INDEX IF NOT EXISTS entries_artist ON entries (artist COLLATE NOCASE)');
    $h->do('CREATE INDEX IF NOT EXISTS entries_album  ON entries (album COLLATE NOCASE)');
    $h->do('CREATE INDEX IF NOT EXISTS entries_player ON entries (player_id)');
    $h->do('CREATE INDEX IF NOT EXISTS plays_entry    ON plays (entry_id)');
    return;
}

# Roll back a failed transaction and leave the handle usable. A rollback that itself fails
# would otherwise leave AutoCommit off, and every later write in this server run would be
# discarded when the handle is destroyed (the Listen Later 0.1.119 lesson).
sub _rollback {
    my ($h) = @_;
    eval { $h->rollback; 1 } or eval { $h->do('ROLLBACK'); 1 };
    eval { $h->{AutoCommit} = 1 } unless $h->{AutoCommit};
    return;
}

# Run $code inside one transaction; true on commit, false (logged) on rollback.
sub _txn {
    my ($what, $code) = @_;
    my $h = dbh() or return 0;
    my $ok = eval {
        $h->begin_work;
        $code->($h);
        $h->commit;
        1;
    };
    return 1 if $ok;
    my $err = $@;
    _rollback($h);
    $log->error("Listening History: $what failed: $err");
    return 0;
}

# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------

my @ENTRY_COLS = qw(kind source player_id player_name artist album title year artwork url
                    album_key track_total tracks_played ref_json started_at played_at);

# A new entry and its first play, in one transaction. Returns the entry id, or undef.
sub addEntry {
    my ($e, $play) = @_;
    my %row = %$e;
    $row{ref_json}      = $JSON->encode($e->{ref} || {});
    $row{tracks_played} //= 1;
    $row{started_at}    //= $row{played_at} //= time();

    my $id;
    _txn('adding an entry', sub {
        my ($h) = @_;
        $h->do('INSERT INTO entries (' . join(',', @ENTRY_COLS) . ') VALUES ('
            . join(',', ('?') x @ENTRY_COLS) . ')', undef, @row{@ENTRY_COLS});
        $id = $h->sqlite_last_insert_rowid;
        _insertPlay($h, $id, $play, $row{played_at}) if $play;
    }) or return undef;
    return $id;
}

# Add a play to an existing entry. With $promote, the entry becomes an ALBUM entry in the
# same transaction: kind, replay ref and album metadata are rewritten, and the track title
# is cleared because the row now stands for the album. Returns true on commit, false if the
# entry has gone (removed or purged while the album was playing) or the write failed.
sub addToEntry {
    my ($id, $play, $promote) = @_;
    my $now = $play->{played_at} // time();
    my $ok = 0;
    _txn('adding a play', sub {
        my ($h) = @_;
        my ($exists) = $h->selectrow_array('SELECT 1 FROM entries WHERE id = ?', undef, $id);
        return unless $exists;
        _insertPlay($h, $id, $play, $now);
        $h->do('UPDATE entries SET tracks_played = tracks_played + 1, played_at = ? WHERE id = ?',
            undef, $now, $id);
        if ($promote) {
            $h->do(q{UPDATE entries SET kind = 'album', title = NULL,
                        artist = COALESCE(?, artist), album = COALESCE(?, album),
                        year = COALESCE(?, year), artwork = COALESCE(?, artwork),
                        track_total = COALESCE(?, track_total), ref_json = ?
                     WHERE id = ?},
                undef, @{$promote}{qw(artist album year artwork track_total)},
                $JSON->encode($promote->{ref} || {}), $id);
        }
        $ok = 1;
    }) or return 0;   # a failed COMMIT rolls back after $ok was set: the transaction decides
    return $ok;
}

# Store a release type in an entry's ref (Tracker, when Qobuz answers). Merged into the ref as
# it is NOW, so a promotion in between keeps its album reference.
sub setReleaseType {
    my ($id, $rt) = @_;
    return 0 unless defined $id && $id =~ /^\d+$/ && defined $rt && $rt =~ /^[A-Z0-9 _]{1,40}$/;
    my $ok = 0;
    _txn('storing a release type', sub {
        my ($h) = @_;
        my $row = $h->selectrow_arrayref('SELECT ref_json FROM entries WHERE id = ?', undef, $id) or return;
        my $ref = eval { $JSON->decode($row->[0] // '{}') } || {};
        $ref->{release_type} = $rt;
        $h->do('UPDATE entries SET ref_json = ? WHERE id = ?', undef, $JSON->encode($ref), $id);
        $ok = 1;
    }) or return 0;
    return $ok;
}

# Point a LIBRARY entry at its album again (Sources::libraryAlbum), or store the album's lasting
# keys on it. Compare-and-set: written only while the entry is still a library entry whose
# ref.album_id is $expect, so a promotion or a Remove in between wins. The keys are merged into
# the ref as it is NOW; album_key follows only where it was the old "lib:<id>"; artwork only when
# given. Plays are never touched. Returns true on a write.
my %RELINK_KEYS = map { $_ => 1 } qw(album_id album_mbid track_mbid album_url);

sub relinkLibrary {
    my ($id, $expect, $new) = @_;
    return 0 unless defined $id && $id =~ /^\d+$/ && defined $expect && ref $new eq 'HASH'
        && defined $new->{album_id} && $new->{album_id} =~ /^\d+$/;
    my $ok = 0;
    _txn('relinking a library album', sub {
        my ($h) = @_;
        my $row = $h->selectrow_hashref('SELECT source, ref_json, album_key FROM entries WHERE id = ?',
            undef, $id) or return;
        return unless ($row->{source} // '') eq 'library';
        my $ref = eval { $JSON->decode($row->{ref_json} // '{}') } || {};
        return unless defined $ref->{album_id} && $ref->{album_id} eq $expect;
        $ref->{$_} = $new->{$_} for grep { $RELINK_KEYS{$_} && defined $new->{$_} } keys %$new;
        my $key = ($row->{album_key} // '') eq "lib:$expect" ? "lib:$new->{album_id}" : $row->{album_key};
        $h->do('UPDATE entries SET ref_json = ?, album_key = ?, artwork = COALESCE(?, artwork) WHERE id = ?',
            undef, $JSON->encode($ref), $key, $new->{artwork}, $id);
        $ok = 1;
    }) or return 0;
    return $ok;
}

sub _insertPlay {
    my ($h, $entryId, $p, $when) = @_;
    $h->do('INSERT INTO plays (entry_id, url, title, artist, album, duration, played_at)
            VALUES (?,?,?,?,?,?,?)', undef,
        $entryId, @{$p}{qw(url title artist album duration)}, $p->{played_at} // $when);
    return;
}

# Remove an entry and its plays. Returns the number of entries removed.
sub remove {
    my ($id) = @_;
    my $n = 0;
    _txn('removing an entry', sub {
        my ($h) = @_;
        $h->do('DELETE FROM plays WHERE entry_id = ?', undef, $id);
        $n = $h->do('DELETE FROM entries WHERE id = ?', undef, $id) + 0;
    }) or return 0;
    return $n;
}

# Remove every entry last played more than $days ago. 0 or less keeps everything.
sub purge {
    my ($days) = @_;
    return 0 unless defined $days && $days =~ /^\d+$/ && $days > 0;
    my $cutoff = time() - $days * 86400;
    my $n = 0;
    _txn('purging old history', sub {
        my ($h) = @_;
        $h->do('DELETE FROM plays WHERE entry_id IN (SELECT id FROM entries WHERE played_at < ?)',
            undef, $cutoff);
        $n = $h->do('DELETE FROM entries WHERE played_at < ?', undef, $cutoff) + 0;
    }) or return 0;
    return $n;
}

# ---------------------------------------------------------------------------
# Reads. Every entry read goes through _entries so the order and decoding live in one place.
# ---------------------------------------------------------------------------
sub _entries {
    my ($where, $binds, $limit) = @_;
    my $h = dbh() or return [];
    my $sql = 'SELECT * FROM entries' . ($where ? " WHERE $where" : '')
            . ' ORDER BY played_at DESC, id DESC LIMIT ?';
    my $rows = eval { $h->selectall_arrayref($sql, { Slice => {} }, @{ $binds || [] }, $limit || LIST_CAP) };
    $log->error("Listening History: read failed: $@") if $@;
    return [ map { _decode($_) } @{ $rows || [] } ];
}

sub _decode {
    my ($r) = @_;
    $r->{ref} = eval { $JSON->decode($r->{ref_json} // '{}') } || {};
    return $r;
}

sub get {
    my ($id) = @_;
    return undef unless defined $id && $id =~ /^\d+$/;
    my $rows = _entries('id = ?', [$id], 1);
    return $rows->[0];
}

sub recent    { return _entries(undef, [], $_[0]) }
sub forArtist { return _entries('artist = ? COLLATE NOCASE', [$_[0]]) }
sub forPlayer { return _entries('player_id = ?', [$_[0]], $_[1]) }
# One source, or an arrayref of several (By service merges sources that share a label).
sub forSource {
    my @src = grep { defined } (ref $_[0] eq 'ARRAY' ? @{ $_[0] } : $_[0]);
    return [] unless @src;
    return _entries('source IN (' . join(',', ('?') x @src) . ')', \@src);
}

# Entries last played in [$from, $to), epoch seconds. The caller works out local midnights.
sub forRange {
    my ($from, $to) = @_;
    return [] unless defined $from && defined $to && $from =~ /^\d+$/ && $to =~ /^\d+$/;
    return _entries('played_at >= ? AND played_at < ?', [$from, $to]);
}

# How many entries forRange would list, uncapped.
sub countRange {
    my ($from, $to) = @_;
    return 0 unless defined $from && defined $to && $from =~ /^\d+$/ && $to =~ /^\d+$/;
    my $h = dbh() or return 0;
    my ($n) = eval { $h->selectrow_array(
        'SELECT COUNT(*) FROM entries WHERE played_at >= ? AND played_at < ?', undef, $from, $to) };
    return $n // 0;
}

sub forAlbum {
    my ($artist, $album) = @_;
    return _entries('album = ? COLLATE NOCASE AND COALESCE(artist, \'\') = ? COLLATE NOCASE',
        [$album, $artist // '']);
}

# Entries whose last play falls on a local calendar day, 'YYYY-MM-DD'.
sub forDay {
    my ($ymd) = @_;
    return [] unless defined $ymd && $ymd =~ /^\d{4}-\d\d-\d\d$/;
    return _entries(q{strftime('%Y-%m-%d', played_at, 'unixepoch', 'localtime') = ?}, [$ymd]);
}

# A text search across what the user can name: artist, album, title, player, and any track
# played inside an album entry. `%` and `_` in the search are LITERAL, not wildcards.
sub search {
    my ($term) = @_;
    return [] unless defined $term && length $term;
    (my $esc = $term) =~ s/([\\%_])/\\$1/g;
    my $pat = "%$esc%";
    my $like = q{LIKE ? ESCAPE '\\'};
    return _entries(
        "artist $like OR album $like OR title $like OR player_name $like"
        . " OR id IN (SELECT entry_id FROM plays WHERE title $like)",
        [ ($pat) x 5 ]);
}

# The tracks that were played for an entry, in the order they were played.
sub plays {
    my ($id) = @_;
    my $h = dbh() or return [];
    return eval {
        $h->selectall_arrayref('SELECT * FROM plays WHERE entry_id = ? ORDER BY played_at, id',
            { Slice => {} }, $id);
    } || [];
}

# ---------------------------------------------------------------------------
# Browse indexes. Each returns [ { key fields…, n => count } ] for a menu level.
# ---------------------------------------------------------------------------
sub _index {
    my ($sql, @binds) = @_;
    my $h = dbh() or return [];
    my $rows = eval { $h->selectall_arrayref($sql, { Slice => {} }, @binds) };
    $log->error("Listening History: index read failed: $@") if $@;
    return $rows || [];
}

sub years {
    return _index(q{SELECT strftime('%Y', played_at, 'unixepoch', 'localtime') AS y,
                           COUNT(*) AS n
                    FROM entries GROUP BY y ORDER BY y DESC});
}

# Every month with entries, or only those of one year ('YYYY').
sub months {
    my ($year) = @_;
    return [] if defined $year && $year !~ /^\d{4}$/;
    return _index(q{SELECT strftime('%Y-%m', played_at, 'unixepoch', 'localtime') AS ym,
                           COUNT(*) AS n
                    FROM entries GROUP BY ym ORDER BY ym DESC}) unless defined $year;
    return _index(q{SELECT strftime('%Y-%m', played_at, 'unixepoch', 'localtime') AS ym,
                           COUNT(*) AS n
                    FROM entries
                    WHERE strftime('%Y', played_at, 'unixepoch', 'localtime') = ?
                    GROUP BY ym ORDER BY ym DESC}, $year);
}

sub days {
    my ($ym) = @_;
    return [] unless defined $ym && $ym =~ /^\d{4}-\d\d$/;
    return _index(q{SELECT strftime('%Y-%m-%d', played_at, 'unixepoch', 'localtime') AS ymd,
                           COUNT(*) AS n
                    FROM entries
                    WHERE strftime('%Y-%m', played_at, 'unixepoch', 'localtime') = ?
                    GROUP BY ymd ORDER BY ymd DESC}, $ym);
}

sub artists {
    return _index(q{SELECT MIN(artist) AS artist, COUNT(*) AS n FROM entries
                    WHERE artist IS NOT NULL AND artist <> ''
                    GROUP BY artist COLLATE NOCASE ORDER BY artist COLLATE NOCASE});
}

# `last_id` is the group's most recent entry, which the By album tile takes its service
# badge from (a group can mix sources; the latest play is the one shown).
sub albums {
    return _index(q{SELECT g.*,
                           (SELECT x.id FROM entries x
                            WHERE x.album = g.album COLLATE NOCASE
                              AND COALESCE(x.artist, '') = g.artist COLLATE NOCASE
                              AND x.kind <> 'station'
                            ORDER BY x.played_at DESC, x.id DESC LIMIT 1) AS last_id
                    FROM (SELECT MIN(album) AS album, MIN(COALESCE(artist, '')) AS artist,
                                 MAX(artwork) AS artwork, COUNT(*) AS n FROM entries
                          WHERE album IS NOT NULL AND album <> '' AND kind <> 'station'
                          GROUP BY album COLLATE NOCASE, COALESCE(artist, '') COLLATE NOCASE) g
                    ORDER BY g.album COLLATE NOCASE, g.artist COLLATE NOCASE});
}

sub services {
    return _index(q{SELECT source, COUNT(*) AS n FROM entries GROUP BY source ORDER BY source});
}

# One row per player, named by the name it had on its most recent entry (a player can be
# renamed; the id is what identifies it).
sub players {
    return _index(q{SELECT e.player_id AS player_id, COUNT(*) AS n,
                           (SELECT player_name FROM entries x WHERE x.player_id = e.player_id
                            ORDER BY x.played_at DESC, x.id DESC LIMIT 1) AS player_name
                    FROM entries e WHERE e.player_id IS NOT NULL
                    GROUP BY e.player_id ORDER BY player_name COLLATE NOCASE});
}

1;
