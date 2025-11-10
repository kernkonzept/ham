# SPDX-License-Identifier: BSD-2-Clause

package Hammer::Project;

use strict;
use warnings;

use Carp;
use File::Spec::Functions qw(catdir catfile splitdir);
use File::Copy;
use File::Path qw(make_path);
use Git::Repository;
use Hammer::Project::Status;

sub is_commit_hash { shift =~ /^[0-9a-fA-F]{40}$/ }

#################################
# Git::Repository::Plugin::KK
{
package Git::Repository::Plugin::KK;

  use Git::Repository::Plugin;
  our @ISA      = qw( Git::Repository::Plugin );
  sub _keywords { qw( rev_parse config config_set cat_object merge rebase ) }

  sub rev_parse
  {
    # skip the invocant when invoked as a class method
    return undef if !ref $_[0];
    my $r = shift;
    my $res = $r->run('rev-parse', '--revs-only', @_, { quiet => 1, fatal => [-128 ]});
    return undef unless defined $res;
    return undef unless $res ne '';
    return $res;
  }

  sub cat_object
  {
    # skip the invocant when invoked as a class method
    return undef if !ref $_[0];
    return $_[0]->run('cat-file', '-p', $_[1]);
  }

  sub merge
  {
    my $git = shift;
    my $output = shift;
    my $cmd = $git->command('merge', @_);
    push @$output, $cmd->final_output();
    return $cmd->exit();
  }

  sub rebase
  {
    my $git = shift;
    my $output = shift;
    my $cmd = $git->command('rebase', @_);
    push @$output, $cmd->final_output();
    return $cmd->exit();
  }

  sub config
  {
    my ($git, $var, $type) = @_;
    my @g = ('--get');
    @g = ('--get-all') if wantarray;
    push @g, "--$type" if defined $type;
    my @r = $git->run('config', @g, $var);
    return undef if ($? >> 8) == 1;
    return $r[0] unless wantarray;
    return (@r);
  }

  sub config_set
  {
    my ($git, $var, $value, $type) = @_;
    my @cmd = ('config');
    push @cmd, "--$type" if defined $type;
    $git->run(@cmd, $var, $value);
  }
}

Git::Repository::Plugin::KK->install();


sub new
{
  my ($class, $hash, %o) = @_;
  $hash->{project_name} = $hash->{name} unless defined $hash->{project_name};
  $hash->{_stderr} = $o{stderr};
  $hash->{_stdout} = $o{stdout};
  $hash->{_root}   = $o{root};
  bless $hash, $class;
}

## get the absolute base path to the work tree of this project
sub abs_path
{
  my $self = shift;
  my $base = $self->{_root};
  return catdir($base, $self->{path});
}

#
# get the '.ham' directory for the project
#
sub ham_dir
{ return catdir($_[0]->{_root}, '.ham'); }

#
# get the attic base path for this project
#
sub attic_base_path
{ return catdir($_[0]->ham_dir, 'attic'); }

#
# get the project specific attic dir
#
sub attic_path
{ return catdir($_[0]->attic_base_path, $_[0]->{name} . '.git'); }

sub ham_dir_rel
{
  my ($self, $sub, $dir) = @_;
  $sub = $self->{path} unless defined $sub;
  $sub = substr $sub, 1 if substr($sub, 0, 1) eq '/';
  my @d = splitdir($sub);
  $dir = catdir('..', $dir) foreach @d;
  return $dir;
}

## test if the work tree diretory exists
sub exists { return -e $_[0]->abs_path; }

## get the .git directory for this project
sub gitdir { return catdir($_[0]->abs_path, '.git'); }

## check for the existence of the '.git' directory
sub is_git_repo { return -e $_[0]->gitdir; }

## get the Git::Repository object for this project (incl. a work tree)
sub git
{
  my $self = shift;
  my $err = shift;

  return $self->{_repo} if defined $self->{_repo};

  if (not $self->is_git_repo) {
    push @$err, "$self->{path} is not a git repository (.git missing)" if defined $err;
    return undef;
  }

  my $r = $self->{_bare_repo} = $self->{_repo}
        = Git::Repository->new(git_dir => $self->gitdir,
                               work_tree => $self->abs_path,
                               { env => { LC_ALL => 'C' } });
  if (not defined $r and defined $err) {
    push @$err, "$self->{path} is not a valid git repository";
    return undef;
  }

  return $r;
}

