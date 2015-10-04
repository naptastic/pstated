#!/usr/bin/perl
package PstateD;

use v5.010;
use strict;
use warnings;

use Path::Tiny  ();
use Time::HiRes ();

our $proc_stat   = '/proc/stat';
our $turbo_pct   = '/sys/devices/system/cpu/intel_pstate/turbo_pct';
our $turbo_cap   = '/sys/devices/system/cpu/intel_pstate/no_turbo';
our $min_file    = '/sys/devices/system/cpu/intel_pstate/min_perf_pct';
our $max_file    = '/sys/devices/system/cpu/intel_pstate/max_perf_pct';
our $delay_usecs = 100_000;

script(@ARGV) unless caller();

sub script {
    my @args = @_;

    my $self = PstateD->new();

    while (1) {
        $self->get_score();
        $self->enact_policy();
        Time::HiRes::usleep($delay_usecs);
    }
}

sub new {
    my ( $class, %args ) = @_;

    my $self = bless {}, $class;

    $self->{'turbo'} = safe_slurp($turbo_pct);
    $self->{'min'}   = safe_slurp($min_file);

    return $self;
}

sub enact_policy {
    my ($self) = @_;

    if ( $self->{idle} < 10 ) {
        $self->{target} = 100;
        $self->{turbo_wanted} += 1;
        $self->{turbo_wanted} = 100 if $self->{turbo_wanted} > 100;
    }
    else {
        $self->{target} -= 2;
        $self->{turbo_wanted} = 0;
    }

    $self->{target} = $self->{min} if $self->{target} < $self->{min};

    # The turbo file uses negative logic. '1' means that turbo mode is disabled.
    if   ( $self->{turbo_wanted} > 10 ) { safe_write( $turbo_cap, '0' ); }
    else                                { safe_write( $turbo_cap, '1' ); }

    safe_write( $max_file, $self->{target} );
}

# The whole point of this method is the wantarray magic.
# When I try to remove it, shit breaks. I don't know why.
# Pull requests exist. Use them. ;) <3
sub safe_slurp {
    my ($filename) = @_;

    my $content = Path::Tiny->new($filename)->slurp();

    if (wantarray) {
        return split /\n/, $content;
    }
    else {
        chomp $content;
        return $content;
    }

    return 1;
}

sub safe_write {
    my ( $filename, $value ) = @_;

    open( my $fh, '>', $filename ) or die "Couldn't open $filename for writing: $!";
    print {$fh} $value;
    close $fh;

    return 1;
}

sub get_score {
    my ($self) = @_;

    my $idle_total = (split /\s+/, ( split /\n/, Path::Tiny->new($proc_stat)->slurp() )[0] )[4];

    $self->{idle}      = $idle_total - $self->{last_idle};
    $self->{last_idle} = $idle_total;

    return 1;
}

1;
