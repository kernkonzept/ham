package Hammer::Subcommand;

use strict;
use warnings;

use Hammer::Getopt;
use Carp;

sub new
{
  shift;
  my %o = @_;
  return bless {
    cmd  => $o{cmd},
    opt  => Hammer::Getopt->new(ref $o{syn} eq 'ARRAY' ? @{$o{syn}} : $o{syn}),
    desc => $o{desc}
  }, __PACKAGE__;
}

sub add
{
  my ($self, $name, $subcmd) = @_;
  return $self->{sub}{$name} = $subcmd if ref $subcmd eq 'Subcommand';
  return $self->{sub}{$name} = Hammer::Subcommand->new(%$subcmd) if ref $subcmd eq 'HASH';
  croak "Subcommand::add needs a hash reference or a Subcommand as second parameter";
}

sub alias
{
  my ($self, $name, $orig) = @_;
  $self->{alias}->{$name} = [ split(/\s+/, $orig) ];
}

sub sub { return $_[0]->{sub}; }

sub usage
{
  my $self = shift;
  return ($self->{opt}->usage(@_), $self->{desc});
}

sub find
{
  my ($self, $command) = @_;
  if (not defined $self->sub or not @ARGV or substr($ARGV[0],0,1) eq '-') {
    return (1, $self, $command);
  }

  while (1) {
    my $subcmd = shift @ARGV;
    my $s = $self->sub->{$subcmd};
    if (not defined $s) {
      my $alias = $self->{alias}->{$subcmd};
      if (defined $alias) {
        unshift @ARGV, @$alias;
        next;
      }
      return (undef, $self, $command, $subcmd);
    }
    return $s->find("$command $subcmd");
  }
}

sub run
{
  my ($self, $command) = @_;
  my $ok = 0;
  my $subcmd;
  ($ok, $self, $command, $subcmd) = $self->find($command);
  if (not $ok) {
    print STDERR "error: unknown command $command $subcmd\n";
    $self->print_usage($command, *STDERR); # exits
  }

  return $self->_exec($command);
}

sub _exec
{
  my ($self, $command) = @_;
  $self->print_usage($command, *STDERR) unless $self->{opt}->get;
  return $self->{cmd}->($self->{opt}->opt, $command, $self);
}

sub print_usage
{
  my $out = defined $_[2] ? $_[2] : *STDERR;
  my $old = select($out);
  shift->_print_usage(@_);
  select($old);
  exit(129);
}

sub usage_error
{
  print STDERR "$_[2]\n";
  shift->print_usage($_[0], *STDERR);
}

sub _print_usage(**)
{
  my ($subcmd, $cmd) = @_;

  sub strip_spaces($)
  {
    my $i = shift;
    $i =~ s,[\n\t ]+, ,sg;
    return $i;
  }

  my ($usage, $options, $description) = $subcmd->usage($cmd);
  $description = strip_spaces($description);

format USAGE =
  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  $usage
~~          ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            $usage
.
format DESCR =
~~      ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        $description
.
  local $~ = 'USAGE';
  local $: = " \n";
  write;
  $~ = 'DESCR';
  print "\n";
  write;
  print "\n";
  foreach my $o (@$options) {
    my $option = $o->[0];
    my $desc = strip_spaces($o->[1]);
format OPTION =
        ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<...
        $option
~~          ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
            $desc
.
      $~ = 'OPTION';
    write;
    print "\n";
  }

  if (defined $subcmd->sub) {
    #print "  SUB COMMANDS\n";
    foreach my $c (sort keys %{$subcmd->sub}) {
      my $d =$subcmd->sub->{$c};
      $d->_print_usage("$cmd $c");
      print "\n";
    }
  }

  if (defined $subcmd->{alias}) {
    print "  ALIASES\n";
    foreach my $c (sort keys %{$subcmd->{alias}}) {
      my $a = join(' ', @{$subcmd->{alias}->{$c}});
format ALIAS =
        @<<<<<<<<<<<<<<<<<<<<< =  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        $c,                       $a
~~                                ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                  $a
.
      $~ = 'ALIAS';
      write;
    }
  }
}

1;
