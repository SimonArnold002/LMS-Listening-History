package Plugins::ListeningHistory::Sources;

# Two jobs, both about crossing between LMS and the stored history:
#
#   describe()      what is playing right now, as the fields an entry needs — source, names,
#                   artwork, the album key that groups back-to-back tracks, and the reference
#                   that plays it again.
#   resolveTracks() a stored album entry back into playable tracks.
#
# The per-service replay code is COPIED from Listen Later's Sources.pm, not shared: a
# sibling plugin cannot be `use`d (its package only resolves where it is installed), and a
# runtime dependency on another plugin being present would make this one's rows unplayable
# whenever it is not. Each copied piece names its origin so the two can be compared.

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('plugin.listeninghistory');

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
#   is_station, track_total, ref (album_id | svc_album_id, svc), album_key
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
        $d{title}  = _first(eval { $track->title }, $meta->{title});
        $d{artist} = _first($meta->{artist}, eval { $track->artistName });
        $d{album}  = _first($meta->{album}, eval { $track->albumname });
        my $y = $meta->{year};
        $d{year}    = $y if defined $y && !ref $y && $y =~ /^\d{4}$/;
        $d{artwork} = _first(@{$meta}{qw(cover image icon artwork_url)});
        my $mdur    = $meta->{duration};
        $d{duration} = $duration > 0 ? $duration
                     : (defined $mdur && !ref $mdur && $mdur =~ /^[\d.]+$/ ? $mdur : 0);

        $d{is_station} = isStation($source, $d{duration}, 1);

        if ($d{is_station}) {
            # A station row is named after the STATION, which is what the track title holds
            # for a stream (the menu title); the handler's title is the now-playing song.
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
            }
        }
    }

    return (undef, 'no title') unless defined $d{title} && length $d{title};
    $d{album_key} = $d{is_station} ? "station:$url" : albumKey(\%d);
    return \%d;
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

# A stored ALBUM entry as playable tracks: the whole album when its library or service can
# rebuild it, otherwise the tracks that were played. $cb->(\@items).
sub resolveTracks {
    my ($client, $entry, $cb) = @_;
    my $ref = $entry->{ref} || {};

    if ($entry->{source} eq 'library' && $ref->{album_id}) {
        my $items = _libraryTracks($ref->{album_id});
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

1;
