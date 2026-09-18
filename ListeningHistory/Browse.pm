package Plugins::ListeningHistory::Browse;

# The app's feeds. The top level is a plain tile list — Recently played, Search, By date,
# By artist, By album, By player, Settings — and every list below it ends in history rows.
#
# A history row is directly playable:
#   album    type => 'playlist' + a coderef that rebuilds the album (Sources::resolveTracks),
#            which is what gives Material Play / Play next / Add on it
#   track    type => 'audio' with the stored play url
#   station  type => 'audio' with the station url
# Each carries itemActions → info, the "…" → More menu (Remove from history).

use strict;
use warnings;

use POSIX ();

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use Plugins::ListeningHistory::DB;
use Plugins::ListeningHistory::Sources;

use constant IMG      => 'plugins/ListeningHistory/html/images/';
use constant ICON     => IMG . 'ListeningHistoryIcon_svg.png';
use constant I_RECENT => IMG . 'history_MTL_icon_history.png';
use constant I_SEARCH => IMG . 'search_MTL_icon_search.png';
use constant I_DATE   => IMG . 'calendar_month_MTL_icon_calendar_month.png';
use constant I_ARTIST => IMG . 'person_MTL_icon_person.png';
use constant I_ALBUM  => IMG . 'album_MTL_icon_album.png';
use constant I_PLAYER => IMG . 'speaker_MTL_icon_speaker.png';
use constant I_SETTINGS => IMG . 'settings_MTL_icon_settings.png';
use constant I_SERVICE  => IMG . 'cloud_MTL_icon_cloud.png';
use constant I_SORT     => IMG . 'sort_MTL_icon_sort.png';

# How an entry list can be ordered, cycled by the "Sorted by" row at its top. The home shelf
# is never re-sorted: it is always the latest entries, newest first.
my @SORT_MODES = qw(date artist album);
my %SORT_LABEL = (date => 'PLUGIN_LH_SORT_DATE', artist => 'PLUGIN_LH_SORT_ARTIST',
                  album => 'PLUGIN_LH_SORT_ALBUM');

# The home shelf and the Recently played list both show this many entries.
use constant SHELF_SIZE => 50;

use constant SEP          => " \x{00b7} ";   # " · "
use constant DASH         => " \x{2013} ";   # " – "
use constant GLYPH_ALBUM  => "\x{266b}";     # ♫  more than one track
use constant GLYPH_TRACK  => "\x{266a}";     # ♪  one track

my $log   = logger('plugin.listeninghistory');
my $prefs = preferences('plugin.listeninghistory');

# ---------------------------------------------------------------------------
# Top level
# ---------------------------------------------------------------------------
sub topLevel {
    my ($client, $cb, $args) = @_;
    my $params = (ref $args->{params} eq 'HASH') ? $args->{params} : {};

    # A search submitted by Material arrives as a `search` param on the app's own command.
    # Gated on item_id being ABSENT: a positional walk into the search row sends both, and
    # is the legacy path _legacySearch handles. (Search Hub's pattern.)
    my $q = $params->{search};
    if (defined $q && !ref $q && length $q && !defined $params->{item_id}) {
        return _searchResults($client, $cb, $q);
    }

    $cb->({ items => [
        _link($client, 'PLUGIN_LH_RECENT',    I_RECENT, \&_recent),
        _searchRow($client, $params->{features}),
        _link($client, 'PLUGIN_LH_BY_DATE',   I_DATE,   \&_months),
        _link($client, 'PLUGIN_LH_BY_ARTIST', I_ARTIST, \&_artists),
        _link($client, 'PLUGIN_LH_BY_ALBUM',  I_ALBUM,  \&_albums),
        _link($client, 'PLUGIN_LH_BY_SERVICE', I_SERVICE, \&_services),
        _link($client, 'PLUGIN_LH_BY_PLAYER', I_PLAYER, \&_players),
        {
            name    => cstring($client, 'PLUGIN_LH_SETTINGS'),
            type    => 'link',
            weblink => '/plugins/ListeningHistory/settings.html',
            image   => I_SETTINGS,
        },
    ] });
}

sub _link {
    my ($client, $str, $image, $code, $pt) = @_;
    return {
        name  => (ref $str ? $$str : cstring($client, $str)),
        type  => 'link',
        image => $image,
        url   => $code,
        ($pt ? (passthrough => [$pt]) : ()),
    };
}

