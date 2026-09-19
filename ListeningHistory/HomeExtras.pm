package Plugins::ListeningHistory::HomeExtras;

# Material Skin home-page shelf: the latest entries (Browse::homeShelf). One HomeExtraBase
# subclass, registered from Plugin::postinitPlugin only when Material can take it.

use strict;
use base qw(Plugins::MaterialSkin::HomeExtraBase);

use Plugins::ListeningHistory::Browse;

sub initPlugin {
    my ($class) = @_;
    $class->SUPER::initPlugin(
        feed  => \&feed,
        tag   => 'LHHome',
        extra => {
            title       => 'PLUGIN_LH',
            icon        => Plugins::ListeningHistory::Browse::ICON(),
            needsPlayer => 0,
        },
    );
}

sub feed {
    my ($client, $cb, $args) = @_;
    Plugins::ListeningHistory::Browse::homeShelf($client, $cb, $args);
}

1;
