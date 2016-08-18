package Hammer::Process_queue;

use strict;
use warnings;

use Hammer::Stream::Process;
use Hammer::Process_queue::Process;


## create a new work queue
sub new
{
  shift;
  my %o = @_;
  $o{max} = 8 unless defined $o{max};
  return bless {
    finish   => $o{finish},
    max      => $o{max},
    queue    => [],
    running  => [],
    sp       => Hammer::Stream::Process->new,
  }, __PACKAGE__;
}


## test if the queue is fully loaded (max number of running processes)
sub full
{
  my $self = shift;
  return scalar(@{$self->{running}}) > $self->{max};
}

## queue new work
sub queue
{
  my ($self, $command, %opts) = @_;
  push @{$self->{queue}}, $command;
}

## run all the queued work
sub work
{
  my $self = shift;
  while (scalar(@{$self->{queue}})) {
    next if not $self->full and $self->_run_next;
    $self->{sp}->process;
  }

  while ($self->{sp}->process) {}
}

## private: update the progress indicator
sub _update_progress
{
  my $self = shift;
  my $txt = '';
  foreach my $r (@{$self->{running}}) {
    $txt .= '['.$r->{err_msg}.']' if defined $r->{err_msg};
  }

  print STDERR "\r$txt\e[K" if $txt ne '';
}

## private functions follow ...
## private: run the next job
sub _run_next
{
  my $self = shift;
  my $next = shift @{$self->{queue}};
  return 0 unless defined $next;

  my ($cmd, %o) = $next->();

  sub parse_stream
  {
    my ($what, $proc, $data, $self, $opts) = @_;
    my $r = (grep { $_->{proc} == $proc } @{$self->{running}})[0];
    my @args = ($opts->{args});
    @args = @{$opts->{args}} if defined $opts->{args} and ref $opts->{args} eq 'ARRAY';
    my $info = $opts->{$what}->($data, @args) if defined $opts->{$what};
    $r->{$what.'_msg'} = $info if defined $info;
    $self->_update_progress if defined $info;
  }

  my %popts = (
    args   => [ $self, { %o } ],
    finish => sub {
      my ($proc, $self, $opts) = @_;
      $self->{running} = [ grep { $_->{proc} != $proc } @{$self->{running}} ];
      my @args = ($opts->{args});
      @args = @{$opts->{args}} if defined $opts->{args} and ref $opts->{args} eq 'ARRAY';
      my $info = $opts->{finish}->($proc, @args) if defined $opts->{finish};
      if (defined $info) {
        print STDERR "\r$info\e[K\n";
        $self->_update_progress;
      }
    },

    err => sub { parse_stream('err', @_); },
    out => sub { parse_stream('out', @_); },
  );
  my $e = Hammer::Process_queue::Process->new($cmd, %popts);
  push @{$self->{running}}, { proc => $e };
  $self->{sp}->add($e->stdout, $e->stderr);
  return 1;
}

1;
