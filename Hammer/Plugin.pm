# SPDX-License-Identifier: BSD-2-Clause

package Hammer::Plugin;

use strict;
use warnings;

my $err = [];
my $info = [];
my %change_sources;

sub logerr
{
  my $class = shift;
  push @$err, (@_);
}

sub loginfo
{
  my $class = shift;
  push @$info, (@_);
}

sub errors
{ return $err; }

sub infos
{ return $info; }

sub _add_change_source
{
  my ($source) = @_;
  my $n = $source->name;
  if (!$source->can('upload') || !$source->can('changes')) {
    die "internal error: change source $n is invalid\n";
  }

  $change_sources{$n} = $source;
}

sub change_source
{
  my $class = shift;
  my $p = shift;
  my $remote_type;
  $remote_type = 'gerrit' if defined $p->{_remote}{review};
  $remote_type = $p->{_remote}{type} if defined $p->{_remote}{type};
  return undef unless defined $remote_type;
  return $change_sources{$remote_type} if defined $change_sources{$remote_type};
  $p->logerr("cannot handle repos of type: $remote_type");
  return undef;
}

sub load_plugin
{
  my ($class, $name) = @_;
  my $fname = $name;
  $fname =~ s|::|/|g;
  $fname .= '.pm';
  eval {
    require $fname;
    _add_change_source($name) if $name->is_change_source;
    1;
  };

  if ($@) {
    print STDERR "could not load plugin: $name ($fname): $@\n";
    return undef;
  }
  return 1;
}

1;
