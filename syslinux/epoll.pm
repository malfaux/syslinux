package syslinux::epoll;
use v5.18;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/EVREAD EVWRITE/;
my $maxevents_ = 32;

use POSIX;
use Scalar::Util qw/openhandle looks_like_number/;

our @EXPORT = qw/
    epoll_create 
    epoll_ctl 
    epoll_wait 
    EPOLLIN 
    EPOLLOUT 
    EPOLLERR 
    EPOLLHUP 
    EPOLLONESHOT
    EPOLL_CTL_ADD
    EPOLL_CTL_MOD
    EPOLL_CTL_DEL
    EVREAD
    EVWRITE
/;

use constant {
    SYS_epoll_create    => 213,
    SYS_epoll_create1   => 291,
    SYS_epoll_ctl       => 233,
    SYS_epoll_wait      => 232,
    EPOLLIN             => 1,
    EPOLLOUT            => 4,
    EPOLLERR            => 8,
    EPOLLHUP            => 16,
    EPOLLONESHOT        => 1<<30,
    EPOLL_CTL_ADD       => 1,
    EPOLL_CTL_DEL       => 2,
    EPOLL_CTL_MOD       => 3,
    EVREAD              => 1,
    EVWRITE             => 4,
    EPOLL_CLOEXEC       => 02000000,
};
sub FLAGSDEFAULT { EPOLL_CLOEXEC }

sub epoll_ctl
{
    syscall(SYS_epoll_ctl, $_[0]+0, $_[1]+0, $_[2]+0, pack("LLL", $_[3], $_[2], 0));
}

our $evque_len = 0;
our $events;
sub epoll_wait
{
    my ($epfd, $maxevents, $timeout, $evout) = @_;
    if ($maxevents > $evque_len) {
        $evque_len = $maxevents;
        $events = "\0" x 12 x $evque_len;
    }
    my $numevents = syscall(SYS_epoll_wait, $epfd, $events, $evque_len, $timeout);
    for(0..$numevents-1) {
        @{$evout->[$_]}[1,0] = unpack("LL", substr($events, 12*$_, 8))
    }
    return $numevents;
}
sub epoll_create 
{
    return syscall(SYS_epoll_create1, $_[0] // FLAGSDEFAULT);
    #return syscall(SYS_epoll_create, ($_[0] // 1) + 0);
}

sub close
{
    POSIX::close($_[0]->{epfd});
}

sub new
{
    my $epfd = epoll_create;
    my $maxevents = $_[1] // $maxevents_;
    die "noepoll" if $epfd < 0;
    my @_e = map { [-1,-1] } (0..$maxevents);
    my $self = {
        epfd => $epfd,
        evt => {},
        events => \@_e,
        maxevents => $maxevents,
    };
    bless $self, $_[0];
}

sub add
{
    my ($self, $fh, $ev, $cb) = @_;
    my $fd = (defined(openhandle($fh)))?fileno($fh):$fh;
    return undef unless looks_like_number($fd);
    my $rc = epoll_ctl($self->{epfd}, EPOLL_CTL_ADD, $fd, $ev);
    die $! if $rc < 0;
    $self->{evt}->{$fd} = [ $cb, $fh ];
    1;
}

sub del
{
    #don't need this shit right now
    1;
}
use constant { CB => 0, FH => 1 };
sub wait
{
    my ($self, $timeout) = @_;
    while(1) {
        my $numevents = epoll_wait($self->{epfd}, $self->{maxevents}, $timeout // -1, $self->{events});
        return undef if $numevents < 0;
        last if $numevents == 0;
        my $ei = 0;
        while($ei < $numevents) {
            my $evi = $self->{events}->[$ei];
            #say "process event $evi->[1] on fd $evi->[0]";
            my $evmap = $self->{evt}->{$evi->[0]};
            $evmap->[CB]->($evi->[1], $evmap->[FH]);
            #$self->{evt}->{$evi->[0]}->[0]->($evi->[1], $self->{evt}->{$evi->[0]}->[1]);
            $ei++;
        }
    }
}

1;
