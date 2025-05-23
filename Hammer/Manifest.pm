package Hammer::Manifest;

use strict;
use warnings;
use XML::Parser;
use Hammer::HelperFunc qw(findkey genxmltag);

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

  my $current_project = undef;

  my $parser = XML::Parser->new(
    Handlers => {
      Start => sub {
        my $parser = shift;
        my $tagname = shift;
        my %attr = @_;

        if (!$parser->context) # Ignore root element
          {
            die "$file: Root element should be called 'manifest'"
              unless $tagname eq "manifest";

            return;
          }
        elsif ($current_project) # Within project tag
          {
            if ($tagname eq "linkfile")
              {
                die "$file: <linkfile> not supported";
              }
            elsif ($tagname eq "copyfile")
              {
                die "$file: <copyfile> not supported";
              }
            elsif ($tagname eq "project")
              {
                die "$file: <project> in <project> not supported.\n";
              }
            elsif ($tagname eq "annotation")
              {
                die "$file: <annotation> not supported.\n";
              }
          }
        else # Outside of project tag
          {
            if ($tagname =~ /^(extend-|remove-|)(project|remote)$/)
              {
                my $type = $2;

                die "$file: Attribute 'name' missing in <$tagname ...>\n"
                  unless exists $attr{name};

                my $name = $attr{name};
                $name //= $attr{project_name} if $type eq "project";

                die "$file: Multiple <$tagname ...> with named '$name'\n"
                  if exists $self->{$tagname}->{$name};

                $current_project = $name if $tagname eq "project";

                $self->{$tagname}->{$name} = { %attr };
                return;
              }
            elsif ($tagname eq "default")
              {
                $self->set_default(\%attr);
                return;
              }
            elsif ($tagname eq "repo-hooks")
              {
                die "$file: <repo-hooks> not supported.";
              }
            elsif ($tagname eq "include")
              {
                die "$file: <include> not supported.";
              }
            elsif ($tagname eq "notice")
              {
                # Ignore notice
                return;
              }
          }

        die "$file: Unexpected tag <$tagname ...>\n";
      },
      End => sub {
        my ($parser, $tagname) = @_;

        $current_project = undef if $tagname eq "project";
      },
    },
  );

  $parser->parsefile($file);

  return $self;
}

sub toxml
{
  my $self = shift;
  my $path = shift;

  my @elements = ( '<!-- AUTOMATICALLY GENERATED. Edit at your own risk -->' );

  # Generate default tag if any
  if (my %defaults = %{$self->{default}})
    {
      push @elements, genxmltag("default", %defaults), "";
    }

  # Generate all *remote and *project tags
  foreach my $type (qw(remote project))
    {
      foreach my $prefix ("", "remove-", "extend-")
        {
          my $any = 0;
          my $tag = "${prefix}${type}";

          foreach my $name (sort keys %{$self->{$tag}})
            {
              $any = 1;

              my $instance = $self->{$tag}{$name};

              if ($type eq "project" && $name ne $instance->{name}) {
                $instance->{project_name} = $name;
              }

              push @elements, genxmltag($tag, %$instance);
            }

          push @elements, "" if $any;
        }
    }

  # Remove last empty line.
  pop @elements if @elements;

  # Generate XML lines
  my @xml = (
    '<?xml version="1.0" encoding="UTF-8" ?>',
    '<manifest>',
    (map { $_ ? s/^/  /rmg : "" } @elements),
    '</manifest>',
  );

  # Make it one string
  my $xml_raw = join "", map { "$_\n" } @xml;

  return $xml_raw;
}

sub writefile
{
  my ($self, $path) = @_;
  open(my $fh, ">", $path)
    or die "Unable to open file $path: $!";
  print $fh $self->toxml();
  close($fh);
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

        my $name = $removal->{$keyattr};

        die "$otherfp: Node <remove-$type ...> tries to remove non-existent $type '$name'"
          unless exists $self->{$type}{$name};

        delete $self->{$type}{$name};
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

        die "$otherfp: Node <extend-$type ...> tries to extend non-existent $type '$name'"
          unless exists $self->{$type}{$name};

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

# Reusable shortcut for adding something
sub _add {
  my ($self, $type, $required_attrs, $attrs) = @_;

  foreach my $attr (@$required_attrs)
    {
      die "Internal error: Trying to add '$type' without attribute '$attr'"
        unless $attrs->{$attr};
    }

  die "Internal error: Trying to add duplicate project '" . $attrs->{name} . "'"
    if exists $self->{$type}{$attrs->{name}};

  my $copy =  { %$attrs };

  $self->{$type}{$attrs->{name}} = $copy;

  return $copy;
}

sub add_project {
  my $self = shift;

  $self->_add('project', [ qw(name path) ], { @_ });
}

sub add_remote {
  my $self = shift;

  $self->_add('remote', [ qw(name fetch) ], { @_ });
}

sub set_default {
  my $self = shift;
  my ($defaults) = @_;

  $self->{default} = {
    %{$self->{default}},
    %$defaults,
  };
}

1;