## get the Git::Repository object for this project (bare)
sub bare_git
{
  my $self = shift;
  my $err = shift;
  return $self->{_bare_repo} if defined $self->{_bare_repo};

  if (not $self->is_git_repo) {
    push @$err, "$self->{path} is not a git repository (.git missing)" if defined $err;
    return undef;
  }

  my $r = $self->{_bare_repo} = Git::Repository->new(git_dir => $self->gitdir,
                                                     { env => { LC_ALL => 'C' } });
   if (not defined $r and defined $err) {
    push @$err, "$self->{path} is not a valid git repository";
    return undef;
  }

  return $r;
}

#
# move a project git repo to the attic directory
#
# The project will only be moved to attic if it has a clean
# working tree, the function will fail otherwise.
#
# NOTE: the working tree will be deleted
#
sub store_to_attic
{
  my ($self, $force) = @_;
  return undef if not $self->is_git_repo;
  my $s = $self->status;
  if ($s->is_dirty) {
    if ($force) {
      $self->loginfo("contains changes, forced move");
    } else {
      $self->logerr("contains changes, not moving to attic");
      return 0;
    }
  }

  my $attic_base = $self->attic_base_path;
  make_path($attic_base);

  my $base = $self->abs_path;
  my $git = $self->git($self->{_stderr});
  my @files = map { catdir($base, $_); } split("\0", $git->run('ls-files', '-z'));
  my @dirs = map { catdir($base, $_); }
             sort { $b cmp $a }
             split("\0", $git->run('ls-tree', '-d', '--name-only', '-z', '-r', 'HEAD', { fatal => [-128] }));
  push @dirs, $base;
  $self->loginfo("moving to attic: ".$self->attic_path);
  return 0 unless File::Copy::move($self->gitdir, $self->attic_path);
  unlink(@files);
  foreach my $i (@dirs) { rmdir($i); }
  return 1;
}

#
# restore a project from its git repo in the attic directory
#
sub restore_from_attic
{
  my $self = shift;
  die "internal error: trying to overwrite .git in working copy: ".$self->girdir if $self->is_git_repo;
  return 0 if not -d $self->attic_path;
  make_path($self->abs_path);
  return File::Copy::move($self->attic_path, $self->gitdir);
}

