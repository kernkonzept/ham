package Hammer::HelperFunc;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(first any all findkey mapvalues genxmltag
                    priority_key_order);

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

sub priority_key_order {
  my ($hash, @priority_keys) = @_;

  @priority_keys = grep { exists $hash->{$_} } @priority_keys;

  my %priority_keys_lookup = map { $_ => 1 } @priority_keys;

  return @priority_keys, grep { !$priority_keys_lookup{$_} } sort keys %$hash;
}

# Helper for generating xml tags that look like this:
# <project name="foo"
#          path="bar"
#          revision="xyz" />
sub genxmltag {
  my $tagname = shift;
  my %attrs = @_;

  # Sanity checks
  die "quote found in attribute value"
    if any { m/"/ } values %attrs;

  die "invalid attr name"
    if any { m/[^a-z_]/ } keys %attrs;

  # Sort attributes
  my @attrorder = priority_key_order(\%attrs, "project_name", "name");

  # Process all attributes in chosen order
  my @xmlattrs = map { sprintf '%s="%s"', $_, $attrs{$_} } @attrorder;

  # Begin of tag
  my $xml = "<$tagname ";

  # Put each attribute after the first one in its own line, with indenting in
  # such a way that all attribute names start in the same text column.
  my $ident = " " x length($xml);
  $xml .= join("\n$ident", @xmlattrs);

  # End of tag
  $xml .= " />";

  return $xml;
}

1;
