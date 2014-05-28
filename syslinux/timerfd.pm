package syslinux::timerfd;
require Exporter;
use v5.18;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
    CLOCK_REALTIME
    CLOCK_MONOTONIC
    timerfd_create
    timerfd_settime
    timerfd_gettime
    timerfd_read
    /;

use constant {
    CLOCK_REALTIME      => 0,
    CLOCK_MONOTONIC     => 1,
    TFD_NONBLOCK        => 0400,
    TFD_CLOEXEC         => 02000000,
    SYS_timerfd_create  => 283,
    SYS_timerfd_settime => 286,
    SYS_timerfd_gettime => 287,
};


sub FLAGDEFAULTS { TFD_CLOEXEC };
sub CLOCKTYPE { CLOCK_MONOTONIC };

sub timerfd_create 
{
    my $clocktype = $_[0] // CLOCKTYPE;
    my $flags = $_[1] // FLAGDEFAULTS;
    my $fd = syscall(SYS_timerfd_create, $clocktype, $flags);
    die $! unless $fd > 0;
    open my $fh = undef, "<&=$fd" or die $!;
    return $fh;
}
our $timerfd_buflen = length pack('l!L!l!L!');

sub timerfd_settime
{
    #@_ = ($repeat, $start);
    #both are with valid params, see perldoc -f syscall on pointers and ints
    #syscall(SYS_timerfd_settime, $_[0], 0, unpack("L!", pack("P", pack('l!L!l!L!', @_[1..4]))), pack('P', undef));
    syscall(SYS_timerfd_settime, fileno($_[0]), 0, pack('l!L!l!L!', @_[1..4]), pack('P', undef));
}

sub timerfd_gettime
{
    #root@skips:~/dev# perl -E 'say unpack("L!", pack("P", pack("l!L!l!L!", 0, 0, 0, 0)))'
    my $buf = "\x00" x $timerfd_buflen;
    syscall(SYS_timerfd_gettime, fileno($_[0]), $buf);
    unpack('l!L!l!L!', $buf);
}
sub timerfd_read
{
    #open(FH, "<&=$_[0]") or return undef;
    my $buf = "\x00" x 8;
    return undef unless sysread($_[0], $buf, 8) + 0 == 8;
    return unpack 'Q', $buf;
}

{
    last if defined((caller)[0]);
    my $foo = timerfd_create();
    say "timer at $foo";
    timerfd_settime($foo, 1,0,1,0);
    use syslinux::epoll;
    my $epfd = syslinux::epoll->new;
    my $count = 3;
    $epfd->add($foo, EPOLLIN, sub {
        my $data = timerfd_read($foo);
        say "timer fired " . $data . " times at " . time;
        $count--;
        if ($count == 0) {
            close $foo;
            $epfd->close();
        }
    });
    $epfd->wait;
    say "DONE";
}
1;