sub _searchRow {
    my ($client, $features) = @_;
    $features //= '';
    return {
        name        => cstring($client, 'PLUGIN_LH_SEARCH'),
        type        => 'search',
        image       => I_SEARCH,
        itemActions => { items => { command => ['listeninghistory', 'items'],
            fixedParams => { search => '__TAGGEDINPUT__',
                (length $features ? (features => $features) : ()) } } },
        url         => \&_legacySearch,
    };
}

# Legacy (Default / Classic skin) walk: the text arrives as $args->{search}.
sub _legacySearch {
    my ($client, $cb, $args) = @_;
    _searchResults($client, $cb, $args->{search});
}

# A search that is a date, or a range of two dates, lists what was played on those days;
# anything else is a text search.
sub _searchResults {
    my ($client, $cb, $term) = @_;
    my ($from, $to) = parseDateSearch($term);
    my $rows = defined $from
        ? Plugins::ListeningHistory::DB::forRange($from, $to)
        : Plugins::ListeningHistory::DB::search($term);
    _entryList($client, $cb, $rows, 'PLUGIN_LH_NO_RESULTS');
}

# ---------------------------------------------------------------------------
# Date search. DAY-FIRST, the UK order: 18/09/2026, 18-09-2026, 18.09.2026, 18/09/26,
# 2026-09-18 (ISO), 18 Sep 2026, 18 September 2026. A RANGE is two of those joined by " - ",
# " to " or a dash with spaces round it, in either order, both days included.
#
# Returns ($from, $to) as epoch seconds — local midnight of the first day, local midnight of
# the day after the last — or an empty list when the term is not entirely dates. A date that
# does not exist (31/02/2026) is not a date, so the term falls through to a text search.
# ---------------------------------------------------------------------------
my @MONTHS = qw(january february march april may june july august september october november december);

sub parseDateSearch {
    my ($term) = @_;
    return () unless defined $term;
    $term =~ s/^\s+|\s+$//g;
    return () unless length $term;
    my @parts = split /\s+(?:-|\x{2013}|\x{2014}|to)\s+/i, $term;
    return () if @parts > 2;
    my @days;
    for my $p (@parts) {
        my $d = _parseDay($p) or return ();
        push @days, $d;
    }
    @days = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @days;
    my ($f, $l) = ($days[0], $days[-1]);
    return (POSIX::mktime(0, 0, 0, $f->[2],     $f->[1] - 1, $f->[0] - 1900),
            POSIX::mktime(0, 0, 0, $l->[2] + 1, $l->[1] - 1, $l->[0] - 1900));
}

# One day, as [year, month, day], or undef.
sub _parseDay {
    my ($s) = @_;
    my ($y, $m, $d);
    if ($s =~ /^(\d{4})-(\d{1,2})-(\d{1,2})$/) {
        ($y, $m, $d) = ($1, $2, $3);
    }
    elsif ($s =~ m{^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})$}) {
        ($d, $m, $y) = ($1, $2, $3);
    }
    elsif ($s =~ /^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,})\.?,?\s+(\d{4})$/i) {
        ($d, $y) = ($1, $3);
        my $name = lc $2;
        ($m) = grep { index($MONTHS[$_ - 1], $name) == 0 } 1 .. 12;
        return undef unless $m;
    }
    else {
        return undef;
    }
    $y += 2000 if $y < 100;
    return undef unless $m >= 1 && $m <= 12 && $d >= 1 && $d <= 31;
    # Reject a day the month does not have: mktime would roll 31/02 into March.
    my @t = localtime(POSIX::mktime(0, 0, 12, $d, $m - 1, $y - 1900));
    return undef unless $t[3] == $d && $t[4] == $m - 1 && $t[5] == $y - 1900;
    return [$y + 0, $m + 0, $d + 0];
}

# ---------------------------------------------------------------------------
# Lists of entries
# ---------------------------------------------------------------------------
sub _recent {
    my ($client, $cb) = @_;
    _entryList($client, $cb, Plugins::ListeningHistory::DB::recent(SHELF_SIZE));
}

# Material home shelf: the latest SHELF_SIZE entries as a FLAT list. The carousel and its
# "show all" page are the same feed and Material addresses rows by position, so the result
# must be identical whatever quantity is asked for — no headers, no paging rows, and the
# limit applied in SQL.
sub homeShelf {
    my ($client, $cb) = @_;
    my $rows = Plugins::ListeningHistory::DB::recent(SHELF_SIZE);
    $cb->({ items => [ map { entryRow($client, $_) } @$rows ] });
}