#
# migrate project (git repo and working copy) to its new location
#
# the new location is $self->{path} and the old location relative to
# $self->{_root} must be given as argument.
#
sub migrate_from
{
  my ($self, $old_path) = @_;
  my $old = catdir($self->{_root}, $old_path);
  my $new = $self->abs_path;
  my $n = $self->{name};

  croak "error: source and destination path are equal $old\n"
    if $new eq $old;

  die "error: cannot move $n, source directory does not exist: $old"
    unless -d $old;

  die "error: cannot move $n, destination already exists: $new"
    if -e $new;

  my @new_p = splitdir($new);
  die "error: $n: empty target path"
    unless scalar @new_p;

  # make base path for new location
  my $d = catdir(@new_p[0..$#new_p-1]);
  make_path($d);

  # move to new location
  unless (File::Copy::move($old, $new)) {
    # do cleanup, remove all possibly created empty directories
    my @n = splitdir($self->{path});
    while (scalar @n) {
      rmdir catdir($self->{_root}, @n);
      pop @n;
    }
    die "error: could not move $n from $old to $new: $!";
  }

  # remove old empty directories
  my @old_p = splitdir($old_path);
  while (scalar @old_p) {
    rmdir catdir($self->{_root}, @old_p);
    pop @old_p;
  }

  return 1;
}


## initialize the project work tree (.git)
sub init
{
  my $self = shift;
  Git::Repository->run( init => $self->abs_path, { env => { LC_ALL => 'C' } } );
  $self->{_bare_repo} = $self->{_repo} = Git::Repository->new(work_tree => $self->abs_path,
                                                              { env => { LC_ALL => 'C' } });
  $self->{remote_has_updates} = 1;
}

sub logerr
{
  my $self = shift;
  push @{$self->{_stderr}}, map { "$self->{path}: $_" } @_;
}

sub loginfo
{
  my $self = shift;
  push @{$self->{_stdout}}, map { "$self->{path}: $_" } @_;
}

sub handle_output
{
  my ($self, $cmd) = @_;

  my @cerr = $cmd->stderr->getlines;
  my @cout = $cmd->stdout->getlines;
  $cmd->close;
  chomp @cout;
  chomp @cerr;
  # log normal output immediately, to see the progress
  print STDOUT "$self->{name}: $_\n" foreach @cout;
  # disabled: logging to buffer and delayed output
  # $self->loginfo(@cout);
  if ($cmd->exit != 0) {
    $self->logerr(@cerr);
  } else {
    $self->loginfo(@cerr);
  }
}

sub git_head
{
  my ($self) = @_;
  my $git = $self->git($self->{_stderr});
  return undef unless defined $git;
  return $git->rev_parse('HEAD');
}

## do a conditional checkout for sync
sub sync_checkout
{
  my ($self, $opts) = @_;
  my $git = $self->git($self->{_stderr});
  return 0 unless defined $git;

  my $head = $git->rev_parse('--abbrev-ref', 'HEAD');

  if (not defined $self->{revision}) {
    my $remote = $self->{remote} || 'origin';
    my @remote_rev = map { s/(.*?):\s*(.*)\s*$/$2/; $_ }
                     grep /HEAD branch:/,
                     $git->run("remote", "show", $remote);
    if (@remote_rev) {
      $self->{revision} = $remote_rev[0];
    } else {
      $self->logerr("Can not find remote default branch, please provide --branch");
      return 0;
    }
  }

  # return if we have already a valid checkout, don't touch the working copy
  if (defined $self->{need_checkout}) {
    delete $self->{need_checkout};
    $self->checkout('--force', $self->{revision}.'^{tree}', '--', '.');
  } elsif (defined $head) {
    if ($opts->{rebase}) {
      if ($head ne $self->{revision}) {
        if (defined $opts->{upstream}) {
          $self->checkout($self->{revision});
          $head = $git->rev_parse('--abbrev-ref', 'HEAD');
        } else {
          $self->loginfo("not on branch $self->{revision}, skip rebase");
          return 1;
        }
      }
    } else {
      my $is_dirty = $opts->{'ignore-untracked'} ? $self->status->is_dirty_ignore_untracked
                                                 : $self->status->is_dirty;
      # avoid touching dirty local HEAD branches
      if (($head eq $self->{revision}) and $is_dirty) {
        $self->loginfo("WARNING: your local working copy has changes, skipping fast-forward.",
                       "         you may use 'git stash; git pull -r; git stash pop'",
                       "         locally to resolve the problem.");
        return 1;
      }

      my $dst_br = is_commit_hash($self->{revision}) ? ("revision-" . $self->{revision}) : $self->{revision};
      my $cmd = $self->git->command('pull', '--ff-only', $self->{_remote}->{name}, "$self->{revision}:$dst_br", {quiet => 1, fatal => [-128 ]});
      $self->handle_output($cmd);

      return 1;
    }

    my $remote = $self->{_remote}->{name};
    my $remote_ref_n = "refs/remotes/$remote/$head";
    my $remote_ref = $git->rev_parse($remote_ref_n);
    if (not $remote_ref) {
      $self->loginfo("no corresponding remote branch found ($head), skipping rebase");
      return 1;
    }

    my $o;
    if (defined $opts->{upstream}) {
      $o = $self->git->command("reset", "--hard", $remote_ref_n);
    } else {
      $o = $self->git->command('rebase', $remote_ref_n);
    }

    $self->handle_output($o);
    return 1;
  }

  my $revision = $self->{revision};
  print STDERR "checkout $self->{name} @ $self->{path} ($revision)\n";
  if (not defined $revision) {
    $self->logerr("has no revision to checkout");
    return 0;
  }

  if (not defined $self->{_remote} or not defined $self->{_remote}->{name}) {
    $self->logerr("has no valid remote");
    return 0;
  }

  my $remote_name = $self->{_remote}->{name};
  if (not $git->rev_parse("$remote_name/$revision")
      and not $git->rev_parse("$revision")) {
    $self->logerr("has no branch named $revision");
    return 0;
  }

  #$self->checkout('-b', $revision, '--track', $remote_name.'/'.$revision);
  $self->checkout($revision);
  return 1;
}

sub add_changeid_hook
{
  my ($self, $opts) = @_;
  my $git = $self->bare_git;

  my $remote = $self->{_remote};
  unless (defined $remote->{review} and $remote->{review} ne '') {
    $git->run(config => '--bool', 'gerrit.createChangeId', 'false');
    return;
  }

  my $hooks = $git->git_dir.'/hooks';
  my $hook_path = catfile($hooks, "commit-msg");
  if (not -e $hook_path) {
    make_path($hooks) unless -d $hooks;
    my $base = $self->{_root};
    if (index($hooks, $base) != 0) {
      $self->logerr("$hooks is not within our repo at $base");
      return 0;
    }

    my $rel_hooks = $self->ham_dir_rel(substr($hooks, length($base)),
                                       '.ham/hooks/commit-msg');
    unlink $hook_path if -l $hook_path && (not -e $hook_path);
    symlink($rel_hooks, $hook_path)
      or $self->logerr("fatal: link $hooks/commit-msg: $!");
  }

  $git->run(config => '--bool', 'gerrit.createChangeId', 'true');
  $git->run(config => '--bool',
            'remote.'.$self->{_remote}->{name}.'.ham', 'true');
  $git->run(config => '--replace-all',
            'ham.'.$self->{_remote}->{name}.'.revision', $self->{revision});
}

## prepare the git repo after sync, incl. checkout
sub prepare
{
  my ($self, $opts) = @_;
  my $res = $self->sync_checkout($opts);
  $self->add_changeid_hook();
  return $res;
}

my $trace = 0;

sub _fetch_progress
{
  local $_ = shift;
  my $self = shift;
  s|\n||gm;
  if (/^\s+(.*)->\s+(.*)\s*$/) {
    $self->{remote_has_updates} = 1;
    $self->loginfo($_);
  }
  if ($_ ne '' and $self->{trace_fetch} or $trace) {
    print STDERR "$self->{name}: $_\n";
    $self->logerr($_);
  } elsif (/^fatal:|^ssh:/) {
    $self->{trace_fetch} = 1;
    print STDERR "$self->{name}: $_\n";
    $self->logerr($_);
  }

  if (/^remote: Finding sources:\s*([0-9]+%).*$/) {
    return "$self->{name}: $1";
  } elsif (/^Receiving object:\s*([0-9]+%).*$/) {
    return "$self->{name}: $1";
  } elsif (/^Resolving deltas:\s*([0-9]+%).*$/) {
    return "$self->{name}: $1";
  }
  return undef;
}

sub _collect
{
  local $_ = shift;
  my $self = shift;
  push @{$self->{output}}, $_;
}

my %checked_ssh_db;

sub check_ssh
{
  # Check that ssh is working ok. This is a bit of a workaround currently as
  # the ssh connection is too deep hidden under the already abstracted git
  # access herein.
  # SSH non-working reasons can be: missing ssh-key and ssh asking for
  # typing in the passphrase; new public host key requesting to answer with
  # yes/no, i.e. it requires interaction with the user

  my ($baseurl) = @_;

  return if defined $checked_ssh_db{$baseurl};
  return unless $baseurl =~ /^(git\+)?ssh\:\/\//;

  $checked_ssh_db{$baseurl} = 1;

  system("git ls-remote $baseurl > /dev/null");
  if ($?) {
    print "ham: ssh returned with error with '$baseurl'\n";
    exit 1;
  }
}

sub fetch
{
  my $self = shift;
  check_ssh($self->{_remote}->{fetch});
  return (
    $self->bare_git->command('fetch', '--progress', @_, { quiet => 1 }),
    out => \&_collect, err => \&_fetch_progress, args => $self,
    finish => sub {
      $self->{trace_fetch} = 0;
      return "done fetching $self->{name}".
             ($self->{remote_has_updates} ? ", has updates" : "")
    }
  );
}

## checkout the work tree
sub checkout
{
  my $r = shift;
  my @args = @_;
  my $branch = \(grep { not /^-/ } @args)[0];
  $$branch =~ s,\{UPSTREAM\},$r->{revision},g;

  my $git = $r->git;
  if (not $git) {
    $r->logerr("is no git repo (may be you need 'sync')");
    return 128;
  }

  push @args, '--' unless grep /^--$/, @args;

  my $head = $git->rev_parse('--abbrev-ref', 'HEAD');
  return if defined $head and $head eq $$branch and @args == 1;
  $head = '' unless defined $head;

  my $cmd = $git->command('checkout', @args, {fatal => [-128], quiet => 1});
  my @cerr = $cmd->stderr->getlines;

  if (grep /invalid reference: $$branch/, @cerr) {
    $r->loginfo("has no reference $$branch, stay at the previous head ($head)");
    return 128;
  }
  if (grep /(Already on )|(Switched to branch )'$$branch'/, @cerr) {
    return 0;
  }

  if (grep /Switched to a new branch /, @cerr) {
    # this happens for the initial checkout of a remote branch
    return 0;
  }

  if (grep /pathspec '\.' did not match any file\(s\) known to git/, @cerr) {
    # this happens in empty repos
    return 128;
  }

  if (grep /You are in 'detached HEAD' state./, @cerr) {
    # this happens when e.g. a tag is checked out without creating a branch
    # (e.g. during ham sync). This is actually a Note printed by git to
    # stderr.
    chomp(@cerr);
    $r->loginfo(@cerr);

    return $cmd->exit;
  }

  if (grep /HEAD is now at/, @cerr) {
    # Another message that is not a real error, but printed to stderr by git,
    # e.g. when running ham init with a tag.

    chomp(@cerr);
    $r->loginfo(@cerr);

    return $cmd->exit;
  }

  if (@cerr) {
    chomp(@cerr);
    $r->logerr(@cerr);
  }
  return $cmd->exit;
}

## get the URL used as fetch URL for this project
sub get_fetch_url
{
  my $self = shift;
  return $self->{_remote}->{fetch};
}

sub add_to_alternates
{
  my ($self, $reference_basepath) = @_;

  croak("no path argument given") unless defined $reference_basepath;

  my $ref = catdir($reference_basepath, $self->{path}, '.git', 'objects');
  unless (-d $ref) {
    $self->loginfo("referenced directory '$ref' does not exist, ignoring");
    return 0;
  }

  my $info_dir = catdir($self->gitdir, 'objects', 'info');
  make_path($info_dir);
  my $alternates_file = catfile($info_dir, 'alternates');

  my $A;
  if (open($A, $alternates_file)) {
    if (grep { chomp; $_ eq $ref } (<$A>)) {
      close $A;
      return 1;
    }
    close $A;
  }

  unless (open($A, ">>$alternates_file")) {
    $self->logerr("cannot open $alternates_file: $!");
    return 0;
  }

  print $A "$ref\n";
  close $A;
  return 1;
}

sub hamify_repo
{
  my $self = shift;
  croak "error: $self->{path} is not a git repository"
    unless $self->is_git_repo;

  my $git = $self->git;
  my $ham_remote = $git->config('ham.remote');
  my $ham_prj_name = $git->config('ham.project');
  my $remote_name = $self->{_remote}->{name};
  if (defined $ham_remote) {
    if ($ham_remote eq $remote_name) {
      $git->run(remote => 'set-url', $remote_name, $self->get_fetch_url);
      return 1;
    }

    $git->run(remote => 'remove', $ham_remote);
  }

  my $old_url = $git->config("remote.$remote_name.url");
  if (not defined $old_url) {
    $git->run(remote => 'add', $remote_name, $self->get_fetch_url);
  } elsif ($old_url ne $self->get_fetch_url) {
    $self->logerr("remote $remote_name already exists");
    $self->logerr("  current URL: $old_url");
    $self->logerr("  new URL:     ".$self->get_fetch_url);
    return 0;
  }
  $git->config_set('ham.remote', $remote_name);
  return 1;
}

## sync #############################################
sub sync
{
  my ($self, $opts) = @_;
  my $remote_name = $self->{_remote}->{name};
  my $r;
  make_path($self->abs_path) unless $self->exists;
  if ($self->is_git_repo) {
    $r = $self->bare_git;
    #print STDERR "fetch $self->{project_name} from $remote_name\n";
  } elsif ($self->restore_from_attic) {
    $self->{need_checkout} = 1;
  } else {
    #print "run: ($self->{path}) git clone $remote_name\n";
    $r = $self->init;
  }

  $self->hamify_repo;
  $self->add_to_alternates($opts->{reference}) if defined $opts->{reference};

  return $self->fetch(
    $remote_name,
    "+refs/heads/*:refs/remotes/${remote_name}/*",
    $self->{revision} // (),
  );
}


sub status
{
  my $self = shift;
  my $r = $self->git($self->{_stderr});
  return unless $r;
  return Hammer::Project::Status->new($r->run(status => '--porcelain', '-b'));
}

sub print_status
{
  my $self = shift;
  my $s = $self->status;
  if ($s->is_different or $s->is_dirty) {
    print "project: $self->{name} at ".$self->abs_path."\n";
    print join("\n", @$s)."\n";
  }
  return;
}


sub check_rev_list
{
  my ($prj, $r, $src_br, $rev_list, $relax) = @_;

  my @no_chid = ();
  my %duplicate_chid = ();
  my @duplicate_chid = ();
  my @multiple_chid = ();

  foreach my $c (@$rev_list) {
    my @cmt = $r->cat_object($c);
    my @chid = grep /^Change-Id:/, @cmt;
    if (not @chid) {
      push @no_chid, $c;
      next;
    } elsif (scalar(@chid) > 1) {
      push @multiple_chid, $c;
      next;
    }

    my $chid = $chid[0];
    $chid =~ s/^Change-Id:\s*(\S+)/$1/;

    if ($chid eq '') {
      push @no_chid, $c;
      next;
    }

    if ($duplicate_chid{$chid}) {
      push @{$duplicate_chid{$chid}}, $c;
      push @duplicate_chid, $chid;
      next;
    } else {
      $duplicate_chid{$chid} = [ $c ];
    }
  }

  my $list_errors = sub
  {
    my ($msg, $e) = @_;
    return unless @$e;
    my $logger = 'logerr';
    $logger = 'loginfo' if $relax;
    $prj->$logger("branch $src_br: $msg");
    foreach my $c (@$e) {
      my $x = $r->run('log', '-n', '1' ,'--oneline', '--color=always', $c);
      $prj->$logger("  $x");
    }
  };

  $list_errors->("the following commits have no change ID", \@no_chid);
  $list_errors->("the following commits have multiple change IDs", \@multiple_chid);
  foreach my $id (@duplicate_chid) {
    $list_errors->("the following commits have the same change ID (you should squash them)",
                   $duplicate_chid{$id});
  }

  return 0 if @no_chid or @multiple_chid or @duplicate_chid;
  return 1;
}

sub check_for_upload
{
  my ($prj, $warn, $src_br, $dst_br, $approve_cb, $relax) = @_;
  my $r = $prj->git($prj->{_stderr});
  my $src_rev = $r->rev_parse($src_br);

  if (not $src_rev) {
    push @$warn, "$prj->{path}: branch has no branch $src_br, skipping.";
    return 0;
  }

  my $remote = $prj->{remote};
  $dst_br = $prj->{revision} unless defined $dst_br;
  $dst_br = 'master' unless defined $dst_br;
  my $rem_br = "$remote/$dst_br";
  my $dst_rev = $r->rev_parse($rem_br);

  if (not $dst_rev) {
    push @$warn, "$prj->{path}: branch has no branch $remote/$dst_br, skipping.";
    return 0;
  }

  # skip if there is nothing to do
  return 0 if $src_rev eq $dst_rev;

  my $merge_base = $r->run('merge-base', $dst_rev, $src_rev);
  if (!$merge_base) {
    $prj->logerr("$src_br is not derived from $rem_br");
    return 0;
  }

  my @commits = $r->run('rev-list', '--ancestry-path', "^$merge_base", $src_rev);
  if (not @commits) {
    $prj->logerr("$src_br is not derived from $rem_br");
    return 0;
  }

  # check if all commits have change IDs
  return 0 unless ($prj->check_rev_list($r, $src_br, \@commits, $relax) || $relax);

  # check the number of changes for this branch
  my $num_changes = scalar(@commits);
  if ($num_changes > 1) {
    if (not defined $approve_cb or not $approve_cb->($prj, \@commits)) {
      $prj->logerr("branch $src_br has more than one ($num_changes) change for $rem_br");
      return 0;
    }
  }
  return wantarray ? (1, $src_br, $dst_br) : 1;
}

1;
