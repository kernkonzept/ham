package Hammer::Process_queue::Process;

use strict;
use warnings;
use Hammer::Stream;

sub new
{
  shift;
  my $cmd = shift;
  my %opts = @_;
  my $self = {};

  $self->{command} = $cmd;
  $self->{done} = 0;

  my @args = ();
  if (defined $opts{args}) {
    @args = ($opts{args});
    @args = @{$opts{args}} if ref $opts{args} eq 'ARRAY';
  }

  my $finish_cb = $opts{finish};

  my $finish = sub {
    my $what = shift;
    delete $self->{$what};
    if (++$self->{done} == 2) {
      $finish_cb->($self, @args) if defined $finish_cb;
      $cmd->close;
      delete $self->{command};
    }
  };

  my $out_cb = $opts{out};
  my $err_cb = $opts{err};
  %opts = ();

  $self->{stdout} = Hammer::Stream->new($cmd->stdout, sub {
      my ($finished, $data) = @_;
      $out_cb->($self, $data, @args) if $out_cb;
      $finish->('stdout') if $finished;
    });
  $self->{stderr} = Hammer::Stream->new($cmd->stderr, sub {
      my ($finished, $data) = @_;
      $err_cb->($self, $data, @args) if $err_cb;
      $finish->('stderr') if $finished;
    });

  return bless $self, __PACKAGE__;
}

sub stdout { $_[0]->{stdout} }
sub stderr { $_[0]->{stderr} }
sub done   { $_[0]->{done} == 2 }

1;
