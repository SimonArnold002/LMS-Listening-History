package Plugins::ListeningHistory::Sources;

# Two jobs, both about crossing between LMS and the stored history:
#
#   describe()      what is playing right now, as the fields an entry needs — source, names,
#                   artwork, the album key that groups back-to-back tracks, and the reference
#                   that plays it again.
#   resolveTracks() a stored album entry back into playable tracks.
#   libraryAlbum()  a library entry's album found again after a rescan, retag or move, its names
#                   following the library's; sweepTick() runs every library entry through it
#                   after each rescan.
#
# The per-service replay code is COPIED from Listen Later's Sources.pm, not shared: a
# sibling plugin cannot be `use`d (its package only resolves where it is installed), and a
# runtime dependency on another plugin being present would make this one's rows unplayable
# whenever it is not. Each copied piece names its origin so the two can be compared.

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Timers;

my $log = logger('plugin.listeninghistory');

# Qobuz album id -> its release type, for this server run (fetchReleaseType).
my %QOBUZ_TYPE;

# url scheme -> source tag, for the services whose tracks we can rebuild an album for.
# (LL Sources.pm %SCHEME)
my %SCHEME = (
    qobuz    => 'qobuz',
    bandcamp => 'bandcamp',
    tidal    => 'tidal',
    deezer   => 'deezer',
    spotify  => 'spotify',
);

# How a source is written in a row's subtitle and the By service menu, where ucfirst would
# read wrongly. Each label names ONE kind of thing: Deezer podcast episodes are not "Deezer"
# (that is the music service's row), and a plain web stream is not "Http". Sources that share
# a label are merged into one By service row (Browse::_services).
my %SOURCE_LABEL = (
    library       => 'Library',
    tidal         => 'TIDAL',
    deezerpodcast => 'Deezer podcasts',
    http          => 'Web stream',
    https         => 'Web stream',
    radio         => 'Radio',
);

sub sourceLabel {
    my ($source) = @_;
    return '' unless defined $source && length $source;
    return $SOURCE_LABEL{$source} || ucfirst($source);
}

# Source tag or url scheme -> the prefix Material's emblems.json keys its service badge on.
# Material (upstream d3f1d9227, 2026-09-18) badges a SlimBrowse row from the part of its
# `extid` before the first ':'; LMS 9.1 XMLBrowser passes a feed item's extid through.
my %EMBLEM = (
    qobuz         => 'qobuz',
    tidal         => 'tidal',
    wimp          => 'wimp',
    deezer        => 'deezer',
    deezerpodcast => 'deezer',
    spotify       => 'spotify',
    bandcamp      => 'bandcamp',
    radioparadise => 'radioparadise',
    sounds        => 'bbc',        # BBC Sounds plays sounds:// urls
    youtube       => 'youtube',
    ytm           => 'ytm',
    pandora       => 'pandora',
);

