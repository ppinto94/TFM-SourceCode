#!/usr/bin/perl -w

# TODO: SCRIPT DESCRIPTION GOES HERE:

# Package declaration:
package NeQuickMode;

# ---------------------------------------------------------------------------- #
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

  # Define constants to export:
  our @EXPORT_CONST = qw( &REF_CCIR_HASH
                          &REF_MODIP_MAP );

  # Define subroutines to export:
  our @EXPORT_SUB   = qw( &ComputeMODIP
                          &ComputeEffectiveIonisationLevel
                          &ComputeNeQuickModelParameters
                          &IntegrateNeQuickSlantTEC
                          &IntegrateNeQuickVerticalTEC );

  # Merge constants$rec_lon subroutines:
  our @EXPORT_OK = (@EXPORT_CONST, @EXPORT_SUB);

  # Define export tags:
  our %EXPORT_TAGS = ( ALL         => \@EXPORT_OK,
                       DEFAULT     => \@EXPORT,
                       CONSTANTS   => \@EXPORT_CONST,
                       SUBROUTINES => \@EXPORT_SUB );

}

# ---------------------------------------------------------------------------- #
# Load bash enviroments:

use lib $ENV{ ENV_ROOT };
use Enviroments qq(:CONSTANTS);

# ---------------------------------------------------------------------------- #
# Import Modules:

use Carp;
use strict; # enables strict syntax...

use Math::Trig;
use Scalar::Util qq(looks_like_number); # scalar utility...

use Data::Dumper; # enables pretty print...
use feature qq(say); # print adding carriage return...

# Import configuration and common interface module:
use lib SRC_ROOT_PATH;
use GeneralConfiguration qq(:ALL);

# Import dedicated libraries:
use lib LIB_ROOT_PATH;
use MyUtil   qq(:ALL); # useful subs and constants...
use MyMath   qq(:ALL); # useful mathematical methods...
use MyPrint  qq(:ALL); # error and warning utilities...
use Geodetic qq(:ALL); # geodesy methods and constants...
use TimeGNSS qq(:ALL); # GNSS time transforming utilities...

# ---------------------------------------------------------------------------- #
# Preliminary MODIP & CCIR file mapping:

# File configuration:
use constant MODIP_FILE_PATH     => NEQUICK_DAT_PATH.qq(modipNeQG_wrapped.txt);
use constant CCIR_BASE_FILE_NAME => qq(ccir);
use constant CCIR_FILE_EXTENSION => qq(.txt);

# CCIR line template:
use constant CCIR_LINE_TEMPLEATE => 'A16'x4;

# CCIR array arrangement:
use constant {
  CCIR_F2_ROW_DIM  => 2,
  CCIR_F2_COL_DIM  => 76,
  CCIR_F2_DEP_DIM  => 13,
  CCIR_FM3_ROW_DIM => 2,
  CCIR_FM3_COL_DIM => 49,
  CCIR_FM3_DEP_DIM => 9,
};

# MODIP array arrangement:
use constant {
  MODIP_ROW_DIM => 39,
  MODIP_COL_DIM => 39,
};

sub LoadMODIPFile {
  my ($modip_file_path) = @_;

  # Init array reference for storing MODIP map matrix:
  my $ref_modip_map = [];

  # Open file:
  my $fh; open($fh, '<', $modip_file_path) or croak $!;

  my @modip_array;
  while (my $line = <$fh>) {
    chomp $line;
    push( @modip_array, split(/ +/, PurgeExtraSpaces($line)) );
  }

  # Close file:
  close($fh);

  # Build up MODIP map:
  for (my $i = 0; $i < MODIP_ROW_DIM; $i += 1) {
    for (my $j = 0; $j < MODIP_COL_DIM; $j += 1) {
      $ref_modip_map->[$i][$j] = shift @modip_array;
    }
  }

  return $ref_modip_map;
}

