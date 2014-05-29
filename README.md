```perl
use syslinux qw/epoll signalfd timerfd/;

my $ep = syslinux::epoll->new();
my ($sigfd, $oldmask) = signalfd(-1, SFD_CLOEXEC|SFD_NONBLOCK, keys %sighandlers);

$ep->add($sigfd, EPOLLIN, sub {
    my($ev, $fh) = @_;
    die $! unless $ev == EPOLLIN and fileno($fh) == fileno($sigfd);
    my @sigs = sigread($fh);
    foreach my $sig (@sigs) {
        say "SIGNAL_CODE: " . $sig->{signo};
        say "SIGNAL_NAME: " . $SIGv2n{$sig->{signo}};
    }
});



```

