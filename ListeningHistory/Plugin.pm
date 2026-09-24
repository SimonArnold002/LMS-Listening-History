package Plugins::ListeningHistory::Plugin;

# Listening History — a play history across every player, for library and streaming music.
#
#   Tracker.pm     watches playback and records what was listened to
#   DB.pm          the plugin's own SQLite store (entries + the plays behind them)
#   Sources.pm     describes a playing track; rebuilds a stored album for playback
#   Browse.pm      the app menu and the history rows
#   HomeExtras.pm  the Material home shelf of the latest 50 entries
#   Settings.pm    the settings page

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Timers;

use Plugins::ListeningHistory::DB;
use Plugins::ListeningHistory::Sources;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.listeninghistory',
    defaultLevel => 'WARN',
    description  => 'PLUGIN_LH',
});

my $prefs = preferences('plugin.listeninghistory');

# NB a pref name must never start with '_': Slim::Utils::Prefs::Base::set silently drops it.
$prefs->init({
    played_threshold => 90,   # % of a track that must play before it is recorded
    session_gap_min  => 30,   # minutes between two tracks that still group into one album
    retention_days   => 0,    # remove entries older than this; 0 keeps everything
    sort             => 'date', # entry-list order: date | artist | album (the view's sort row)
});

sub initPlugin {
    my $class = shift;

    if (main::WEBUI) {
        require Plugins::ListeningHistory::Settings;
        Plugins::ListeningHistory::Settings->new();
    }

    require Plugins::ListeningHistory::Browse;

    # Open / migrate the store up front, so a failure shows at startup.
    Plugins::ListeningHistory::DB::dbh();

    # [needClient, isQuery, hasTags, func]
    Slim::Control::Request::addDispatch(['listeninghistory', 'contextmenu'], [0, 1, 1, \&_contextMenuQuery]);
    Slim::Control::Request::addDispatch(['listeninghistory', 'remove'],      [0, 0, 1, \&_removeCommand]);

    require Plugins::ListeningHistory::Tracker;
    Plugins::ListeningHistory::Tracker->init();

    $class->SUPER::initPlugin(
        tag    => 'listeninghistory',
        feed   => \&Plugins::ListeningHistory::Browse::topLevel,
        is_app => 1,
        menu   => 'radios',
        weight => 10,
    );
    return;
}

sub postinitPlugin {
    if ( Slim::Utils::PluginManager->isEnabled('Plugins::MaterialSkin::Plugin')
      && Plugins::MaterialSkin::Plugin->can('registerHomeExtra') ) {
        eval {
            require Plugins::ListeningHistory::HomeExtras;
            Plugins::ListeningHistory::HomeExtras->initPlugin();
            1;
        } or $log->error("Listening History: failed to register the Material home shelf: $@");
    }

    # Retention: first pass shortly after startup, then daily.
    Slim::Utils::Timers::killTimers(undef, \&_purgeTick);
    Slim::Utils::Timers::setTimer(undef, time() + 60, \&_purgeTick);

    # Library check (Sources::sweepTick): after every rescan, and once after startup in case a
    # scan finished while the plugin was not running.
    Slim::Control::Request::subscribe(\&_onRescanDone, [['rescan'], ['done']]);
    Plugins::ListeningHistory::Sources::startSweep(120);
    return;
}

sub _onRescanDone {
    Plugins::ListeningHistory::Sources::startSweep(10);
    return;
}

sub _purgeTick {
    my $days = $prefs->get('retention_days');
    my $n = eval { Plugins::ListeningHistory::DB::purge($days) } || 0;
    $log->warn("Listening History: removed $n entr" . ($n == 1 ? 'y' : 'ies')
        . " older than $days days") if $n;
    Slim::Utils::Timers::setTimer(undef, time() + 86400, \&_purgeTick);
    return;
}

# The row's "…" → More menu. 'parent' on a More-menu action makes Material refresh the list
# in place rather than jumping back home (Listen Later's pattern).
sub _contextMenuQuery {
    my $request = shift;
    my $client  = $request->client;
    my $id      = $request->getParam('id');

    $request->addResultLoop('item_loop', 0, 'text', cstring($client, 'PLUGIN_LH_REMOVE'));
    $request->addResultLoop('item_loop', 0, 'actions', {
        do => { player => 0, cmd => ['listeninghistory', 'remove'], params => { id => $id } },
    });
    $request->addResultLoop('item_loop', 0, 'nextWindow', 'parent');
    $request->addResult('offset', 0);
    $request->addResult('count', 1);
    $request->setStatusDone;
    return;
}

sub _removeCommand {
    my $request = shift;
    my $id = $request->getParam('id');
    Plugins::ListeningHistory::DB::remove($id) if defined $id && $id =~ /^\d+$/;
    $request->setStatusDone;
    return;
}

sub shutdownPlugin {
    eval { Plugins::ListeningHistory::Tracker->shutdown; 1 }
        or $log->error("Listening History: tracker shutdown failed: $@");
    Slim::Control::Request::unsubscribe(\&_onRescanDone);
    Plugins::ListeningHistory::Sources::stopSweep();
    return;
}

sub getDisplayName { 'PLUGIN_LH' }

sub playerMenu { undef }

1;