sub LoadCCIRFiles {
  my ($ccir_data_path) = @_;

  # Init CCIR hash to be returned:
  my $ref_ccir_hash = {};

  # Iterate over all year months:
  for my $month (1..12) {

    # Set CCIR hash entry for month:
    $ref_ccir_hash->{$month}{ F2  } = [];
    $ref_ccir_hash->{$month}{ FM3 } = [];

    # Build file path:
    my $ccir_file_path =
       NEQUICK_DAT_PATH.CCIR_BASE_FILE_NAME.(10 + $month).CCIR_FILE_EXTENSION;

    # Open CCIR month file:
    my $fh; open($fh, '<', $ccir_file_path) or croak $!;

    # Load file in memory as single line string:
    my @ccir_array;
    while (my $line = <$fh>) {
      chomp $line;
      push( @ccir_array,
            map { PurgeExtraSpaces($_) } unpack(CCIR_LINE_TEMPLEATE, $line) );
    }

    # Close CCIR month file:
    close($fh);

    # Build up F2 matrix from CCIR array:
    for (my $i = 0; $i < CCIR_F2_ROW_DIM; $i += 1) {
      for (my $j = 0; $j < CCIR_F2_COL_DIM; $j += 1) {
        for (my $k = 0; $k < CCIR_F2_DEP_DIM; $k += 1) {
          $ref_ccir_hash->{$month}{F2}[$i][$j][$k] = shift @ccir_array;
        }
      }
    }

    # Build up FM3 matrix from CCIR array:
    for (my $i = 0; $i < CCIR_FM3_ROW_DIM; $i += 1) {
      for (my $j = 0; $j < CCIR_FM3_COL_DIM; $j += 1) {
        for (my $k = 0; $k < CCIR_FM3_DEP_DIM; $k += 1) {
          $ref_ccir_hash->{$month}{FM3}[$i][$j][$k] = shift @ccir_array;
        }
      }
    }

  } # end for $month

  return $ref_ccir_hash;
}


# ---------------------------------------------------------------------------- #
# Constants:

use constant {
  MIN_EFF_IONO_LEVEL => 0,
  MAX_EFF_IONO_LEVEL => 400,
  DEFAULT_EFF_IONO_LEVEL => 63.7,
};

use constant ZENIT_ANGLE_DAY_NIGHT_TRANSITION => 86.23292796211615; # [deg]

use constant REF_CCIR_HASH => LoadCCIRFiles( DAT_ROOT_PATH   );
use constant REF_MODIP_MAP => LoadMODIPFile( MODIP_FILE_PATH );

# ---------------------------------------------------------------------------- #
# Public Subroutines: #

sub ComputeMODIP {
  my ($lat, $lon) = @_;

  # Preliminary --> Transform latitude and longitude to degree angle format:
  $lat *= RADIANS_TO_DEGREE;
  $lon *= RADIANS_TO_DEGREE;

  # Init MODIP value to be returned:
  my $modip;

  # Latitude extreme cases:
  if      ( $lat ==  90 ) {
    $modip =  90;
  } elsif ( $lat == -90 ) {
    $modip = -90;
  } else { # For the rest of the cases, MODIP interpolation is performed:

    # Longitude grid index:
    my $lon_index  = int( ($lon + 180)/10 ) - 2;
       $lon_index += 36 if $lon_index < 0;
       $lon_index -= 36 if $lon_index > 33;

    # Tipificate (arange among 0 to 1) latitude point to interpolate:
    my $aux1 = ($lat + 90)/5 + 1;
    my $x    = $aux1 - int($aux1);

    # Latitude grid index:
    my $lat_index = int($aux1) - 2;

    # Build buffer grid:
    # NOTE: buffer grid is 4x4 MODIP imported points
    my $ref_modip_buffer_grid = [];

    for my $k (0..3) {
      for my $j (0..3) {
        $ref_modip_buffer_grid->[$j][$k] =
          REF_MODIP_MAP->[$lat_index + $j][$lon_index + $k];
      }
    }

    # Interpolate on latitude grid buffer:
    my @z_interpolated_lat;
    for my $k (0..3) {
      push ( @z_interpolated_lat,
             ThirdOrderInterpolation($ref_modip_buffer_grid->[0][$k],
                                     $ref_modip_buffer_grid->[1][$k],
                                     $ref_modip_buffer_grid->[2][$k],
                                     $ref_modip_buffer_grid->[3][$k], $x) );
    }

    # Tipificate (arange among 0 to 1) longitude point to interpolate:
    my $aux2 = ($lon + 180)/10;
    my $y    = $aux2 - int($aux2);

    # Interpolate on longitude grid buffer using interpolation performed on
    # latitude buffer in order to retrive MODIP:
    $modip = ThirdOrderInterpolation( @z_interpolated_lat, $y );

  }

  # MODIP is returned in radians:
  return $modip*DEGREE_TO_RADIANS;
}