# The row's extid, or undef for a row with no service badge (library, plain radio, the web).
# The stored source decides first; a station (source 'radio') is badged from its url scheme.
# An album row with the service's own album id carries the real "<svc>:album:<id>"; any other
# row carries the bare "<svc>:" — on a SlimBrowse row the prefix is all Material reads.
sub extid {
    my ($e) = @_;
    my $pfx = $EMBLEM{ $e->{source} // '' };
    $pfx //= $EMBLEM{ lc $1 } if !defined $pfx && ($e->{url} // '') =~ m{^(\w+):};
    return undef unless $pfx;
    my $id = ref $e->{ref} eq 'HASH' ? $e->{ref}{svc_album_id} : undef;
    return ($e->{kind} // '') eq 'album' && defined $id && length $id ? "$pfx:album:$id" : "$pfx:";
}

sub isServiceSource { return $SCHEME{ $_[0] // '' } ? 1 : 0 }

# 'library' for a local file, the service tag for a known streaming scheme, otherwise the
# scheme itself (http, https, sounds, …).
sub sourceFromUrl {
    my ($url) = @_;
    return 'library' unless defined $url && $url =~ m{^(\w+)://};
    my $scheme = lc $1;
    return 'library' if $scheme eq 'file';
    return $SCHEME{$scheme} || $scheme;
}

# The protocol handler's metadata for a url, always a hashref. Streaming services keep
# album, artist and cover here rather than on the LMS track row. (LL Sources::playingMeta)
sub playingMeta {
    my ($client, $url) = @_;
    return {} unless defined $url && length $url;
    my $handler = eval { Slim::Player::ProtocolHandlers->handlerForURL($url) } or return {};
    return {} unless $handler->can('getMetadataFor');
    my $meta = eval { $handler->getMetadataFor($client, $url) };
    return ref $meta eq 'HASH' ? $meta : {};
}

# A handler value can arrive as a plain string, a hash ({name => …}) or an object with a
# name. (HQPlayer Bridge Player::_handlerMeta)
sub _str {
    my ($v) = @_;
    return undef unless defined $v;
    if (ref $v) {
        $v = ref $v eq 'HASH' ? ($v->{name} // $v->{title})
           : eval { $v->can('name') } ? $v->name
           : undef;
    }
    return undef unless defined $v && !ref $v;
    $v =~ s/^\s+|\s+$//g;
    return length $v ? $v : undef;
}

sub _first { for (@_) { my $s = _str($_); return $s if defined $s } return undef }

# Does this url play song after song on ONE url? LMS's own test: the handler's isRepeatingStream
# (Radio Paradise). There the url does not identify a song, the title does.
sub sharesUrl {
    my ($url, $song) = @_;
    my $handler = eval { Slim::Player::ProtocolHandlers->handlerForURL($url) } or return 0;
    return 0 unless $handler->can('isRepeatingStream');
    return eval { $handler->isRepeatingStream($song) } ? 1 : 0;
}

# The playing track's length in seconds, 0 if unknown. For a REMOTE track the protocol handler's
# figure comes first: it describes the song playing now, where the song's own can be missing (a
# queued streaming track the service has not described yet) or stale (Radio Paradise plays every
# song as a clone on one url; the clone keeps no length of its own and reads the shared track's,
# which RP's getMetadataFor only updates when asked, so at newsong it is the PREVIOUS song's).
# $meta, the handler's metadata, when the caller already has it.
sub trackDuration {
    my ($client, $song, $url, $remote, $meta) = @_;
    if ($remote) {
        my $m = ($meta || playingMeta($client, $url))->{duration};
        return $m + 0 if defined $m && !ref $m && $m =~ /^[\d.]+$/ && $m > 0;
    }
    return eval { $song->duration } || 0;
}

# The artist a group of tracks is keyed on. Services credit every artist on a track
# ("Kygo, Khalid, Gryffin" from Spotty), so two tracks of one album can carry different
# full credits; their FIRST credit agrees.
sub primaryArtist {
    my ($artist) = @_;
    return '' unless defined $artist;
    my ($p) = split /\s*(?:,|;|&|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b|\bx\b)\s*/i, $artist;
    $p //= '';
    $p =~ s/^\s+|\s+$//g;
    return lc $p;
}

# What identifies "the same album" for grouping back-to-back tracks: the library album id,
# a service album id, or failing both the service plus album title plus primary artist.
# undef means this track never groups (it has no album at all).
sub albumKey {
    my ($d) = @_;
    my $ref = $d->{ref} || {};
    return "lib:$ref->{album_id}" if $d->{source} eq 'library' && $ref->{album_id};
    return "$d->{source}:id:$ref->{svc_album_id}" if $ref->{svc_album_id};
    return undef unless defined $d->{album} && length $d->{album};
    return join ':', $d->{source}, 'name', lc($d->{album}) . '|' . primaryArtist($d->{artist});
}

# Is this remote url one we cannot identify a track in — a live stream? Service schemes are
# never radio (a service track with no duration is an error answer, not a station); any
# other remote url with no duration is. UNVERIFIED LIVE against every radio source.
sub isStation {
    my ($source, $duration, $remote) = @_;
    return 0 unless $remote;
    return 0 if isServiceSource($source) || $source eq 'deezerpodcast';
    return ($duration // 0) > 0 ? 0 : 1;
}

# Describe the playing song. Returns a hash, or undef with a reason for the log when the
# track is not something we record.
#
#   source, remote, url, title, artist, album, year, artwork, duration,
#   is_station, track_total, album_key, ref (album_id + album_mbid, track_mbid, album_url for
#   libraryAlbum | svc_album_id, svc, release_type)
sub describe {
    my ($client, $song, $track, $url) = @_;
    return (undef, 'no url') unless defined $url && length $url;

    my $remote = eval { $track->can('remote') ? $track->remote : undef };
    $remote = ($url !~ m{^file:}i && $url =~ m{^\w+://}) ? 1 : 0 unless defined $remote;
    my $source   = $remote ? sourceFromUrl($url) : 'library';
    my $duration = eval { $song->duration } || 0;

    my %d = (source => $source, remote => $remote ? 1 : 0, url => $url, ref => {});

    if (!$remote) {
        my $alb = eval { $track->album };
        $alb = undef unless ref $alb;
        $d{title}  = _str(eval { $track->title });
        $d{artist} = _str(eval { $track->artistName });
        if ($alb) {
            $d{album} = _str(eval { $alb->title });
            my $aa = _str(eval { $alb->contributor ? $alb->contributor->name : undef });
            $d{album_artist} = $aa if defined $aa;
            my $y = eval { $alb->year };
            $d{year} = $y if $y && $y =~ /^\d{4}$/;
            if (my $aid = eval { $alb->id }) {
                $d{ref}{album_id} = $aid;
                # The keys that outlive the row id (libraryAlbum): a rescan renumbers the album.
                %{ $d{ref} } = (%{ $d{ref} }, _albumKeys($alb, $track));
                $d{track_total} = eval {
                    Slim::Schema->search('Track', { 'album.id' => $aid }, { join => 'album' })->count;
                } || undef;
            }
            my $art = eval { $alb->artwork };
            $d{artwork} = "/music/$art/cover" if $art && $art !~ /^-/;
        }
        $d{artist} //= $d{album_artist};
        $d{duration} = $duration;
    }
    else {
        my $meta = playingMeta($client, $url);
        # The handler's own title first: LMS stores the name of the row a track was started from
        # as its title (`playlist play <url> <title>`), and a favourite or one of our own track
        # rows is named "Title by Artist from Album". NOT for a plain web track: LMS's own HTTP
        # handler builds its title from that same row name, split at one " - " into artist and
        # title, so there the track's own title stays first. A station is named from $track below.
        my $web = $source =~ /^https?$/;
        $d{title}  = $web ? _first(eval { $track->title }, $meta->{title})
                          : _first($meta->{title}, eval { $track->title });
        # The same split gives the front half as the ARTIST. Recognised by the halves rejoining to
        # the track's own title; an artist the handler really has (stream metadata) is kept.
        my $split = $web && _isSplit($meta, eval { $track->title });
        $d{artist} = _first($split ? () : $meta->{artist}, eval { $track->artistName });
        $d{album}  = _first($meta->{album}, eval { $track->albumname });
        my $y = $meta->{year};
        $d{year}    = $y if defined $y && !ref $y && $y =~ /^\d{4}$/;
        $d{artwork} = _first(@{$meta}{qw(cover image icon artwork_url)});
        $d{duration} = trackDuration($client, $song, $url, 1, $meta);

        $d{is_station} = isStation($source, $d{duration}, 1);

        if ($d{is_station}) {
            # A station is named after the STATION, which is what the track title holds for a
            # stream (the menu title); the handler's title is the now-playing song. Stations are
            # not recorded since 1.0.15: the name is for Tracker's log line and old station rows.
            $d{title}  = _first(eval { $track->title }, $meta->{title}, $url);
            $d{artist} = undef;
            $d{album}  = undef;
            $d{source} = 'radio';
        }
        elsif ($d{duration} <= 0) {
            # A service track that reports no length: Spotty's "not authorised" / "no SSL"
            # answers put an error hint in title AND artist with duration 0. Never record it.
            return (undef, "no duration from $source");
        }
        else {
            my $aid = _first($meta->{albumId}, $meta->{album_id});
            $aid //= _spotifyAlbumId($url) if $source eq 'spotify';
            if (defined $aid) {
                $d{ref}{svc_album_id} = $aid;
                $d{ref}{svc}          = $source;
                # Already asked this run (fetchReleaseType): an album promotion rewrites the
                # entry's ref from THIS hash, so it must carry the type too.
                my $rt = $source eq 'qobuz' ? $QOBUZ_TYPE{$aid} : undef;
                $d{ref}{release_type} = $rt if $rt;
            }
        }
    }

    return (undef, 'no title') unless defined $d{title} && length $d{title};
    $d{album_key} = $d{is_station} ? "station:$url" : albumKey(\%d);
    return \%d;
}

# Did LMS's HTTP handler make its artist and title by splitting this title at " - "?
sub _isSplit {
    my ($meta, $title) = @_;
    my ($a, $t) = (_str($meta->{artist}), _str($meta->{title}));
    $title = _str($title);
    return 0 unless defined $a && defined $t && defined $title;
    my $sq = sub { (my $v = lc shift) =~ s/\s+/ /g; $v };
    return $sq->("$a - $t") eq $sq->($title) ? 1 : 0;
}

# The Spotify release id of a playing track, from Spotty's own track cache (no Web API
# call). Spotty's getMetadataFor publishes no album id. (LL Played::_spotifyAlbumRecord)
sub _spotifyAlbumId {
    my ($url) = @_;
    (my $uri = $url) =~ s{/}{}g;
    return undef unless $uri =~ /^spotify:track:/;
    return undef unless Plugins::Spotty::API->can('trackCached');
    my $cached = eval { Plugins::Spotty::API->trackCached(undef, $uri, { noLookup => 1 }) };
    $log->warn("Listening History: Spotty trackCached died for $uri: $@") if $@;
    return undef unless ref $cached eq 'HASH' && ref $cached->{album} eq 'HASH';
    my $id = $cached->{album}{id};
    return (defined $id && length $id) ? $id : undef;
}

# ---------------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------------

# Can this service rebuild an album node here? (LL Sources::_serviceCan)
sub serviceCan {
    my ($source) = @_;
    return 0 unless defined $source;
    return 1 if $source eq 'qobuz'    && Plugins::Qobuz::Plugin->can('QobuzGetTracks');
    return 1 if $source eq 'tidal'    && Plugins::TIDAL::Plugin->can('getAlbum');
    return 1 if $source eq 'deezer'   && Plugins::Deezer::Plugin->can('getAlbum');
    return 1 if $source eq 'spotify'  && Plugins::Spotty::OPML->can('album');
    return 0;
}

# The service's own album coderef and the passthrough it expects. Each service spells the
# id differently, and getting it wrong returns an empty album, not an error.
# (LL Sources::_streamingAlbumNode; Bandcamp is left out because its album call needs the
# album PAGE url, which a playing Bandcamp track does not give us.)
sub _albumNode {
    my ($source, $albumId) = @_;
    return undef unless serviceCan($source) && defined $albumId && length $albumId;
    return (\&Plugins::Qobuz::Plugin::QobuzGetTracks, { album_id => $albumId }) if $source eq 'qobuz';
    return (\&Plugins::TIDAL::Plugin::getAlbum,       { id => $albumId })       if $source eq 'tidal';
    return (\&Plugins::Deezer::Plugin::getAlbum,      { id => $albumId })       if $source eq 'deezer';
    # Spotty wants the full URI; a bare id matches nothing and returns no tracks.
    return (\&Plugins::Spotty::OPML::album, { uri => "spotify:album:$albumId" }) if $source eq 'spotify';
    return undef;
}

# Does this item play? A port of LMS's own hasAudio (Slim::Control::XMLBrowser), an
# ALLOW-list: Qobuz sends info rows ('Credits', 'Copyright', …) with no type at all, and a
# deny-list would count them as tracks. (LL Sources::isPlayableTrack)
sub isPlayableTrack {
    my ($i) = @_;
    return 0 unless ref $i eq 'HASH';
    return 1 if $i->{play};
    return 1 if ((($i->{type} // '') =~ /^(?:audio|playlist)$/)
                 && ($i->{playlist} || $i->{url} || scalar @{ $i->{outline} || [] }));
    return 1 if ref $i->{enclosure} eq 'HASH' && (($i->{enclosure}{type} // '') =~ /audio/);
    return 0;
}

# The tracks that were actually played for an entry, as playable items. Always available,
# for any source, which is why it is the fallback for every album the service cannot rebuild.
sub playedTracks {
    my ($entry) = @_;
    my $plays = Plugins::ListeningHistory::DB->can('plays')->($entry->{id});
    my %seen;
    return [ map {
        { name => $_->{title} // $_->{url}, type => 'audio', url => $_->{url},
          ($entry->{artwork} ? (image => $entry->{artwork}) : ()) }
    } grep { defined $_->{url} && !$seen{ $_->{url} }++ } @$plays ];
}

sub _libraryTracks {
    my ($albumId) = @_;
    my @items;
    my $rs = eval {
        Slim::Schema->search('Track', { 'album.id' => $albumId },
            { join => 'album', order_by => 'me.disc, me.tracknum' });
    } or return [];
    while (my $t = $rs->next) {
        push @items, { name => $t->title, type => 'audio', url => $t->url };
    }
    return \@items;
}

# ---------------------------------------------------------------------------
# A library entry's album, found again after a rescan. `ref.album_id` is LMS's albums.id, a row
# number: "Clear library and rescan" (schema_clear.sql DELETEs the table; the id is AUTOINCREMENT,
# so an old number is never reused) and a retag of the album's title or artist both leave it
# pointing at NOTHING, never at another album. So the album is looked for the way LMS itself
# keeps things across a rescan, most exact key first (Simon, 2026-09-24: "follow what LMS does"):
#
#   1. the row id, while it still exists
#   2. the album's MusicBrainz release id (albums.musicbrainz_id) — how the scanner itself tells
#      one tagged album from another (_createOrUpdateAlbum)
#   3. the files that were played — persist.db's urlmd5; a wipe and a retag keep the path
#   4. the track's MusicBrainz id — persist.db's FIRST key, but here only when it names ONE album:
#      it is the RECORDING id (MUSICBRAINZ_TRACKID / UFID), which repeats on every compilation
#      the song is on. After the urls for that reason: a url that resolves is exact.
#   5. LMS's own album url, `Album::url` (extid, else db:album.title=…&contributor.name=…), which
#      is how an LMS favourite finds its album again — by name, the first match. Only once every
#      exact key has failed: it is what recovers an untagged album whose files were moved.
#
# A find by 2–5 is written back (relinkLibrary), so the next read is step 1 again. Never while a
# scan runs: the library is half-built (persist.db skips its writes then too, LMS bug 16003).
# ---------------------------------------------------------------------------

my $UUID = qr/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

sub _mbid {
    my ($v) = @_;
    return (defined $v && !ref $v && $v =~ $UUID) ? $v : undef;
}

# The lasting keys of a library album, and of the track played from it when there is one.
sub _albumKeys {
    my ($alb, $track) = @_;
    my %k;
    my $url = eval { $alb->url };
    $k{album_url}  = $url if defined $url && !ref $url && length $url;
    my $am = _mbid(eval { $alb->musicbrainz_id });
    $k{album_mbid} = $am if $am;
    my $tm = $track ? _mbid(eval { $track->musicbrainz_id }) : undef;
    $k{track_mbid} = $tm if $tm;
    return %k;
}

sub _scanning { return eval { Slim::Music::Import->stillScanning } ? 1 : 0 }

# The urls an entry played: a track entry's own, an album entry's plays.
sub _entryUrls {
    my ($e) = @_;
    my %seen;
    my @urls = grep { defined && length && !$seen{$_}++ }
        ($e->{url}, map { $_->{url} } @{ Plugins::ListeningHistory::DB->can('plays')->($e->{id}) || [] });
    return @urls;
}

sub _trackForUrl {
    my ($url) = @_;
    my $t = eval { Slim::Schema->objectForUrl({ url => $url, create => 0 }) };
    return (ref $t && eval { $t->can('album') }) ? $t : undef;
}

# The one album every item maps to, or undef when they disagree or none maps.
sub _sameAlbum {
    my %by;
    for my $alb (@_) {
        my $id = ref $alb ? eval { $alb->id } : undef;
        $by{$id} //= $alb if defined $id;
    }
    return keys %by == 1 ? (values %by)[0] : undef;
}

sub _byAlbumMbid {
    my ($ref, $urls) = @_;
    my $mbid = _mbid($ref->{album_mbid}) or return undef;
    my @albums = eval { Slim::Schema->search('Album', { musicbrainz_id => $mbid })->all };
    return $albums[0] if @albums == 1;
    return undef unless @albums;
    # One release split into several albums (a disc per album): the one this entry played.
    my %ours = map { my $al = eval { $_->album }; $al ? (eval { $al->id } => 1) : () }
               grep { defined } map { _trackForUrl($_) } @$urls;
    my @hit = grep { $ours{ eval { $_->id } // '' } } @albums;
    return @hit == 1 ? $hit[0] : undef;
}

sub _byUrls {
    my ($urls) = @_;
    return _sameAlbum(map { my $t = _trackForUrl($_); $t ? eval { $t->album } : () } @$urls);
}

sub _byTrackMbid {
    my ($ref) = @_;
    my $mbid = _mbid($ref->{track_mbid}) or return undef;
    my @tracks = eval { Slim::Schema->search('Track', { musicbrainz_id => $mbid })->all };
    return _sameAlbum(map { eval { $_->album } || () } @tracks);
}

sub _byAlbumUrl {
    my ($e) = @_;
    my $ref = $e->{ref} || {};
    my $url = $ref->{album_url};
    # Stored before the keys were: an ALBUM entry's artist is the album artist (the promotion
    # stores album_artist), so LMS's url can be rebuilt; a track entry's artist is the track's.
    # Built from the stored names, which describe() trimmed (_str): an album whose title starts or
    # ends in whitespace is not found this way.
    if (!defined $url && ($e->{kind} // '') eq 'album'
        && defined $e->{album} && length $e->{album} && defined $e->{artist} && length $e->{artist})
    {
        require URI::Escape;
        $url = sprintf('db:album.title=%s&contributor.name=%s',
            URI::Escape::uri_escape_utf8($e->{album}), URI::Escape::uri_escape_utf8($e->{artist}));
    }
    return undef unless defined $url && $url =~ /^db:album\./;
    my $alb = eval { Slim::Schema->objectForUrl({ url => $url, create => 0 }) };
    return (ref $alb && eval { $alb->id }) ? $alb : undef;
}

# The names an entry should carry for $alb, where they differ from what it carries now (Simon,
# 2026-09-24: history follows the library — a retag renames the row, so it groups and searches
# with the plays that come after it). An ALBUM entry: title, album artist (the name the promotion
# stores) and year. A TRACK entry: album and year, and its own track's title and artist when its
# file is still on this album. Trimmed as describe() trims (_str), so a name never differs by
# whitespace alone. The play log (plays) keeps what was heard.
sub _nameChanges {
    my ($e, $alb) = @_;
    my %n;
    my $set = sub { my ($k, $v) = @_; $n{$k} = $v if defined $v && ($e->{$k} // '') ne $v };
    $set->(album => _str(eval { $alb->title }));
    my $y = eval { $alb->year };
    $set->(year => $y) if defined $y && $y =~ /^\d{4}$/;
    if (($e->{kind} // '') eq 'album') {
        $set->(artist => _str(eval { $alb->contributor ? $alb->contributor->name : undef }));
    }
    elsif (my $t = _trackForUrl($e->{url})) {
        my $ta = eval { $t->album };
        if ($ta && (eval { $ta->id } // '') eq (eval { $alb->id } // '-')) {
            $set->(title  => _str(eval { $t->title }));
            $set->(artist => _first(eval { $t->artistName },
                                    eval { $alb->contributor ? $alb->contributor->name : undef }));
        }
    }
    return %n;
}

# The live LMS album of a library entry, or undef (in list context also what was written:
# 'relinked', 'renamed' or ''). $mode:
#   undef    a list being rendered (releaseType): a stale album is found again and written back,
#            names included, but an entry whose album is still there is only read.
#   'open'   one entry being opened (resolveTracks), and
#   'sweep'  the pass after a rescan (sweepTick): also store the lasting keys an entry recorded
#            before them lacks, and bring its names in line with the library's.
sub libraryAlbum {
    my ($e, $mode) = @_;
    my $out = sub { return wantarray ? @_ : $_[0] };
    return $out->(undef, '') unless ref $e eq 'HASH' && ($e->{source} // '') eq 'library';
    my $ref = ref $e->{ref} eq 'HASH' ? $e->{ref} : {};
    my $old = $ref->{album_id} or return $out->(undef, '');

    if (my $alb = eval { Slim::Schema->find('Album', $old) }) {
        return $out->($alb, '') unless $mode && !_scanning();
        my %w;
        if (!defined $ref->{album_url}) {
            my $t;
            for (_entryUrls($e)) { last if $t = _trackForUrl($_) }
            %w = _albumKeys($alb, $t);
        }
        my %n = _nameChanges($e, $alb);
        return $out->($alb, '') unless %w || %n;
        return $out->($alb, '') unless Plugins::ListeningHistory::DB::relinkLibrary($e->{id}, $old, { album_id => $old, %w, %n });
        %$ref = (%$ref, %w);
        @{$e}{ keys %n } = values %n;
        return $out->($alb, %n ? 'renamed' : '');
    }

    my @urls = _entryUrls($e);
    my ($alb, $how);
    ($alb = _byAlbumMbid($ref, \@urls)) and $how = 'album MusicBrainz id';
    $alb or (($alb = _byUrls(\@urls))   and $how = 'played files');
    $alb or (($alb = _byTrackMbid($ref)) and $how = 'track MusicBrainz id');
    $alb or (($alb = _byAlbumUrl($e))   and $how = 'album name');
    return $out->(undef, '') unless $alb;

    my $new = eval { $alb->id } or return $out->(undef, '');
    my $art = eval { $alb->artwork };
    my %n   = _nameChanges($e, $alb);
    my %new = (album_id => $new, _albumKeys($alb, undef), %n,
               (_mbid($ref->{track_mbid}) ? (track_mbid => $ref->{track_mbid}) : ()),
               ($art && $art !~ /^-/ ? (artwork => "/music/$art/cover") : ()));
    if (_scanning()) {
        $log->info("Listening History: entry $e->{id} album $old is now $new (by $how); not stored during a scan");
        return $out->($alb, '');
    }
    return $out->($alb, '') unless Plugins::ListeningHistory::DB::relinkLibrary($e->{id}, $old, \%new);
    $log->info("Listening History: entry $e->{id} album $old is now $new (found by $how)");
    $e->{artwork}   = delete $new{artwork} if defined $new{artwork};
    $e->{album_key} = "lib:$new" if ($e->{album_key} // '') eq "lib:$old";
    @{$e}{ keys %n } = values %n;
    delete @new{ keys %n };
    %$ref = (%$ref, %new);
    $e->{ref} = $ref;
    return $out->($alb, 'relinked');
}

# ---------------------------------------------------------------------------
# The sweep after a rescan. A rescan is when albums are renumbered and renamed, so when LMS says
# one has finished (['rescan', 'done'], Slim::Music::Import) every library entry is run through
# libraryAlbum('sweep'): a stale album is found again, the names follow the library, and an entry
# recorded before the lasting keys gains them. Also once after startup, for a scan that finished
# while the plugin was not running. SWEEP_BATCH entries per tick, SWEEP_GAP seconds apart, so the
# server never stalls; while a scan runs it waits and carries on from where it was.
# ---------------------------------------------------------------------------
use constant SWEEP_BATCH => 25;
use constant SWEEP_GAP   => 1;
use constant SWEEP_WAIT  => 30;

my %SWEEP;   # { after => last entry id done, seen, relinked, renamed } while a sweep is under way

sub startSweep {
    my ($delay) = @_;
    Slim::Utils::Timers::killTimers(undef, \&sweepTick);
    %SWEEP = (after => 0, seen => 0, relinked => 0, renamed => 0);
    Slim::Utils::Timers::setTimer(undef, time() + ($delay // 10), \&sweepTick);
    return;
}

sub stopSweep {
    Slim::Utils::Timers::killTimers(undef, \&sweepTick);
    %SWEEP = ();
    return;
}

# Timer body. A named sub, so killTimers can pair on the coderef.
sub sweepTick {
    return unless %SWEEP;
    if (_scanning()) {
        Slim::Utils::Timers::setTimer(undef, time() + SWEEP_WAIT, \&sweepTick);
        return;
    }
    my $rows = Plugins::ListeningHistory::DB::libraryAfter($SWEEP{after}, SWEEP_BATCH);
    unless (@$rows) {
        my $msg = "Listening History: library check done — $SWEEP{seen} entries, $SWEEP{relinked} "
                . "found their album again, $SWEEP{renamed} renamed to follow the library";
        ($SWEEP{relinked} || $SWEEP{renamed}) ? $log->warn($msg) : $log->info($msg);
        %SWEEP = ();
        return;
    }
    for my $e (@$rows) {
        $SWEEP{after} = $e->{id};
        $SWEEP{seen}++;
        my (undef, $what) = eval { libraryAlbum($e, 'sweep') };
        $log->error("Listening History: checking entry $e->{id} failed: $@") if $@;
        $SWEEP{relinked}++ if ($what // '') eq 'relinked';
        $SWEEP{renamed}++  if ($what // '') eq 'renamed';
    }
    Slim::Utils::Timers::setTimer(undef, time() + SWEEP_GAP, \&sweepTick);
    return;
}

# A stored ALBUM entry as playable tracks: the whole album when its library or service can
# rebuild it, otherwise the tracks that were played. $cb->(\@items).
sub resolveTracks {
    my ($client, $entry, $cb) = @_;
    my $ref = $entry->{ref} || {};

    if ($entry->{source} eq 'library' && $ref->{album_id}) {
        my $alb   = libraryAlbum($entry, 'open');
        my $items = $alb ? _libraryTracks(eval { $alb->id }) : [];
        return $cb->(@$items ? $items : playedTracks($entry));
    }

    my ($code, $pt) = _albumNode($ref->{svc} // $entry->{source}, $ref->{svc_album_id});
    return $cb->(playedTracks($entry)) unless $code;

    my $done;
    my $answer = sub {
        return if $done++;
        my $res = shift;
        # Qobuz, TIDAL and Deezer answer { items => [...] }; others a bare arrayref.
        my $items = ref $res eq 'HASH'  ? ($res->{items} || [])
                  : ref $res eq 'ARRAY' ? $res : [];
        my @tracks = grep { isPlayableTrack($_) } @$items;
        unless (@tracks) {
            $log->warn("Listening History: $entry->{source} returned no tracks for album "
                . "$ref->{svc_album_id} — playing the tracks that were recorded");
            return $cb->(playedTracks($entry));
        }
        $cb->(\@tracks);
    };
    eval { $code->($client, $answer, {}, $pt); 1 } or do {
        $log->warn("Listening History: $entry->{source} album call died: $@");
        $answer->([]);
    };
    return;
}

# ---------------------------------------------------------------------------
# Release type — ALBUM, EP, SINGLE, COMPILATION …, the types LMS groups an artist's releases by
# (Simon, 2026-09-19: "By release … break them down like LMS"). Upper-case, as LMS stores them.
# ---------------------------------------------------------------------------

# The type of a stored entry's release. The LIBRARY is read live from LMS, so every entry
# already in the history has one and a retag + rescan moves it (libraryAlbum finds the album
# again when the rescan renumbered it; this is a list render, so it relinks but never captures). QOBUZ is what fetchReleaseType
# stored when it played. Nothing else states a type (Tidal, Deezer and Spotify only through
# their plugins' internals — declined fleet-wide, see the streaming-service-apis note), so
# everything else is ALBUM, which is also what Material assumes for a release with no type.
sub releaseType {
    my ($e) = @_;
    return 'ALBUM' unless ref $e eq 'HASH';
    my $ref = ref $e->{ref} eq 'HASH' ? $e->{ref} : {};
    if (($e->{source} // '') eq 'library' && $ref->{album_id}) {
        my $t = _libraryReleaseType(scalar libraryAlbum($e));
        return $t if $t;
    }
    return _normType($ref->{release_type}) || 'ALBUM';
}

# A service's own spelling of an LMS type. Qobuz's album object says `epmini` for an EP (its
# `album` / `single` already match), and its plugin shows that raw as "Epmini". Applied on every
# read as well as on store, so an entry stored before the alias existed is read right too.
my %TYPE_ALIAS = (EPMINI => 'EP');

sub _normType {
    my ($t) = @_;
    return undef unless defined $t && !ref $t;
    $t = uc $t;
    $t =~ s/^\s+|\s+$//g;
    return undef unless length $t;
    return $TYPE_ALIAS{$t} // $t;
}

# LMS 8.4+ `albums.release_type`. Material's rule (browse-resp.js): a compilation whose type is
# ALBUM, or has none, groups as COMPILATION.
sub _libraryReleaseType {
    my ($alb) = @_;
    return undef unless $alb;
    my $t = _normType(eval { $alb->release_type });
    return 'COMPILATION' if eval { $alb->compilation } && (!$t || $t eq 'ALBUM');
    return $t;
}

# The order Material lists release types in (browse-resp.js RELEASE_TYPES); any other type
# follows, A–Z.
my @TYPE_ORDER = qw(ALBUM EP BOXSET BESTOF COMPILATION SINGLE APPEARANCE);
my %TYPE_RANK  = map { $TYPE_ORDER[$_] => $_ } 0 .. $#TYPE_ORDER;

sub sortReleaseTypes {
    return sort { ($TYPE_RANK{$a} // @TYPE_ORDER) <=> ($TYPE_RANK{$b} // @TYPE_ORDER) || $a cmp $b } @_;
}

# The plural name LMS gives a type: "Albums", "EPs", "Singles". LMS's own
# Slim::Schema::Album::releaseTypeName (8.4+) — the name its library uses — when it is there;
# otherwise the same lookup, copied: RELEASE_TYPE_<T>S, RELEASE_TYPE_CUSTOM_<T>, <T>S,
# RELEASE_TYPE_<T>, <T> — the first that exists and is not empty (RELEASE_TYPE_ALBUMS is empty,
# so ALBUM lands on ALBUMS) — else the type spelled out.
sub releaseTypeLabel {
    my ($client, $type) = @_;
    $type //= '';
    if (Slim::Schema::Album->can('releaseTypeName')) {
        my $name = eval { Slim::Schema::Album->releaseTypeName($type, $client) };
        return $name if defined $name && length $name && $name ne $type;
    }
    (my $tok = uc $type) =~ s/[^A-Z_0-9]/_/g;
    for my $s ("RELEASE_TYPE_${tok}S", "RELEASE_TYPE_CUSTOM_$tok", "${tok}S", "RELEASE_TYPE_$tok", $tok) {
        next unless Slim::Utils::Strings::stringExists($s);
        my $name = cstring($client, $s);
        return $name if defined $name && length $name;
    }
    return join ' ', map { ucfirst lc } split /\s+/, $type;
}

# Ask Qobuz for a release's type: its album object states album / ep / single (LL
# Sources::classifyRelType uses the same call). Once per album per server run; $cb gets the
# upper-cased type, or undef. Every other source answers undef at once.
sub fetchReleaseType {
    my ($client, $source, $aid, $cb) = @_;
    return $cb->(undef) unless ($source // '') eq 'qobuz' && defined $aid && length $aid;
    return $cb->($QOBUZ_TYPE{$aid}) if $QOBUZ_TYPE{$aid};
    my $api = Plugins::Qobuz::Plugin->can('getAPIHandler')
        ? eval { Plugins::Qobuz::Plugin::getAPIHandler($client) } : undef;
    return $cb->(undef) unless $api && $api->can('getAlbum');
    my $done;
    my $ok = eval {
        $api->getAlbum(sub {
            return if $done++;
            my $album = shift;
            my $rt = _normType(ref $album eq 'HASH' ? $album->{release_type} : undef);
            $QOBUZ_TYPE{$aid} = $rt if $rt;
            $cb->($rt);
        }, $aid);
        1;
    };
    return if $ok;
    $log->warn("Listening History: Qobuz getAlbum died: $@");
    $cb->(undef) unless $done++;
}

1;
