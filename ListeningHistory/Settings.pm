package Plugins::ListeningHistory::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.listeninghistory');

sub name { return Slim::Web::HTTP::CSRF->protectName('PLUGIN_LH') }

sub page { return Slim::Web::HTTP::CSRF->protectURI('plugins/ListeningHistory/settings.html') }

sub prefs { return ($prefs, qw(played_threshold session_gap_min record_radio retention_days)) }

sub handler {
    my ($class, $client, $params, $callback, @args) = @_;

    if ($params->{saveSettings}) {
        # Clean the raw form values IN PLACE: SUPER::handler saves every pref in prefs()
        # straight from $params->{pref_*} after this runs.
        $params->{pref_played_threshold} = _clamp($params->{pref_played_threshold}, 90, 10, 100);
        $params->{pref_session_gap_min}  = _clamp($params->{pref_session_gap_min},  30, 1, 1440);
        $params->{pref_retention_days}   = _clamp($params->{pref_retention_days},   0,  0, 36500);
        # An unticked checkbox posts NOTHING, and the base class would store that undef —
        # which init() then re-seeds to the default at the next start. Materialise the 0.
        $params->{pref_record_radio} = $params->{pref_record_radio} ? 1 : 0;
    }

    return $class->SUPER::handler($client, $params);
}

sub _clamp {
    my ($v, $default, $min, $max) = @_;
    $v = $default unless defined $v && $v =~ /^\d+$/;
    $v = $min if $v < $min;
    $v = $max if $v > $max;
    return $v + 0;
}

1;
