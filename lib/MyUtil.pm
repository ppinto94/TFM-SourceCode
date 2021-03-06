#!/usr/bin/perl -w

# Package declaration:
package MyUtil;

# Import useful modules:
use Carp;
use strict;

use feature qq(say);

# Set package exportation properties:
BEGIN {
  # Load export module:
  require Exporter;

  # Set package version:
  our $VERSION = 1.0;

  # Inherit from Exporter to export subs and constants:
  our @ISA = qq(Exporter);

  # Default export:
  our @EXPORT = ();

  our @EXPORT_OK = qw( &TRUE
                       &FALSE
                       &KILLED
                       &GENERIC_ERR_CODE
                       &ERR_WRONG_ARRAY_REF
                       &ERR_WRONG_HASH_REF
                       &ERR_WRONG_SCALAR_REF
                       &ERR_UNRECOGNIZED_INPUT
                       &ERR_WRITE_PERMISSION_DENIED
                       &GENERIC_WARN_CODE
                       &DummySub
                       &SkipLines
                       &PushUnique
                       &ReadBoolean
                       &PurgeExtraSpaces
                       &GetPrettyLocalDate
                       &GetFileLayout
                       &LoadFileByLayout );

  our %EXPORT_TAGS = ( DEFAULT => [],
                       ALL     => \@EXPORT_OK );
}


# Constants:
# ---------------------------------------------------------------------------- #
# Boolean:
use constant {
  TRUE =>  1,
  FALSE => 0
};

# Killed status for subroutines:
use constant KILLED => -999;

# Common error codes:
use constant {
  GENERIC_ERR_CODE     => 30000,
  ERR_WRONG_HASH_REF   => 30001,
  ERR_WRONG_ARRAY_REF  => 30002,
  ERR_WRONG_SCALAR_REF => 30003,
  ERR_UNRECOGNIZED_INPUT => 30005,
  ERR_WRITE_PERMISSION_DENIED => 30004,
};

# Common warning codes:
use constant {
    GENERIC_WARN_CODE => 90000,
};

# Subroutines:
# ---------------------------------------------------------------------------- #
sub DummySub {
  return @_;
}

sub PurgeExtraSpaces {
  my ($string) = @_;

  $string =~ s/^ +| +$//;

  return $string;
}

sub PushUnique {
  my ( $ref_array, @values ) = @_;

  # Consistency check for array:
  unless (ref($ref_array) eq 'ARRAY') {
    croak "Not a valid array reference in ".
          "'PushUnique($ref_array, ".join(', ', @values).")'";
  }

  # Push each passed value if not present already:
  for my $push_value (@values) {
    unless (grep( /^$push_value$/, @{ $ref_array } )) {
      push( @$ref_array, $push_value );
    }
  }

  return TRUE;
}

sub ReadBoolean {
  my ($literal_boolean) = @_;

  if     ( $literal_boolean =~ m/TRUE/i  ) { return 1;     }
  elsif  ( $literal_boolean =~ m/FALSE/i ) { return 0;     }
  else                                     { return undef; }
}

sub SkipLines {
  my ($fh, $num_lines) = @_;

  my $useles_content = <$fh> for (1..$num_lines);

  return TRUE;
}

sub GetPrettyLocalDate {
  # No arguments for this function...

  # Set time:
  my ($ss,$mm,$hh,$dd,$mo,$year,$wday,$yday,$isdst) = localtime();

  # Apply year offset:
  $year += ($year < 80) ? 2000 : 1900;

  # Date string:
  my $date =
    sprintf("%04d/%02d/%02d %02d:%02d:%02d", $year, $mo+1, $dd, $hh, $mm, $ss);

  return $date;
}

sub GetFileLayout {
  my ($file_path, $head_line, $delimiter) = @_;

  my $ref_file_layout = {};

  $ref_file_layout->{FILE}{ PATH      } = $file_path;
  $ref_file_layout->{FILE}{ HEAD      } = $head_line;
  $ref_file_layout->{FILE}{ DELIMITER } = $delimiter;

  my $fh; open($fh, '<', $file_path) or die "Could not open $file_path. $!";

  while (my $line = <$fh>) {
    if ($. == $head_line) {

      my @head_items = split(/[\s$delimiter]+/, $line);

      for my $index (keys @head_items) {
        $ref_file_layout->{ITEMS}{$head_items[$index]}{INDEX} = $index;
      }

      last;

    }
  }

  close($fh);

  return $ref_file_layout;
}

sub LoadFileByLayout {
  my ($ref_file_layout) = @_;

  # Retrieve file properties:
  my ( $file_path,
       $head_line,
       $delimiter ) = ( $ref_file_layout->{FILE}{PATH},
                        $ref_file_layout->{FILE}{HEAD},
                        $ref_file_layout->{FILE}{DELIMITER} );

  my $ref_array = [];

  my $fh; open($fh, '<', $file_path) or die "Could not open $!";

  SkipLines($fh, $head_line);

  while (my $line = <$fh>) {
    push( @{$ref_array}, [split(/$delimiter/, $line)] );
  }

  close($fh);

  return $ref_array;
}

1;