sub ComputeEffectiveIonisationLevel {
  my ( $ref_iono_coeff, $modip ) = @_;

  # De-reference iono coefficient array:
  my ( $a0, $a1, $a2 ) = @{ $ref_iono_coeff };

  # MODIP is transformed to degree angle format:
  $modip *= RADIANS_TO_DEGREE;

  # Init effective ionisation level value to return:
  my $eff_iono_level;

  if ( $a0 == 0 && $a1 == 0 && $a2 == 0 ) {
    $eff_iono_level = DEFAULT_EFF_IONO_LEVEL;
  } else {
    $eff_iono_level = $a0 + $a1*$modip + $a2*$modip**2;
  }

  # Bound effective ionisation level according to estipulated range:
  if ( $eff_iono_level < MIN_EFF_IONO_LEVEL  )
     { $eff_iono_level = MIN_EFF_IONO_LEVEL; }
  if ( $eff_iono_level > MAX_EFF_IONO_LEVEL  )
     { $eff_iono_level = MAX_EFF_IONO_LEVEL; }

  # In addition, compute Effective sunspot number:
  my $eff_sunspot_number =
    (167273 + ($eff_iono_level - DEFAULT_EFF_IONO_LEVEL)*1123.6)**0.5 - 408.99;

  return ($eff_iono_level, $eff_sunspot_number);
}

sub ComputeNeQuickModelParameters {
  my ( $lat, $lon, $modip,
       $month, $ut_time, $local_time,
       $eff_iono_level, $eff_sunspot_number ) = @_;

  # Preliminary:
    # Angle formats are converted to degrees:
    ($lat, $lon, $modip) = map{ $_*RADIANS_TO_DEGREE } ($lat, $lon, $modip);

  # Init hash to store model parameters:
  my $ref_model_parameters = {};

  # ******************** #
  # 1. Solar Parameters: #
  # ******************** #

    # 1.a. Compute Solar Declination:
    my ($sin_delta_sun, $cos_delta_sun) = # [n/a], [n/a]
      ComputeSolarDeclination( $month, $ut_time );

    # 1.b. Compute Solar Zenit Angle:
    my ($solar_zenit_angle) = # [deg]
      ComputeSolarZenitAngle( $lat, $local_time,
                              $sin_delta_sun, $cos_delta_sun );

    # 1.c. Compute Effective Solar Zenit Angle:
    my ($eff_solar_zenit_angle) = # [deg]
      ComputeEffSolarZenitAngle( $solar_zenit_angle,
                                 ZENIT_ANGLE_DAY_NIGHT_TRANSITION  );

  # ******************** #
  # 2. Model Parameters: #
  # ******************** #

    # 2.a. E ionosphere layer parameters:
    #      f0E --> E layer critical frequency [MHz]
    #      NmE --> E layer maximum density    [10e11m-3]
      ComputeELayerParameters( $lat, $month,
                               $eff_iono_level,
                               $eff_solar_zenit_angle,
                               $ref_model_parameters );


    # 2.b. F2 ionosphere layer parameters:
    #      f0F2 --> F2 layer critical frequency [MHz]
    #      NmF2 --> F2 layer maximum density    [10e11m-3]
    #      M(3000)F2 --> F2 layer transmission factor [??]
      ComputeF2LayerParameters( $lat, $lon, $modip,
                                $month, $ut_time,
                                $eff_sunspot_number,
                                $ref_model_parameters );

    # 2.c. F1 ionosphere layer parameters:
    #      f0F1 --> F1 layer critical frequency [MHz]
    #      NmF1 --> F1 layer maximum density    [10e11m-3]
      ComputeF1LayerParameters( $ref_model_parameters );

    # 2.d. Layer maximum density heights:
    #      hME  --> E  layer maximum density height [km]
    #      hMF2 --> F2 layer maximum density height [km]
    #      hMF1 --> F1 layer maximum density height [km]
      ComputeLayerMaxDensityHeight( $ref_model_parameters );

    # 2.e. Ionosphere layer thickness parameters:
    #      B2BOT        --> F2 bottom layer thickness [km]
    #      BETOP, BEBOT --> E  top and bottom layer thickness [km]
    #      B1TOP, B1BOT --> F1 top and bottom layer thickness [km]
      ComputeLayerThickness( $ref_model_parameters );

    # 2.f. Ionosphere layers amplitude:
    #      A1 --> F2 layer amplitude [10e11m-3]
    #      A2 --> F1 layer amplitude [10e11m-3]
    #      A3 --> E  layer amplitude [10e11m-3]
      ComputeLayerAmplitude( $ref_model_parameters );

    # 2.g. k --> Shape Parameter: [n/a]
      ComputeShapeParameter( $month,
                             $eff_sunspot_number,
                             $ref_model_parameters );

    # 2.h. H0 --> Topside thickness parameter: [km]
      ComputeTopsideThickness( $ref_model_parameters );


  return $ref_model_parameters;
}

