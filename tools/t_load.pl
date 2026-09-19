#!/usr/bin/env perl
# Every shipped module compiles AND loads, and every Plugins::ListeningHistory::X::y() call
# names a sub that exists — `perl -c` passes on a call to a sub that does not.
use strict;
use warnings;
use FindBin;
require "$FindBin::Bin/t_stubs.pl";

my @mods = qw(DB Sources Tracker Browse HomeExtras Settings Plugin);
for my $m (@mods) {
    ok("loads: $m", eval { main::lh_require($m); 1 }) or print "     $@\n";
}

my $dir = "$FindBin::Bin/../ListeningHistory";
no strict 'refs';
for my $m (@mods) {
    open my $fh, '<', "$dir/$m.pm" or die $!;
    my $src = do { local $/; <$fh> };
    my %seen;
    while ($src =~ /\bPlugins::ListeningHistory::(\w+)::(\w+)\s*(?:\(|->)/g) {
        my ($pkg, $sub) = ($1, $2);
        next if $seen{"$pkg\::$sub"}++;
        ok("defined: Plugins::ListeningHistory::$pkg\::$sub (called from $m)",
           defined &{"Plugins::ListeningHistory::$pkg\::$sub"} || $sub =~ /^[A-Z_]+$/);
    }
}

main::done();
