package syslinux::signalfd;

use v5.18;

require Exporter;
use syslinux qw/fdflags epoll/;
use Errno qw/EIO :POSIX/;
use List::MoreUtils qw/zip/;

our @ISA = qw/Exporter/;
our @EXPORT = qw/
    sigaddmask 
    sigdelmask
    signewmask
    sigprocmask
    getprocmask
    setprocmask
    signalfd
    %SIGn2v
    %SIGv2n
    SFD_CLOEXEC
    SFD_NONBLOCK
    sigread
    /;

use Config;
use POSIX;
use constant {
    SFD_NONBLOCK        => 00004000,
    SFD_CLOEXEC         => 02000000,
    SYS_signalfd        => 282,
    SYS_rt_sigprocmask  => 14,
    MASKLEN             => 1024 / (8 * $Config{longsize}),
    SIGINFOLEN          => 128,
    SIGINFOFMT          => 'I!i!i!I!I!i!I!I!I!I!i!i!L!L!L!L!a*',
    _NSIG               => 64,
};

our %SIGn2v = ();
our %SIGv2n = ();

{
    no strict 'refs';
    my @signames__ = map { 
        s/^SIG//; $_; 
    } grep { 
        /^SIG[A-Z]/ && $_ ne 'SIGRT'
    } keys %POSIX::;
    my @sigvalues_ = map { &{"POSIX::SIG".$_} } (@signames__);
    %SIGn2v = zip @signames__, @sigvalues_;
    %SIGv2n = zip @sigvalues_, @signames__;
}

sub signewmask { pack 'L!*', map { 0 } (1..MASKLEN); }
sub sigsetmask
{
    my $bitval = shift;
    my $mask = shift;
    my @sigs;
    {
        no strict 'refs';
        @sigs = map { &{'POSIX::SIG'.$_} } (@_);
    }
    vec($mask, $_-1, 1) = $bitval foreach(@sigs);
    return $mask;
}
sub sigaddmask  {&sigsetmask(1, @_); }
sub sigdelmask { &sigsetmask(0, @_) }
sub sigORmask;

sub FLAGSDEFAULT { SFD_CLOEXEC }

sub sigprocmask 
{
    #($how, $newmask, $oldmask) = @_;
    syscall(SYS_rt_sigprocmask, @_, _NSIG/8);
    
}

sub getprocmask
{
    my $sigmask = signewmask();
    sigprocmask($_[0], undef, $sigmask);
    return $sigmask;
}
sub setprocmask
{
    my $how = shift;
    my $oldmask = signewmask();
    my $newmask = sigsetmask(1, signewmask(), @_);
    sigprocmask($how, $newmask, $oldmask);
    return $oldmask;
}
sub signalfd 
{
    my ($fd, $flags, @sigs) = @_;
    $flags = FLAGSDEFAULT unless defined $flags;
    my $sigmask = sigsetmask(1,signewmask(), @sigs);
    #my $oldmask = signewmask();
    #my $ret = syscall(SYS_rt_sigprocmask, &POSIX::SIG_BLOCK, undef, $oldmask, _NSIG/8);
    #die $! unless $ret == 0;
    #$sigmask = sigORmask($sigmask, $oldmask);
    my $oldmask = signewmask();
    my $ret = sigprocmask(&POSIX::SIG_BLOCK, $sigmask, $oldmask);
    return undef unless $ret == 0;
    my $sfd = syscall(SYS_signalfd, $fd, $sigmask, _NSIG/8, $flags);
    return undef unless $sfd > 0;
    open my $fh = undef, "<&=$sfd" or die $!;
    return ($fh, $oldmask);
}

my @__sitags = qw/signo errno code pid uid fd tid band overrun trapno status int ptr utime stime addr pad/;
use Fcntl qw/O_NONBLOCK/;

sub sigread
{
    #open(my $fh = undef, "<&=$_[0]") or die $!;
    my $fh = $_[0];
    my @sigs = ();
    my $buf = "\x00" x SIGINFOLEN;
    my $restoreflag = undef;
    unless(isfdflagset($fh, O_NONBLOCK)) {
        #say "O_NONBLOCK not set, setting it temporarly";
        ndelayon $fh;
        $restoreflag = 1;
    }
    while(1) {
        my $bytesread = sysread $fh, $buf, SIGINFOLEN;
        unless(defined($bytesread) and $bytesread > 0) {
            die $! unless $!{EWOULDBLOCK};
            #say "sigread: done reading: $!";
            last;
        }
        my @sivals = unpack SIGINFOFMT, $buf;
        my %siginfo = zip @__sitags, @sivals;
        push @sigs, \%siginfo;
    }
    if($restoreflag) {
        #say "setting back blocking mode on file descriptor...";
        ndelayoff($fh);
    }
    return @sigs;
}

#<<OO interface
sub new
{
    my $class = shift;
    my $flags = shift // 0;
    my $mask = sigaddmask(signewmask(), @_);
    my $self = {
        flags=>$flags,
        sigmask => $mask,
        sigmap => {},
        sifd => signalfd(-1, $mask, $flags),
    };
    bless $self, $class;
}
sub set
{
    my $self = shift;
    my $self->sigmask = sigaddmask(signewmask(), @_);
    signalfd($self->fileno(), $self->sigmask, $self->{flags});
}
sub fileno { $_[0]->{sifd} }

sub on_event
{
    die "weird event received" unless $_[1] == EPOLLIN;
    my @sigs = sigread($_[2]);
    die "die no signals" unless scalar @sigs > 0;
}

#>>OO interface

#main tests
{
    last if defined((caller)[0]);
    use syslinux::epoll;
    use Data::Dumper;
    my $epfd = syslinux::epoll->new;
    my $sifd = signalfd(-1, SFD_CLOEXEC, qw/HUP CHLD USR1 USR2 TERM/);
    say "signalfd at $sifd pid=$$";
    say "press Ctrl-C to quit";
    $epfd->add($sifd, EPOLLIN, sub {
        my($ev, $fh) = @_;
        my @sigs = sigread($fh);
        print Dumper(\@sigs);
    });
    $epfd->wait();
}

1;