sub IntegrateNeQuickSlantTEC {}

sub IntegrateNeQuickVerticalTEC {}

# ---------------------------------------------------------------------------- #
# Private Subroutines: #

# ************************************************** #
# First Level Subroutines:                           #
#   Subroutines called from main public subroutines. #
# ************************************************** #
sub ComputeSolarDeclination {
  my ( $month, $ut_time ) = @_;

  # Day of the year (at th middle of the month??):
  my $doy = 30.5*$month - 15;

  # Compute time [days]:
  my $time = $doy + (18 - $ut_time)/24;

  # Solar's declination argument:
  my $aux1 = (0.9856*$time - 3.289)*DEGREE_TO_RADIANS;
  my $aux2 = (1.916*sin($aux1) + 0.02*sin(2*$aux1) + 282.634)*DEGREE_TO_RADIANS;
  my $argument = $aux1 + $aux2;

  # Solar declination sinus and cosine components:
  my $sin_delta_sun = 0.39782*sin($argument);
  my $cos_delta_sun = (1 - $sin_delta_sun**2)**0.5;

  return ( $sin_delta_sun, $cos_delta_sun );
}

sub ComputeSolarZenitAngle {
  my ($lat, $local_time, $sin_delta_sun, $cos_delta_sun) = @_;

  # Preliminary:
    # Latitude is transformed o radians:
    $lat *= DEGREE_TO_RADIANS;

  # Solar zenit angle cosine component:
  my $cos_solar_zenit_angle = sin($lat)*$sin_delta_sun +
                              cos($lat)*$cos_delta_sun +
                              cos( pi/12*(12 - $local_time) );

  my $solar_zenit_angle = RADIANS_TO_DEGREE*
                          atan2( (1 - $cos_solar_zenit_angle**2)**0.5,
                                 $cos_solar_zenit_angle );

  return $solar_zenit_angle;
}

sub ComputeEffSolarZenitAngle {
  my ($solar_zenit_angle, $zenit_angle_day_night_transition) = @_;

  my $aux = exp( 12*($solar_zenit_angle -
                     $zenit_angle_day_night_transition) );

  my $denominator = 1 + $aux;
  my $nominator   = $solar_zenit_angle +
                    ( 90 - 0.24*exp(20 - 0.2*$solar_zenit_angle) )*$aux;

  # Effective solar zenit angle is computed as the following fraction:
  return $nominator/$denominator;
}