sub _entryList {
    my ($client, $cb, $rows, $emptyStr) = @_;
    unless (@$rows) {
        return $cb->({ items => [{ name => cstring($client, $emptyStr || 'PLUGIN_LH_EMPTY'),
                                   type => 'text' }] });
    }
    my @items = (_sortRow($client), map { entryRow($client, $_) } @{ sortEntries($rows, _sortMode()) });
    if (@$rows >= Plugins::ListeningHistory::DB::LIST_CAP()) {
        push @items, { type => 'text',
            name => sprintf(cstring($client, 'PLUGIN_LH_TRUNCATED'), scalar @$rows) };
    }
    $cb->({ items => \@items });
}

# The current sort mode, read LIVE from the pref each time.
sub _sortMode {
    my $m = $prefs->get('sort') // 'date';
    return $SORT_LABEL{$m} ? $m : 'date';
}

# Order entries for display. Every mode falls back to newest-first, then id, so the order is
# fully determined — XMLBrowser addresses a row by its position. Blank names sort LAST.
sub sortEntries {
    my ($rows, $mode) = @_;
    my $recent = sub { ($b->{played_at} // 0) <=> ($a->{played_at} // 0) || ($b->{id} // 0) <=> ($a->{id} // 0) };
    return [ sort { $recent->() } @$rows ] if $mode eq 'date';
    my $key = $mode eq 'artist'
        ? sub { lc($_[0]{artist} // '') }
        : sub { lc($_[0]{album} // $_[0]{title} // '') };
    my %k = map { $_->{id} => $key->($_) } @$rows;
    return [ sort {
        (($k{ $a->{id} } eq '') <=> ($k{ $b->{id} } eq ''))
            || $k{ $a->{id} } cmp $k{ $b->{id} }
            || $recent->()
    } @$rows ];
}

# "Sorted by date (tap to change)". Advances from the LIVE pref, not from what this render
# captured, so a stale page cannot step it backwards; an EMPTY answer with nextWindow
# 'refresh' re-walks the view in place. (Pitchfork Reviews' _yearSortToggle.)
#
# The Default / Classic web skins have no nextWindow: the empty answer would open as a blank
# page. There the answer is _webBounce instead, which sends the browser back to the list the
# row was on, now re-sorted. (Pitchfork Reviews' _webSkin / _webBounce rule.)
sub _sortRow {
    my ($client) = @_;
    return {
        name       => sprintf(cstring($client, 'PLUGIN_LH_SORTED_BY'),
                              cstring($client, $SORT_LABEL{ _sortMode() })),
        type       => 'link',
        image      => I_SORT,
        nextWindow => 'refresh',
        url        => sub {
            my ($c, $cb, $args) = @_;
            my $cur = _sortMode();
            my ($i) = grep { $SORT_MODES[$_] eq $cur } 0 .. $#SORT_MODES;
            $prefs->set('sort', $SORT_MODES[ ($i + 1) % @SORT_MODES ]);
            $cb->(_webSkin($args) ? _webBounce($c) : { items => [] });
        },
    };
}

# A web-skin request: XMLBrowser's isWeb, or feedMode on a CLI request (how a web skin
# fetches an itemActions row). Material sends neither.
sub _webSkin {
    my ($args) = @_;
    return 0 unless ref $args eq 'HASH';
    return 1 if $args->{isWeb};
    return (ref $args->{params} eq 'HASH' && defined $args->{params}{feedMode}) ? 1 : 0;
}

# A one-row answer whose script replaces the page with the list one level up (the page the
# tapped row was on), cache-busted so the skin re-walks it. The link is the fallback for a
# browser with scripts off. A textarea, because a web skin escapes a plain text row.
sub _webBounce {
    my ($client) = @_;
    my $js = "(function(){var u=new URL(location.href),p=u.searchParams,"
           . "i=(p.get('index')||'').split('.');i.splice(-1,1);"
           . "if(i.length&&i[0]!=='')p.set('index',i.join('.'));else p.delete('index');"
           . "p.set('lhr',Date.now());location.replace(u.href);})();";
    my $back = cstring($client, 'PLUGIN_LH_WEB_BACK');
    $back =~ s/&/&amp;/g; $back =~ s/</&lt;/g; $back =~ s/>/&gt;/g;
    return { items => [{
        type => 'textarea',
        name => '<div style="padding:8px 0"><a href="javascript:history.back()">'
              . $back . "</a></div><script>$js</script>",
    }], cachetime => 0 };
}

# ---------------------------------------------------------------------------
# By date: Today, Yesterday, then month → day → entries
# ---------------------------------------------------------------------------
sub _months {
    my ($client, $cb) = @_;
    my @items = (
        _link($client, 'PLUGIN_LH_TODAY',     I_DATE, \&_day, { ymd => _ymd(time()) }),
        # From MIDDAY today, not now: a clock-change day is 23 or 25 hours long, and now-minus-
        # 24h just after such a midnight lands two days back (or on today).
        _link($client, 'PLUGIN_LH_YESTERDAY', I_DATE, \&_day, { ymd => _ymd(_middayToday() - 86400) }),
    );
    for my $m (@{ Plugins::ListeningHistory::DB::months() }) {
        my ($y, $mo) = split /-/, $m->{ym};
        my $label = POSIX::strftime('%B %Y', 0, 0, 12, 1, $mo - 1, $y - 1900) . " ($m->{n})";
        push @items, _link($client, \$label, I_DATE, \&_days, { ym => $m->{ym} });
    }
    $cb->({ items => \@items });
}

sub _days {
    my ($client, $cb, $args, $pt) = @_;
    my @items;
    for my $d (@{ Plugins::ListeningHistory::DB::days($pt->{ym}) }) {
        my ($y, $mo, $dd) = split /-/, $d->{ymd};
        my $label = POSIX::strftime('%A %e %B', 0, 0, 12, $dd, $mo - 1, $y - 1900);
        $label =~ s/\s+/ /g;
        push @items, _link($client, \"$label ($d->{n})", I_DATE, \&_day, { ymd => $d->{ymd} });
    }
    return _entryList($client, $cb, []) unless @items;
    $cb->({ items => \@items });
}

sub _day {
    my ($client, $cb, $args, $pt) = @_;
    _entryList($client, $cb, Plugins::ListeningHistory::DB::forDay($pt->{ymd}));
}

sub _ymd { return POSIX::strftime('%Y-%m-%d', localtime($_[0])) }

sub _middayToday {
    my @t = localtime(time());
    return POSIX::mktime(0, 0, 12, $t[3], $t[4], $t[5]);
}

# ---------------------------------------------------------------------------
# By artist / album / player
# ---------------------------------------------------------------------------
sub _artists {
    my ($client, $cb) = @_;
    my @items = map {
        _link($client, \"$_->{artist} ($_->{n})", I_ARTIST, \&_artist, { artist => $_->{artist} })
    } @{ Plugins::ListeningHistory::DB::artists() };
    return _entryList($client, $cb, []) unless @items;
    $cb->({ items => \@items });
}

sub _artist {
    my ($client, $cb, $args, $pt) = @_;
    _entryList($client, $cb, Plugins::ListeningHistory::DB::forArtist($pt->{artist}));
}

sub _albums {
    my ($client, $cb) = @_;
    my @items = map {
        my $label = $_->{album} . (length $_->{artist} ? DASH . $_->{artist} : '') . " ($_->{n})";
        _link($client, \$label, $_->{artwork} || I_ALBUM, \&_album,
            { album => $_->{album}, artist => $_->{artist} })
    } @{ Plugins::ListeningHistory::DB::albums() };
    return _entryList($client, $cb, []) unless @items;
    $cb->({ items => \@items });
}

sub _album {
    my ($client, $cb, $args, $pt) = @_;
    _entryList($client, $cb, Plugins::ListeningHistory::DB::forAlbum($pt->{artist}, $pt->{album}));
}

# One row per LABEL, not per stored source: two sources shown under the same name (http and
# https are both "Web stream") would otherwise be two identical rows with nothing to tell
# them apart. The row carries every source it stands for.
sub _services {
    my ($client, $cb) = @_;
    my (%n, %src);
    for (@{ Plugins::ListeningHistory::DB::services() }) {
        my $label = Plugins::ListeningHistory::Sources::sourceLabel($_->{source});
        next unless length $label;
        $n{$label} += $_->{n};
        push @{ $src{$label} }, $_->{source};
    }
    return _entryList($client, $cb, []) unless %n;
    my @items = map {
        my $name = "$_ ($n{$_})";
        _link($client, \$name, I_SERVICE, \&_service, { sources => $src{$_} })
    } sort { lc $a cmp lc $b || $a cmp $b } keys %n;
    $cb->({ items => \@items });
}

sub _service {
    my ($client, $cb, $args, $pt) = @_;
    _entryList($client, $cb, Plugins::ListeningHistory::DB::forSource($pt->{sources}));
}

sub _players {
    my ($client, $cb) = @_;
    my @items = map {
        my $label = ($_->{player_name} // $_->{player_id}) . " ($_->{n})";
        _link($client, \$label, I_PLAYER, \&_player, { player_id => $_->{player_id} })
    } @{ Plugins::ListeningHistory::DB::players() };
    return _entryList($client, $cb, []) unless @items;
    $cb->({ items => \@items });
}

sub _player {
    my ($client, $cb, $args, $pt) = @_;
    _entryList($client, $cb, Plugins::ListeningHistory::DB::forPlayer($pt->{player_id}));
}

# ---------------------------------------------------------------------------
# One history row
# ---------------------------------------------------------------------------
sub entryRow {
    my ($client, $e) = @_;
    my $kind = $e->{kind} // 'track';

    my @sub;
    my ($name, %play);

    if ($kind eq 'album') {
        $name = _join($e->{artist}, $e->{album} // cstring($client, 'PLUGIN_LH_UNKNOWN_ALBUM'));
        my $n = $e->{tracks_played} || 0;
        push @sub, GLYPH_ALBUM . ' ' . ($e->{track_total}
            ? sprintf(cstring($client, 'PLUGIN_LH_TRACKS_OF'), $n, $e->{track_total})
            : sprintf(cstring($client, 'PLUGIN_LH_TRACKS'), $n));
        %play = (type => 'playlist', url => \&_entryTracks, passthrough => [{ id => $e->{id} }]);
    }
    elsif ($kind eq 'station') {
        $name = $e->{title} // $e->{url};
        push @sub, cstring($client, 'PLUGIN_LH_TYPE_STATION');
        %play = (type => 'audio', url => $e->{url});
    }
    else {
        $name = _join($e->{artist}, $e->{title} // cstring($client, 'PLUGIN_LH_UNKNOWN_TITLE'));
        push @sub, GLYPH_TRACK . ' ' . (defined $e->{album} && length $e->{album}
            ? sprintf(cstring($client, 'PLUGIN_LH_FROM'), $e->{album})
            : cstring($client, 'PLUGIN_LH_TYPE_TRACK'));
        %play = (type => 'audio', url => $e->{url});
    }

    push @sub, Plugins::ListeningHistory::Sources::sourceLabel($e->{source})
        unless $kind eq 'station';
    push @sub, $e->{player_name} if defined $e->{player_name} && length $e->{player_name};
    push @sub, _when($e->{played_at});

    return {
        name        => $name,
        line2       => join(SEP, @sub),
        image       => $e->{artwork} || ICON,
        %play,
        itemActions => {
            info => {
                command     => ['listeninghistory', 'contextmenu'],
                fixedParams => { id => $e->{id} },
            },
        },
    };
}

sub _join {
    my ($artist, $what) = @_;
    return (defined $artist && length $artist) ? $artist . DASH . $what : $what;
}

# Always the full date and time, "18 Sep 2026, 14:32" — today included, no day of the week
# (Simon, 2026-09-18).
sub _when {
    my ($t) = @_;
    return '' unless $t;
    return POSIX::strftime('%e %b %Y, %H:%M', localtime($t)) =~ s/^\s+//r;
}

# Drill-in and play of an album row: the whole album where the library or the service can
# rebuild it, otherwise the tracks that were played.
sub _entryTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $e = Plugins::ListeningHistory::DB::get($pt->{id});
    return $cb->({ items => [{ name => cstring($client, 'PLUGIN_LH_EMPTY'), type => 'text' }] })
        unless $e;
    Plugins::ListeningHistory::Sources::resolveTracks($client, $e, sub {
        my $items = shift || [];
        @$items = ({ name => cstring($client, 'PLUGIN_LH_NO_MATCH'), type => 'text' }) unless @$items;
        $cb->({ items => $items });
    });
}

1;
