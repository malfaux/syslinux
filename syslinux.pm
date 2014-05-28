package syslinux;
use v5.18;
use Carp qw/croak/;

BEGIN {
    use POSIX;
    die unless $^O eq 'linux';                                                                                                                                                                 
    die unless (POSIX::uname)[4] eq 'x86_64';
}

sub import 
{
    my $package = caller;
    my $self = shift;
    eval "package $package; use syslinux::$_;" foreach (@_);
    croak $@ if $@;
    return;
}
1;