sub ComputeELayerParameters {
  my ($lat, $month,
      $eff_iono_level, $eff_solar_zenit_angle, $ref_model_parameters) = @_;

  # Init model parameters to be computed:
  my ($e_critical_freq, $e_max_density);

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{E_LAYER}{ MAX_DENSITY   } = $e_max_density;
  $ref_model_parameters->{E_LAYER}{ CRITICAL_FREQ } = $e_critical_freq;

  return TRUE;
}

sub ComputeF2LayerParameters {
  my ($lat, $lon, $modip, $month, $ut_time,
      $eff_sunspot_number, $ref_model_parameters) = @_;

  # Init model parameters to be computed:
  my ($f2_critical_freq, $f2_max_density, $f2_trans_fact);

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{F2_LAYER}{ MAX_DENSITY         } = $f2_critical_freq;
  $ref_model_parameters->{F2_LAYER}{ CRITICAL_FREQ       } = $f2_critical_freq;
  $ref_model_parameters->{F2_LAYER}{ TRANSMISSION_FACTOR } = $f2_trans_fact;

  return TRUE;
}

sub ComputeF1LayerParameters {
  my ($ref_model_parameters) = @_;

  # Necessary model parameters for sub:
  my ( $e_critical_freq,
       $f2_critical_freq ) =
     ( $ref_model_parameters->{ E_LAYER  }{CRITICAL_FREQ},
       $ref_model_parameters->{ F2_LAYER }{CRITICAL_FREQ} );

  # Init model parameters to be computed:
  my ($f1_critical_freq, $f1_max_density);

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{F1_LAYER}{ MAX_DENSITY   } = $f1_max_density;
  $ref_model_parameters->{F1_LAYER}{ CRITICAL_FREQ } = $f1_critical_freq;

  return TRUE;
}

sub ComputeLayerMaxDensityHeight {
  my ($ref_model_parameters) = @_;

  # Necessary model parameters for sub:
  my ( $e_critical_freq,
       $f2_critical_freq,
       $f2_trans_fact ) =
     ( $ref_model_parameters->{ E_LAYER  }{ CRITICAL_FREQ       },
       $ref_model_parameters->{ F2_LAYER }{ CRITICAL_FREQ       },
       $ref_model_parameters->{ F2_LAYER }{ TRANSMISSION_FACTOR } );

  # Init model parameters to be computed:
  my ($e_max_density_height,
      $f1_max_density_height,
      $f2_max_density_height);

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->
    { E_LAYER  }{MAX_DENSITY_HEIGHT} = $e_max_density_height;
  $ref_model_parameters->
    { F1_LAYER }{MAX_DENSITY_HEIGHT} = $f1_max_density_height;
  $ref_model_parameters->
    { F2_LAYER }{MAX_DENSITY_HEIGHT} = $f2_max_density_height;

  return TRUE;
}

sub ComputeLayerThickness {
  my ($ref_model_parameters) = @_;

  # Necessary model parameters for sub:
    # Maximum layer density:
    my ( $f2_max_density,
         $f2_critical_freq,
         $f2_trans_fact, ) =
       ( $ref_model_parameters->{F2_LAYER}{ MAX_DENSITY         },
         $ref_model_parameters->{F2_LAYER}{ CRITICAL_FREQ       },
         $ref_model_parameters->{F2_LAYER}{ TRANSMISSION_FACTOR } );
    # Maximum layer density height:
    my ( $e_max_density_height,
         $f1_max_density_height,
         $f2_max_density_height ) =
       ( $ref_model_parameters->{ E_LAYER  }{MAX_DENSITY_HEIGHT},
         $ref_model_parameters->{ F1_LAYER }{MAX_DENSITY_HEIGHT},
         $ref_model_parameters->{ F2_LAYER }{MAX_DENSITY_HEIGHT} );

  # Init model parameters to be computed:
  my ($f2_bot_thick, $f1_top_thick, $f1_bot_thick, $e_top_thick, $e_bot_thick);

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{ E_LAYER  }{TOP_THICKNESS} = $e_top_thick;
  $ref_model_parameters->{ E_LAYER  }{BOT_THICKNESS} = $e_bot_thick;
  $ref_model_parameters->{ F1_LAYER }{TOP_THICKNESS} = $f1_top_thick;
  $ref_model_parameters->{ F1_LAYER }{BOT_THICKNESS} = $f1_bot_thick;
  $ref_model_parameters->{ F2_LAYER }{BOT_THICKNESS} = $f2_bot_thick;

  return TRUE;
}

