package Hammer::Getopt;

use strict;
use warnings;
use Getopt::Long;

sub new
{
  shift;
  my ($usage, @options) = @_;
  my $self = { usage => $usage };
  if (ref $options[0] eq 'HASH') {
    $self->{conf} = shift @options;
  } else {
    $self->{conf} = {};
  }

  $self->{options} = [@options];
  return bless $self, __PACKAGE__;
}

sub get
{
  my ($self) = shift;
  $self->{opt} = {};
  my @pre_args;
  if (defined $self->{conf}->{pre_args}) {
    @pre_args = ();
    while (@ARGV and substr($ARGV[0], 0, 1) ne '-') {
      push @pre_args, shift @ARGV;
    }
  }

  if (defined $self->{conf}->{extra_args}) {
    $self->{opt}->{__EXTRA_ARGS} = [];
    for (my $i = 0; $i < scalar(@ARGV); $i++) {
      if ($ARGV[$i] eq '--') {
        $self->{opt}->{__EXTRA_ARGS} = [ @ARGV[$i+1 .. $#ARGV] ];
        @ARGV = $i > 0 ? @ARGV[0 .. $i-1] : ();
        last;
      }
    }
  }

  my $o = Getopt::Long::Parser->new;
  $o->configure(@{$self->{conf}->{config}}) if defined $self->{conf}->{config};
  my $res = $o->getoptions($self->{opt}, map { $_->[0] } @{$self->{options}});
  $self->{opt}->{__PREARGS} = \@pre_args;
  return $res;
}

sub opt { return $_[0]->{opt}; }

sub usage
{
  my ($self, $cmd) = @_;

  my $usage = $self->{usage};
  my $o = join(' ', map { option_spec($_->[0], $_->[2]) } @{$self->{options}});
  $usage =~ s/%o/$o/g;
  $usage =~ s/%c/$cmd/g;

  my $options = [];
  foreach my $o (@{$self->{options}}) {
    next if ref $o ne 'ARRAY';
    push @$options, option_desc(@$o);
  }

  return ($usage, $options);

  sub pretty_opts
  {
    my ($o, $c) = @_;
    my $op = '';
    $o =~ /^([a-zA-Z0-9\-|]+)(?:([\!\+=:])(.+))?$/;
    my @opts = split(/\|/, $1);
    my ($spec, $type) = ($2, $3);
    my $args;
    my $optional = (defined $spec and $spec eq ':') ? 1 : 0;
    if (defined $spec and $spec =~ /[:=]/) {
      my %types = ( s => '<string>', i => '<int>', o => '<int>', f => '<float>' );
      if (defined $c->{arg}) {
        $args = $c->{arg};
      } elsif (defined $types{$type}) {
        $args = $types{$type};
      } else {
        $args = '<unk>';
      }
    }

    sub pretty_opt
    {
      my ($opt, $optional, $arg) = @_;
      return "--$opt=$arg" if length($opt) > 1 and defined $arg and not $optional;
      return "-$opt $arg" if length($opt) == 1 and defined $arg and not $optional;
      return "--$opt"."[=$arg]" if length($opt) > 1 and defined $arg and $optional;
      return "-$opt [$arg]" if length($opt) == 1 and defined $arg and $optional;
      return "-$opt" if length($opt) == 1;
      return "--$opt";
    }

    @opts = map { pretty_opt($_, $optional, $args) } @opts;
    return @opts;
  }

  sub option_desc
  {
    my ($o, $d, $c) = @_;
    return [] unless defined $o;
    my @os = pretty_opts($o, $c);
    my $txt = join(", ", @os);
    return [$txt, $d];
  }

  sub option_spec
  {
    my ($o, $c) = @_;
    my @os = pretty_opts($o, $c);
    my $txt = join("|", @os);
    return $txt if defined $c->{required};
    return "[$txt]";
  }
}

1;
