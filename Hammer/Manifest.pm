package Hammer::Manifest;

use strict;
use warnings;
use XML::Parser;
use Hammer::HelperFunc qw(findkey);

sub new
{
  my $class = shift;
  my %members = @_;
  my $self = {
    'filepath' => undef,
    'remote' => {},
    'extend-remote' => {},
    'remove-remote' => {},
    'project' => {},
    'extend-project' => {},
    'remove-project' => {},
    'default' => {},
  };

  foreach my $k (keys %$self)
    {
      $self->{$k} = $members{$k} if exists($members{$k});
    }

  foreach my $k (keys %members)
    {
      die "$class->new(): Unexpected key $k"
        unless exists $self->{$k};
    }

  bless $self, $class;
  return $self;
}

sub new_from_file
{
  my $class = shift;
  my $file = shift;

  my $self = $class->new(filepath => $file);

  my $parser = XML::Parser->new(
    Handlers => {
      Start => sub {
        my $parser = shift;
        my $tagname = shift;
        my %attr = @_;

        # Ignore root element
        return unless $parser->context;

        if ($tagname =~ /^(extend-|remove-|)(project|remote)$/)
          {
            my $type = $2;

            die "$file: Attribute 'name' missing in <$tagname ...>\n"
              unless exists $attr{name};

            my $name = $attr{name};
            $name //= $attr{project_name} if $type eq "project";

            die "$file: Multiple <$tagname ...> with named '$name'\n"
              if exists $self->{$tagname}->{$name};

            $self->{$tagname}->{$name} = { %attr };
          }
        elsif ($tagname eq "default")
          {
            $self->{default} = {
              %{$self->{default}},
              %attr
            };
          }
        else
          {
            die "$file: Unexpected <$tagname ...>\n";
          }
      },
    },
  );

  $parser->parsefile($file);

  return $self;
}

# Apply a local manifest to a manifest
sub extend
{
  my ($self, $other) = @_;

  # Merge defaults
  $self->{default} = {
    %{$self->{default}},
    %{$other->{default}},
  };

  sub apply_type {
    my ($self, $other, $type, @keyattrs) = @_;

    my $otherfp = $other->{filepath} // "<unknown>";

    # Apply removals first so that a local-manifest can remove a
    # project/remote and then redefine it from scratch.
    foreach my $removal (values %{$other->{"remove-$type"}})
      {
        my $keyattr = findkey($removal, @keyattrs);
        die "$otherfp: Node <remove-$type ...> is missing one of these attributes: " . join(", ", @keyattrs)
          unless defined $keyattr;
        delete $self->{$type}{$removal->{$keyattr}};
      }

    # Add plain project/remotes next
    foreach my $addition (values %{$other->{$type}})
      {
        my $keyattr = findkey($addition, @keyattrs);

        die "$otherfp: Node <$type ...> is missing one of these attributes: " . join(", ", @keyattrs)
          unless defined $keyattr;

        my $name = $addition->{$keyattr};

        die "$otherfp: Node <$type ...> named '$name' redefined."
          if exists $self->{$type}{$name};

        $self->{$type}{$name} = $addition;
      }

    # Apply extend-project/remotes
    foreach my $extension (values %{$other->{"extend-$type"}})
      {
        my $keyattr = findkey($extension, @keyattrs);

        die "$otherfp: Node <extend-$type ...> is missing one of these attributes: " . join(", ", @keyattrs)
          unless defined $keyattr;

        my $name = $extension->{$keyattr};

        $self->{$type}{$name} = {
          %{$self->{$type}{$name}},
          %$extension
        };
      }
  }

  apply_type($self, $other, "project", qw(project_name name));
  apply_type($self, $other, "remote", qw(name));
}

sub projects {
  my $self = shift;

  # Ensure no modifying tags have been forgotten.
  foreach my $tagname (map { ("extend-$_","remove-$_") } qw(remote project))
    {
      die "Unexpected remaining node(s) '$tagname'\n"
        if %{$self->{$tagname}};
    }

  my %defaults = %{$self->{default} // {}};

  my %projects;

  while (my ($name, $partial_info) = each(%{$self->{project}}))
    {
      # To be on the safe side
      $partial_info //= {};
      # Copy info from manifest and apply defaults
      my $info = { %defaults, %$partial_info };

      for my $attr (qw(name path remote))
        {
          die "Missing attribute '$attr' for project" . ($attr ne "name" ? " with name '$info->{name}'" : " with path '$info->{path}'") . "\n"
            unless exists $info->{$attr} && $info->{$attr} ne "";
        }

      die qq(Missing node <remote name="$info->{remote}" ...> for project '$info->{name}')
        unless exists $self->{remote}{$info->{remote}};

      # Insert selected remote as auxiliary information
      $info->{_remote} = { %{$self->{remote}{$info->{remote}}} };

      $projects{$name} = $info;
    }

  return %projects;
}

sub each_project(&) {
  my $self = shift;
  my $cb = shift;

  foreach my $project (values %{$self->{project}})
    {
      local $_ = $project;
      $cb->();
    }
}

1;