sub ComputeLayerAmplitude {
  my ($ref_model_parameters) = @_;

  # Necessary model parameters:
    # Maximum layer density:
    my ( $e_max_density,
         $f1_max_density,
         $f2_max_density ) =
       ( $ref_model_parameters->{ E_LAYER  }{MAX_DENSITY},
         $ref_model_parameters->{ F1_LAYER }{MAX_DENSITY},
         $ref_model_parameters->{ F2_LAYER }{MAX_DENSITY} );
    # Maximum layer density height
    my ( $e_max_density_height,
         $f1_max_density_height,
         $f2_max_density_height ) =
       ( $ref_model_parameters->{ E_LAYER  }{MAX_DENSITY_HEIGHT},
         $ref_model_parameters->{ F1_LAYER }{MAX_DENSITY_HEIGHT},
         $ref_model_parameters->{ F2_LAYER }{MAX_DENSITY_HEIGHT} );
    # Layer top and bottom thickness:
    my ( $f2_bot_thick,
         $e_top_thick, $e_bot_thick,
         $f1_top_thick, $f1_bot_thick ) =
       ( $ref_model_parameters->{ F2_LAYER }{BOT_THICKNESS},
         $ref_model_parameters->{ E_LAYER  }{TOP_THICKNESS},
         $ref_model_parameters->{ E_LAYER  }{BOT_THICKNESS},
         $ref_model_parameters->{ F1_LAYER }{TOP_THICKNESS},
         $ref_model_parameters->{ F1_LAYER }{BOT_THICKNESS} );
    # F1 critical frequency:
    my $f1_critical_freq = $ref_model_parameters->{F1_LAYER}{CRITICAL_FREQ};


  # Init model parameters to be computed:
  my ($e_amplitude, $f1_amplitude, $f2_amplitude);

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{ E_LAYER  }{AMPLITUDE} = $e_amplitude;
  $ref_model_parameters->{ F1_LAYER }{AMPLITUDE} = $f1_amplitude;
  $ref_model_parameters->{ F2_LAYER }{AMPLITUDE} = $f2_amplitude;

  return TRUE;
}

sub ComputeShapeParameter {
  my ($month, $eff_sunspot_number, $ref_model_parameters) = @_;

  # Necessary model parameters:
  my ( $f2_bot_thick,
       $f2_max_density,
       $f2_max_density_height ) =
     ( $ref_model_parameters->{F2_LAYER}{ BOT_THICKNESS      },
       $ref_model_parameters->{F2_LAYER}{ MAX_DENSITY        },
       $ref_model_parameters->{F2_LAYER}{ MAX_DENSITY_HEIGHT } );

  # Init model parameter to be computed:
  my $shape_parameter;

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{SHAPE_PARAMETER} = $shape_parameter;

  return TRUE;
}

sub ComputeTopsideThickness {
  my ($ref_model_parameters) = @_;

  # Necessary model parameters:
  my $shape_parameter = $ref_model_parameters->{SHAPE_PARAMETER};
  my $f2_bot_thick    = $ref_model_parameters->{F2_LAYER}{BOT_THICKNESS};

  # Init model parameter to be computed:
  my $topside_thick;

  # Computation steps:

  # Append computed parameters to model hash:
  $ref_model_parameters->{TOPSIDE_THICKNESS} = $topside_thick;

  return TRUE;
}

# ******************************************************** #
# Second Level Subroutines:                                #
#   Subroutines called from 1st level private subroutines. #
# ******************************************************** #

# ******************************************************** #
# Third Level Subroutines:                                 #
#   Subroutines called from 2nd level private subroutines. #
# ******************************************************** #

# ******************************************************** #
# Forth Level Subroutines:                                 #
#   Subroutines called from 3rd level private subroutines. #
# ******************************************************** #

TRUE;
