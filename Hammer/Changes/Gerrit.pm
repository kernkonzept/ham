# SPDX-License-Identifier: BSD-2-Clause

package Hammer::Changes::Gerrit;

use strict;
use warnings;

use URI;
use JSON::PP;
use File::Spec::Functions qw(catdir);
use Hammer::Plugin;

sub name { return 'gerrit'; }
sub is_change_source { return 1; }

sub _process_query
{
  my ($prjs, @json) = @_;
  my @changes = ();

  foreach my $j (@json) {
    my $q = decode_json($j);
    if (not defined $q) {
      Hammer::Plugin->logerr("gerrit did not return a JSON string but '$j'");
      next;
    }
    if (defined $q->{type} and $q->{type} eq 'error') {
      Hammer::Plugin->logerr("gerrit returned an error: '$q->{message}'");
      next;
    }
    next if defined $q->{type} and $q->{type} eq 'stats';
    if (not defined $q->{project} or not defined $q->{id}
        or not defined $q->{currentPatchSet} or not defined $q->{number}
        or not defined $q->{branch}) {
      Hammer::Plugin->logerr("the query result seems to be no change '$j'");
      next;
    }

    next if not $q->{open};
    next if not $prjs->{$q->{project}};

    push @changes, {
      src_type => 'gerrit',
      id       => $q->{id},
      prj      => $prjs->{$q->{project}},
      project  => $q->{project},
      branch   => $q->{branch},
      src_ref  => $q->{currentPatchSet}{ref},
      desc     => "change $q->{number}/$q->{currentPatchSet}{number}",
      chg      => $q
    };
  }

  return @changes;
}

# per default register the gerrit change_source
sub changes
{
  my ($class, $p, $chid) = @_;
  my $uri = URI->new($p->{_remote}{fetch});
  if ($uri->scheme eq 'ssh') {
    my $query = 'ssh';
    $query .= ' -p '.$uri->_port if defined $uri->_port;
    $query .= ' -l '.$uri->userinfo if defined $uri->userinfo;
    $query .= ' '.$uri->host;
    $query .= " gerrit query --current-patch-set --format=JSON change:$chid";
    return ($class . ': ' . $query => sub { return _process_query($_[0], qx($query)); });
  }

  Hammer::Plugin->logerr("unsupported remote ($uri) in $p->{name} for the download-id command");
  return ();
}

sub upload
{
  my ($class, $self, $dst_br, $src_br, $opts) = @_;
  my @base_attr;
  foreach my $c (map { split /,/ } @{$opts->{re}}) {
    push @base_attr, "r=$c";
  }

  foreach my $c (map { split /,/ } @{$opts->{cc}}) {
    push @base_attr, "cc=$c";
  }

  my $target = 'for';
  $target = 'drafts' if ($opts->{draft});

  my $dst_ref = catdir('refs', $target, $dst_br);
  my @attrs;
  my $r = $self->bare_git;
  if ($opts->{topic}) {
    push @attrs, "topic=$opts->{topic}";
  } elsif ($opts->{t}) {
    $src_br = $r->rev_parse('--abbrev-ref', $src_br) if $src_br eq 'HEAD';
    push @attrs, "topic=$src_br";
  }
  push @attrs, @base_attr;
  if (@attrs) {
    $dst_ref .= "%".join(',', @attrs);
  }

  if ($opts->{'dry-run'}) {
    print "$self->{path}: git push $self->{remote} $src_br:$dst_ref\n";
  } else {
    $self->loginfo($r->run('push', $self->{remote}, "$src_br:$dst_ref"));
  }
}

1;
