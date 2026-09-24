#!/usr/bin/env perl
# Shared bootstrap for the t_*.pl regression tests: fakes just enough of the LMS (Slim::*)
# tree that the plugin's own modules load and run on a machine with no server installed.
# Modelled on Listen Later's tools/t_stubs.pl.
#
# The stubs are deliberately DUMB. Anything a test depends on (a pref, a track count, a
# handler's metadata) is set IN that test, visibly, so nothing passes because of behaviour
# hidden in here. Registering via %INC means no files on disk and no @INC juggling.
#
# Usage:   require "$FindBin::Bin/t_stubs.pl";   (before loading any Plugins:: module)
use strict;
use warnings;

{
    package Slim::Utils::Log;
    require Exporter; our @ISA = ('Exporter'); our @EXPORT = ('logger');
    our @LINES;
    sub addLogCategory { return bless {}, 'Slim::Utils::Log::Obj' }
    sub logger         { return bless {}, 'Slim::Utils::Log::Obj' }
    sub clear          { @LINES = () }
    package Slim::Utils::Log::Obj;
    sub warn  { push @Slim::Utils::Log::LINES, "WARN $_[1]" }
    sub error { push @Slim::Utils::Log::LINES, "ERROR $_[1]" }
    sub info  { push @Slim::Utils::Log::LINES, "INFO $_[1]" }
    sub debug {} sub is_debug {0} sub is_info {0}
    sub AUTOLOAD {} sub DESTROY {}
    $INC{'Slim/Utils/Log.pm'} = __FILE__;
}

