package Hammer::HelperFunc;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(first any all findkey mapvalues);

sub first(&@) { my $c = shift; ($c->($_) and return $_) foreach @_ }
sub any(&@) { my $c = shift; ($c->($_) and return 1) foreach @_ }
sub all(&@) { my $c = shift; ($c->($_) or return) foreach @_; 1 }

sub findkey {
  my ($h, @keys) = @_;
  return first { exists $h->{$_} } @keys;
}

sub mapvalues(&%) {
  my $fn = shift;
  my %hash = @_;
  my %result;

  while (my ($k, $v) = each(%hash)) {
    local $_ = $v;
    $v = $fn->();
    $result{$k} = $v;
  }

  return %result;
}

1;
