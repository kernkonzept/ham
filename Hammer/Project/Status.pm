# SPDX-License-Identifier: BSD-2-Clause

package Hammer::Project::Status;

use strict;
use warnings;

sub new
{
  my ($p, @s) = @_;
  return bless \@s, $p;
}

my %what = (
  M =>    'modified:   ',
  A =>    'added:      ',
  D =>    'deleted:    ',
  R =>    'renamed:    ',
  C =>    'copied:     ',
  'DD' => 'both deleted:    ',
  'AU' => 'added by us:     ',
  'UD' => 'deleted by them: ',
  'UA' => 'added by them:   ',
  'DU' => 'deleted by us:   ',
  'AA' => 'both added:      ',
  'UU' => 'both modified:   ',
  '??' => '',
  '!!' => 'ignored:     ',
  '' => '',
);

sub is_different
{
  my $self = shift;
  return $self->[0] =~ /##.*(?:\[ahead|\[behind)/;
}

sub is_ahead
{
  return $_[0]->[0] =~ /##.*\[.*(?:ahead).*\]/;
}

sub is_behind
{
  return $_[0]->[0] =~ /##.*\[.*(?:behind).*\]/;
}

sub is_dirty      { scalar(@{$_[0]}) > 1; }
sub branch_status { $_[0]->[0]; }
sub files         { @{$_[0]}[1..$#{$_[0]}]; }
sub conflicts     { grep { /^(U.|.U|DD|AA)/ } $_[0]->files; }
sub index         { grep { /^[MARCD]./ } $_[0]->files; }
sub changed       { grep { /^.[MD]/ } $_[0]->files; }
sub untracked     { grep { /^\?\?|\!\!/ } $_[0]->files; }

sub __pretty
{
  my ($x, $path, $v)  = @_;
  my ($m, $p1, $p2);
  if ($v =~ /^([ MADRCU?!]{2})\s(.*)\s->\s(.*)$/) {
    ($m, $p1, $p2) = ($1, File::Spec->catdir($path, $2), File::Spec->catdir($path, $3));
  }
  if ($v =~ /^([ MADRCU?!]{2})\s(.*)$/) {
    ($m, $p1) = ($1 ,File::Spec->catdir($path, $2));
  }

  return "??  ERROR ($path: $v)" unless $m;

  $m =~ s,$x,,;
  my $r = "$what{$m}$p1";
  $r .= " -> $p2" if $p2;
  return $r;
}

sub pretty_index
{
  my ($s, $path) = @_;
  map { __pretty('.$', $path, $_) } $s->index;
}

sub pretty_untracked
{
  my ($s, $path) = @_;
  map { __pretty('', $path, $_) } $s->untracked;
}

sub pretty_changed
{
  my ($s, $path) = @_;
  map { __pretty('^.', $path, $_) } $s->changed;
}

sub pretty_conflicts
{
  my ($s, $path) = @_;
  map { __pretty('', $path, $_) } $s->conflicts;
}

1;
