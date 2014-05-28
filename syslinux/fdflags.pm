package syslinux::fdflags;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/ndelayon ndelayoff isfdflagset/;

use Fcntl qw/F_GETFL F_SETFL O_NONBLOCK/;

sub ndelayon
{
    fcntl($_[0], F_SETFL, fcntl($_[0], F_GETFL, 0) | O_NONBLOCK);
}
sub ndelayoff
{
    fcntl($_[0], F_SETFL, fcntl($_[0], F_GETFL, 0) & ~O_NONBLOCK);
}

sub isfdflagset
{
    fcntl($_[0], F_GETFL, 0) & $_[1];
}

1;