# Prefs. Namespaces are separate stores, and — like the real Prefs::Base::set — a name
# starting with '_' is silently DISCARDED.
{
    package Slim::Utils::Prefs;
    require Exporter; our @ISA = ('Exporter'); our @EXPORT = ('preferences');
    our %NAMESPACES;
    sub preferences { return bless { ns => $_[0] }, 'Slim::Utils::Prefs::Obj' }
    sub set_test_pref { my ($ns, $k, $v) = @_; $NAMESPACES{$ns}{$k} = $v }
    package Slim::Utils::Prefs::Obj;
    sub _s   { return $Slim::Utils::Prefs::NAMESPACES{ $_[0]->{ns} } ||= {} }
    sub get  { return $_[0]->_s->{ $_[1] } }
    sub set  { return if $_[1] =~ /^_/; $_[0]->_s->{ $_[1] } = $_[2] }
    sub init { my ($self, $h) = @_; my $s = $self->_s; $s->{$_} //= $h->{$_} for keys %$h }
    sub AUTOLOAD {} sub DESTROY {}
    $INC{'Slim/Utils/Prefs.pm'} = __FILE__;
}

# cstring() returns the token, so a test asserting on a label sees 'PLUGIN_LH_RECENT'.
# A token holding a %s maps to a format here, so sprintf still says something.
{
    package Slim::Utils::Strings;
    require Exporter; our @ISA = ('Exporter'); our @EXPORT_OK = ('cstring', 'string');
    my %FMT = (PLUGIN_LH_TRUNCATED => 'latest %s', PLUGIN_LH_SORTED_BY => 'Sorted by %s',
                PLUGIN_LH_PLAYED_IN => 'Played in %s', PLUGIN_LH_ALL_OF => 'All of %s',
                # LMS's real values: RELEASE_TYPE_ALBUMS is empty, ALBUMS carries the name.
                RELEASE_TYPE_ALBUMS => '', ALBUMS => 'Albums', RELEASE_TYPE_EPS => 'EPs',
                RELEASE_TYPE_SINGLES => 'Singles', RELEASE_TYPE_COMPILATIONS => 'Compilations');
    sub cstring { return $FMT{ $_[1] // '' } // $_[1] // '' }
    sub string  { return $_[0] // '' }
    # The release-type names LMS has (RELEASE_TYPE_ALBUMS exists but is EMPTY, as on a real server).
    our %EXISTS = map { $_ => 1 } qw(RELEASE_TYPE_ALBUMS ALBUMS RELEASE_TYPE_EPS RELEASE_TYPE_SINGLES RELEASE_TYPE_COMPILATIONS);
    sub stringExists { return $EXISTS{ $_[0] // '' } ? 1 : 0 }
    $INC{'Slim/Utils/Strings.pm'} = __FILE__;
}

# A controllable clock: TestClock::advance(60). Installed BEFORE any plugin module is
# compiled, because a CORE::GLOBAL override only binds in code compiled after it.
{
    package TestClock;
    our $OFFSET = 0;
    sub advance { $OFFSET += $_[0] }
    sub reset   { $OFFSET = 0 }
    sub now     { CORE::time() + ($OFFSET || 0) }   # the clock the PLUGIN sees; a test file compiled before this override reads the real one
    $INC{'TestClock.pm'} = __FILE__;
}
BEGIN { *CORE::GLOBAL::time = sub () { CORE::time() + ($TestClock::OFFSET || 0) } }

# Timers record what was armed; a test fires one with fire_timer().
{
    package Slim::Utils::Timers;
    our @ARMED;
    sub setTimer   { my ($obj, $when, $cb, @a) = @_; push @ARMED, { obj => $obj, when => $when, cb => $cb, args => \@a }; 1 }
    sub killTimers { my ($obj, $cb) = @_; @ARMED = grep { !($_->{cb} == $cb && (!defined $obj || $_->{obj} == $obj)) } @ARMED }
    sub clear      { @ARMED = () }
    # Fire (and disarm) the earliest timer for $obj, advancing the clock to its time.
    sub fire_timer {
        my ($obj) = @_;
        my ($t) = sort { $a->{when} <=> $b->{when} } grep { !defined $obj || $_->{obj} == $obj } @ARMED
            or return 0;
        @ARMED = grep { $_ != $t } @ARMED;
        my $delta = $t->{when} - time();
        TestClock::advance($delta) if $delta > 0;
        $t->{cb}->($t->{obj}, @{ $t->{args} });
        return 1;
    }
    $INC{'Slim/Utils/Timers.pm'} = __FILE__;
}

{
    package Slim::Utils::PluginManager;
    sub isEnabled { 0 }
    sub AUTOLOAD {} sub DESTROY {}
    $INC{'Slim/Utils/PluginManager.pm'} = __FILE__;
}

# Request: subscribe records the callback so a test can drive it; addDispatch records too.
{
    package Slim::Control::Request;
    our (@SUBSCRIBED, %DISPATCH);
    sub subscribe   { push @SUBSCRIBED, [ @_ ] }
    sub unsubscribe { my ($cb) = @_; @SUBSCRIBED = grep { $_->[0] != $cb } @SUBSCRIBED }
    sub addDispatch { my ($cmd, $spec) = @_; $DISPATCH{ join ' ', @$cmd } = $spec }
    $INC{'Slim/Control/Request.pm'} = __FILE__;
}

# Protocol handlers: a test maps a url scheme to the metadata getMetadataFor answers.
{
    package Slim::Player::ProtocolHandlers;
    our %META;   # scheme => { url => metadata hash } or scheme => metadata hash
    sub handlerForURL {
        my (undef, $url) = @_;
        my ($scheme) = ($url // '') =~ m{^(\w+):} or return undef;
        return exists $META{$scheme} ? 'TestHandler' : undef;
    }
    package TestHandler;
    sub getMetadataFor {
        my (undef, $client, $url) = @_;
        my ($scheme) = $url =~ m{^(\w+):};
        my $m = $Slim::Player::ProtocolHandlers::META{$scheme};
        return (ref $m eq 'HASH' && exists $m->{$url}) ? $m->{$url} : $m;
    }
    $INC{'Slim/Player/ProtocolHandlers.pm'} = __FILE__;
}

{
    package Slim::Plugin::OPMLBased;
    sub initPlugin {} sub AUTOLOAD {} sub DESTROY {}
    $INC{'Slim/Plugin/OPMLBased.pm'} = __FILE__;
}
{
    package Slim::Web::Settings;
    sub new {} sub name {} sub page {} sub prefs {}
    # Mirrors the real base class on the one point that matters: a save walks prefs() and
    # sets every one from $params->{pref_<name>}, INCLUDING an absent (undef) checkbox.
    sub handler {
        my ($class, $client, $p) = @_;
        return unless $p && $p->{saveSettings};
        my ($prefsObj, @names) = $class->prefs;
        $prefsObj->set($_, $p->{"pref_$_"}) for @names;
        return;
    }
    sub AUTOLOAD {} sub DESTROY {}
    $INC{'Slim/Web/Settings.pm'} = __FILE__;
}
{
    package Plugins::MaterialSkin::HomeExtraBase;
    our @INIT;
    sub initPlugin { my ($class, %a) = @_; push @INIT, { class => $class, %a } }
    sub AUTOLOAD {} sub DESTROY {}
    $INC{'Plugins/MaterialSkin/HomeExtraBase.pm'} = __FILE__;
}

# Slim::Schema: a test registers library albums with add_test_album; search('Track',
# {'album.id' => $id}) then counts / iterates exactly those tracks, and nothing else.
# An album exists while it has tracks or meta. ALBUM_META may also carry musicbrainz_id, title,
# artist (its contributor name, for the db: url) and artwork; TRACK_MBID maps a track url to its
# recording MBID. objectForUrl answers a registered track url, or a db:album url by title + artist
# (first match, as LMS's _objForDbUrl does). $SCANNING stands in for Import->stillScanning.
{
    package Slim::Schema;
    our %ALBUM_TRACKS;   # album id => [ [title, url], … ]
    our %ALBUM_META;     # album id => { release_type, compilation, musicbrainz_id, title, artist, artwork }
    our %TRACK_MBID;     # track url => recording MBID
    sub add_test_album { my ($id, @tracks) = @_; $ALBUM_TRACKS{$id} = \@tracks }
    sub _album {
        my ($id) = @_;
        return undef unless defined $id && ($ALBUM_META{$id} || $ALBUM_TRACKS{$id});
        return bless { %{ $ALBUM_META{$id} || {} }, id => $id }, 'Slim::Schema::FakeAlbum';
    }
    sub find {
        my (undef, $kind, $id) = @_;
        return undef unless $kind eq 'Album';
        return _album($id);
    }
    sub _track {
        my ($url) = @_;
        for my $id (sort { $a <=> $b } keys %ALBUM_TRACKS) {
            for my $t (@{ $ALBUM_TRACKS{$id} }) {
                return bless { title => $t->[0], url => $t->[1], album_id => $id }, 'Slim::Schema::FakeTrack'
                    if $t->[1] eq $url;
            }
        }
        return undef;
    }
    sub objectForUrl {
        my (undef, $args) = @_;
        my $url = ref $args eq 'HASH' ? $args->{url} : $args;
        return undef unless defined $url;
        if ($url =~ /^db:album\.title=([^&]*)&contributor\.name=(.*)$/) {
            require URI::Escape;
            my ($t, $n) = map { my $v = URI::Escape::uri_unescape($_); utf8::decode($v); $v } ($1, $2);
            for my $id (sort { $a <=> $b } keys %ALBUM_META) {
                my $m = $ALBUM_META{$id};
                return _album($id) if ($m->{title} // '') eq $t && ($m->{artist} // '') eq $n;
            }
            return undef;
        }
        return _track($url);
    }
    package Slim::Schema::FakeAlbum;
    sub release_type { $_[0]->{release_type} } sub compilation { $_[0]->{compilation} }
    sub id { $_[0]->{id} } sub musicbrainz_id { $_[0]->{musicbrainz_id} } sub artwork { $_[0]->{artwork} }
    sub url {
        my $s = shift;
        return undef unless defined $s->{title} && defined $s->{artist};
        require URI::Escape;
        return sprintf('db:album.title=%s&contributor.name=%s',
            URI::Escape::uri_escape_utf8($s->{title}), URI::Escape::uri_escape_utf8($s->{artist}));
    }
    package Slim::Schema;
    sub search {
        my (undef, $kind, $cond) = @_;
        my @rows;
        if (ref $cond eq 'HASH' && exists $cond->{musicbrainz_id}) {
            my $m = $cond->{musicbrainz_id};
            if ($kind eq 'Album') {
                @rows = map { _album($_) }
                        grep { ($ALBUM_META{$_}{musicbrainz_id} // '') eq $m } sort { $a <=> $b } keys %ALBUM_META;
            }
            else {
                @rows = map { _track($_) } grep { $TRACK_MBID{$_} eq $m } sort keys %TRACK_MBID;
            }
            return bless { rows => \@rows }, 'Slim::Schema::Rs';
        }
        my $id = ref $cond eq 'HASH' ? $cond->{'album.id'} : undef;
        my @t = @{ $ALBUM_TRACKS{ $id // '' } || [] };
        return bless { t => \@t }, 'Slim::Schema::Rs';
    }
    package Slim::Schema::Rs;
    sub count { return scalar @{ $_[0]->{t} } }
    sub next  { my $r = shift @{ $_[0]->{t} } or return undef; return bless { title => $r->[0], url => $r->[1] }, 'Slim::Schema::FakeTrack' }
    sub all   { return grep { defined } @{ $_[0]->{rows} || [] } }
    package Slim::Schema::FakeTrack;
    sub title { $_[0]->{title} } sub url { $_[0]->{url} }
    sub album { Slim::Schema::_album($_[0]->{album_id}) }
    sub musicbrainz_id { $Slim::Schema::TRACK_MBID{ $_[0]->{url} // '' } }
    $INC{'Slim/Schema.pm'} = __FILE__;
}
{
    package Slim::Music::Import;
    our $SCANNING = 0;
    sub stillScanning { $SCANNING }
    $INC{'Slim/Music/Import.pm'} = __FILE__;
}

{
    package main;
    eval 'use constant WEBUI => 1;' unless defined &main::WEBUI;
}

# Load the plugin's OWN modules by path: their package names match the INSTALLED layout
# (Plugins/ListeningHistory/…), which a checkout does not have. Registered in %INC under
# the name they call themselves, so a sibling's `use` of them is a no-op.
sub main::lh_require {
    require File::Basename;
    require Cwd;
    my $dir = File::Basename::dirname(Cwd::abs_path(__FILE__)) . '/../ListeningHistory';
    for my $name (@_) {
        my $key = "Plugins/ListeningHistory/$name.pm";
        next if $INC{$key};
        my $path = "$dir/$name.pm";
        die "no such module: $path\n" unless -f $path;
        $INC{$key} = $path;
        require $path;
    }
    return 1;
}

# A temp cachedir, so a suite's DB never lands anywhere real.
sub main::lh_tempdb {
    require File::Temp;
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    Slim::Utils::Prefs::set_test_pref('server', 'cachedir', $dir);
    Plugins::ListeningHistory::DB::_reset() if defined &Plugins::ListeningHistory::DB::_reset;
    return $dir;
}

# Tiny assertion kit shared by every suite.
our ($PASS, $FAIL) = (0, 0);
sub main::is {
    my ($desc, $got, $want) = @_;
    my $ok = (defined $got && defined $want) ? $got eq $want : !defined $got && !defined $want;
    if ($ok) { $PASS++; print "ok   $desc\n" if $ENV{V} }
    else     { $FAIL++; printf "FAIL %s\n     got:  %s\n     want: %s\n", $desc, $got // 'undef', $want // 'undef' }
    return $ok;
}
sub main::ok { main::is($_[0], ($_[1] ? 1 : 0), 1) }
sub main::done {
    printf "%d passed, %d failed\n", $PASS, $FAIL;
    exit($FAIL ? 1 : 0);
}

1;
