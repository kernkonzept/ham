## stream to be processed by a stream processor
package Hammer::Stream;

use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

sub new
{
  shift;
  my $fh = shift;
  my $cb = shift;
  my @args = @_;
  my $self = {};
  $self->{buffer} = '';
  $self->{fh} = $fh;
  $self->{cb} = $cb;
  $self->{sep} = "\n\r";
  $self->{args} = \@args;
  my $flags = fcntl($fh, F_GETFL, 0);
  fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
  return bless $self, __PACKAGE__;
}

sub process
{
  my $self = shift;
  my $func = shift;
  my @args = @_;
  my $buffer = \$self->{buffer};
  my $fh = $self->{fh};
  my $sep = $self->{sep};

  my $buf = '';
  my $n = sysread($fh, $buf, 1024);
  $$buffer .= $buf;
  if ($$buffer =~ s/([^\r\n]+)[\r\n]//) {
    $self->{cb}->(0, $1, @{$self->{args}});
    return 1;
  } elsif ($n == 0) {
    $self->{cb}->(1, $$buffer, @{$self->{args}});
    $$buffer = '';
    $self->{done} = 1;
    return 0;
  }
}

1;
