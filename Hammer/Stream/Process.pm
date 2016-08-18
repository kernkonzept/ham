package Hammer::Stream::Process;

use strict;
use warnings;

## create a new stream processor
sub new
{
  my $s = { streams => [] };
  return bless $s, __PACKAGE__;
}

## add new stream to the processor
sub add
{
  my $self = shift;
  foreach my $s (@_) {
    push @{$self->{streams}}, $s unless $s->{done};
  }
}

## delete a stream from the processor
sub del
{
  my ($self, $s) = @_;
  @{$self->{streams}} = grep { $_ != $s } @{$self->{streams}};
}

## delete all closed stream from the processor
sub gc
{
  my ($self) = @_;
  @{$self->{streams}} = grep { not $_->{done} } @{$self->{streams}};
}

## are there any streams left ?
sub done
{
  my ($self) = @_;
  return not scalar(@{$self->{streams}});
}

## do stream processing
sub process
{
  my ($self) = @_;

  return undef if $self->done;

  while (my @handles = map { $_->{fh} } @{$self->{streams}}) {
    my @ready = IO::Select->new(@handles)->can_read;
    foreach my $h (@ready) {
      my ($s) = grep { $_->{fh} == $h } @{$self->{streams}};
      if (not $s->process) {
        # stream closed ...
        $self->gc;
        return $s;
      }
    }
  }
}

1;

