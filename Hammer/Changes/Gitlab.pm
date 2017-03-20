package Hammer::Changes::Gitlab;

use warnings;
use strict;

use URI;
use URI::Escape;
use LWP::UserAgent;
use HTTP::Request;
use JSON::PP;

my $lwp_conn_cache;
eval { require LWP::ConnCache; };
$lwp_conn_cache = LWP::ConnCache->new unless $@;

sub is_change_source { return 1; }
sub name { return 'gitlab'; }

##
# make a request to the GitLab REST API
##
sub _rest_api
{
  my $p = shift;
  my $method = shift;
  my $path = shift;
  my $uri = URI->new($p->{_remote}{gitlab} . '/api/v3/' . $path);

  my $ua = LWP::UserAgent->new(conn_cache => $lwp_conn_cache);
  $ua->default_header('PRIVATE-TOKEN' => $p->{_remote}{gitlab_token}) if defined $p->{_remote}{gitlab_token};
  $ua->ssl_opts(SSL_ca_file => $p->{_remote}{gitlab_ca}) if defined $p->{_remote}{gitlab_ca};

  return $ua->request(HTTP::Request->new($method, $uri, @_));
}

##
# make a request to the GitLab REST API /projects/<namespace>%2F<name>
##
sub _project_rest_api
{
  my $p = shift;
  my $method = shift;
  my $path = shift;

  my $prjname = $p->{name};
  if (defined $p->{_remote}{gitlab_namespace}) {
    $prjname = $p->{_remote}{gitlab_namespace} . '/' . $prjname;
  }
  $prjname = URI::Escape::uri_escape($prjname);

  return _rest_api($p, $method, 'projects/' . $prjname . $path, @_);
}

####
# Query GitLab for changes with the given Change-Id (from gerrit)
#
# Note, a change in GitLab is a merge request with the 'gerrit'
# change ID in the title (usually the title is "Change-Id: <ID>").
##
sub _process_query
{
  my ( $prjs, $p, $query, $chid ) = @_;

  # print STDERR "connections: ". join(", ", $lwp_conn_cache->get_connections) . "\n";
  my $res = _project_rest_api($p, GET => $query);

  if ($res->code != 200) {
    $p->logerr("gitlab API query failed: " . $res->code  . ": " . $res->content
               . ": $query");
    return ();
  }
  my $json = decode_json($res->content);
  my @changes = ();
  foreach my $mr (@$json) {
    next unless $mr->{title} =~ /\b$chid\b/;

    push @changes, {
      id       => $chid,
      src_type => 'gitlab',
      prj      => $p,
      project  => $p->{name},
      branch   => $mr->{target_branch},
      src_ref  => "refs/merge-requests/$mr->{iid}/head",
      desc     => "merge request $mr->{iid} ($mr->{title})",
      chg      => $mr,
    };
  }

  #require Data::Dumper;
  #print Data::Dumper->Dump(\@changes);
  return @changes;
}

sub changes
{
  my ($class, $p, $chid) = @_;
  return ("$class: $p->{name} ~~ $chid" => sub {
    return _process_query($_[0], $p, '/merge_requests?state=opened', $chid);
  });
}

##
# Get an array of all open merge requests from GitLab
##
sub _get_mrs
{
  my ($p) = @_;
  my $res = _project_rest_api($p, GET => '/merge_requests?state=opened');
  if ($res->code != 200) {
    $p->logerr("gitlab API query failed: " . $res->code . ": " . $res->content);
    return [];
  }
  return decode_json($res->content);
}

####
# Hammer::Project upload helper for GitLab
##
sub upload
{
  my ($class, $p, $dst_br, $src_br, $opts) = @_;
  my $r = $p->bare_git;
  my @cmt = $r->cat_object($src_br);
  my @chid = grep /^Change-Id:/, @cmt;
  if (not @chid) {
    $p->logerr("no change id in $src_br.");
    return 0;
  } elsif (scalar(@chid) > 1) {
    $p->logerr("multiple change ids in $src_br.");
    return 0;
  }

  my $chid = $chid[0];
  $chid =~ s/^Change-Id:\s*(\S+)/$1/;
  my $mr_branch = "change-$chid-for-$dst_br";
  my $branch_name = "refs/heads/" . $mr_branch;
  my $mr_title = "Change-Id: $chid";
  if ($opts->{'dry-run'}) {
    print "$p->{path}: git push $p->{remote} $src_br:$branch_name\n";
    print "$p->{path}: gitlab create merge request: '$mr_title' branch $branch_name\n";
  } else {
    $p->loginfo($r->run(push => $p->{remote}, "$src_br:$branch_name"));
    my $mrs = _get_mrs($p);
    if (defined $mrs) {
      return if grep {
        ($_->{title} =~ /\b$chid\b/)
        && ($_->{target_branch} eq $dst_br)
        && ($_->{source_branch} eq $mr_branch)
      } @$mrs;
    }

    my $mr = {
      title                => "Change-Id: $chid",
      source_branch        => $mr_branch,
      target_branch        => "$dst_br",
      remove_source_branch => 'true'
    };

    my $res = _project_rest_api($p, POST => '/merge_requests',
                                [ 'Content-Type', 'application/json'],
                                encode_json($mr));
    if ($res->code != 201) {
      $p->logerr("could not create gitlab merge request for $chid "
                 . "($mr_branch): " . $res->code . ": "
                 . $res->content);
    }
  }
}

1;
