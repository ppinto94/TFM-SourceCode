#!/usr/bin/perl -w

# Package declaration:
package ErrorSource;


# SCRIPT DESCRIPTION GOES HERE:

# Import Modules:
# ---------------------------------------------------------------------------- #
use strict;   # enables strict syntax...

use PDL;
use PDL::GSL::INTERP;
use PDL::Constants qw(PI);
use Scalar::Util qq(looks_like_number); # scalar utility...

use feature qq(say); # print adding carriage return...
use Data::Dumper;    # enables pretty print...

# Import configuration and common interface module:
use lib qq(/home/ppinto/TFM/src/);
use GeneralConfiguration qq(:ALL);

# Import dedicated libraries:
use lib qq(/home/ppinto/TFM/src/lib/); # TODO: this should be an enviroment!
use MyUtil   qq(:ALL); # useful subs and constants...
use MyMath   qq(:ALL); # useful mathematical methods...
use MyPrint  qq(:ALL); # error and warning utilities...
use Geodetic qq(:ALL); # geodesy methods and constants...
use TimeGNSS qq(:ALL); # GNSS time transforming utilities...

# Set package exportation properties:
# ---------------------------------------------------------------------------- #
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
  our @EXPORT_CONST = qw(  );

  # Define subroutines to export:
  our @EXPORT_SUB   = qw( &ComputeTropoSaastamoinenDelay
                          &ComputeIonoKlobucharDelay
                          &ComputeIonoNeQuickDelay );

  # Merge constants$rec_lon subroutines:
  our @EXPORT_OK = (@EXPORT_CONST, @EXPORT_SUB);

  # Define export tags:
  our %EXPORT_TAGS = ( ALL         => \@EXPORT_OK,
                       DEFAULT     => \@EXPORT,
                       CONSTANTS   => \@EXPORT_CONST,
                       SUBROUTINES => \@EXPORT_SUB );

}


# ---------------------------------------------------------------------------- #
# Constants:
# ---------------------------------------------------------------------------- #
use constant SAASTAMOINEN_B_DOMAIN =>
  [0.0e3, 0.5e3, 1.0e3, 1.5e3, 2.0e3, 2.5e3, 3.0e3, 4.0e3, 5.0e3]; # [m]
use constant SAASTAMOINEN_B_RANGE  =>
  [1.156, 1.079, 1.006, 0.938, 0.874, 0.813, 0.757, 0.654, 0.563]; # [m]

# ---------------------------------------------------------------------------- #
# Subroutines:
# ---------------------------------------------------------------------------- #

# Public Subroutines: #
# ............................................................................ #
sub ComputeTropoSaastamoinenDelay {
  my ($zenital, $height) = @_; # [rad], [m]

  # Computation sequence:
    # Temperature estimation [K]:
    my $temp = 291.15 - 0.0065*$height;

    # Pressure estimation [mb]:
    my $press = 1013.25*(1 - 0.000065*$height)**(5.225);

    # Humidity estimation [%]:
    my $humd = 50*exp(-1*0.0006396*$height);

    # Partial pressure of water vapor [mb]:
    my $pwv = ($humd*0.01)*exp(-37.2465 + 0.213166 - (0.000256908*$temp**2));

    # Interpolation of 'B' [m] --> correction acounting for elipsoidal height:
      # Define as PDL piddles B parameter's domain and range
      my $pdl_b_range  = pdl SAASTAMOINEN_B_RANGE;
      my $pdl_b_domain = pdl SAASTAMOINEN_B_DOMAIN;

      # Define B interpolation function (linear interpolation):
      my $pdl_interp_func = PDL::GSL::INTERP->init('linear',
                                                   $pdl_b_domain,
                                                   $pdl_b_range);

      # Interpolate B parameter:
      my $b_prm = $pdl_interp_func->eval($height);

  # Troposhperic delay correction is computed as follows:
    # Auxiliar variables:
    my $aux1 = (0.002277/cos($zenital));
    my $aux2 = (1255/$temp) + 0.05;
    # Computed delay:
    my $dtropo = $aux1*($press + $aux2*$pwv - $b_prm*(tan($zenital))**2);

    # PrintTitle3(*STDOUT, "Troposphere Saastamoinen computed parameters:");
    # PrintBulletedInfo(*STDOUT, "\t\t - ",
    #   "Temperature = $temp",
    #   "Pressure    = $press",
    #   "Humidity    = $humd",
    #   "Water vapor's pressure = $pwv",
    #   "'B' Parameter interpolated = $b_prm",
    #   "Tropo correction  = $dtropo");

  # Return tropospheric delay:
  # NOTE: apply piddle to scalar transformation
  return sclr($dtropo); # [m]
}

sub ComputeIonoKlobucharDelay {
  my ( $gps_epoch,
       $leap_sec,
       $ref_sat_xyz,
       $ref_rec_lat_lon_h,
       $azimut, $elevation,
       $ref_iono_alpha, $ref_iono_beta,
       $carrier_freq_f1, $carrier_freq_f2, $elip ) = @_;

  # De-reference input arguments:
    # GPS Alpha and Beta coefficients:
    my @iono_alpha_prm = @{ $ref_iono_alpha };
    my @iono_beta_prm  = @{ $ref_iono_beta  };

    # Receiver's geodetic position:
    my ($rec_lat, $rec_lon, $rec_helip) = @{ $ref_rec_lat_lon_h };

  # Preliminary steps:
    # Elevation from [rad] --> [semicircles]:
    $elevation /= PI;

    # Receiver latitude and longitude: [rad] --> [semicircles]
    $rec_lat /= PI; $rec_lon /= PI;

    # Time transfomation: GPS --> Num_week, Num_day, ToW [s]
    my ($week, $day, $tow) = GPS2ToW($gps_epoch);

  # Computation sequence:
    # Compute earth center angle [semicircles]:
    my $earth_center_angle = (0.0137/($elevation + 0.11)) - 0.022;

    # Compute IPP's geodetic coordinates:
      # IPP's latitude [semicircles]:
      my $ipp_lat = $rec_lat + $earth_center_angle*cos($azimut);

        # Latitude boundary protection:
        $ipp_lat =    0.416 if ($ipp_lat >    0.416);
        $ipp_lat = -1*0.416 if ($ipp_lat < -1*0.416);

      # IPP's longitude [semicircles]:
      # NOTE: Cosine's argument is transformaed [semicircles] --> [rad]
      my $ipp_lon =
         $rec_lon + ( $earth_center_angle*sin($azimut) )/( cos($ipp_lat*PI) );

      # IPP's geomagnetic latitude [semicircles]:
      # NOTE: Sinus's argument is transformed [semicircles] --> [rad]
      my $geomag_lat_ipp = $ipp_lat + 0.064*cos( ($ipp_lon - 1.617)*PI );

      # Local time at IPP [s]:
      my $ipp_time  = SECONDS_IN_DAY/2 * $ipp_lon + $tow;
         $ipp_time -= SECONDS_IN_DAY if ($ipp_time >= SECONDS_IN_DAY);
         $ipp_time += SECONDS_IN_DAY if ($ipp_time < 0.0 );

    # Compute ionospheric delay amplitude [s]:
    my $iono_amplitude  = 0;
       $iono_amplitude += $iono_alpha_prm[$_]*$geomag_lat_ipp**$_ for (0..3);
       $iono_amplitude  = 0 if ($iono_amplitude < 0);

    # Compute ionospheric delay period [s]:
    my $iono_period  = 0;
       $iono_period += $iono_beta_prm[$_]*$geomag_lat_ipp**$_ for (0..3);
       $iono_period  = 72000 if ($iono_period < 72000);

    # Compute ionospheric delay phase [rad]:
    my $iono_phase = ( 2*PI*($ipp_time - 50400) ) / $iono_period;

    # Compute slant factor delay [m¿?]:
    my $slant_fact = 1.0 + 16.0*(0.53 - $elevation)**3;

    # Compute ionospheric time delay for standard frequency [m]:
    my $iono_delay_f1;
    # Depending of the absolue magnitude of the phase delay, delay for L1 signal
    # is computed as:
    if ( abs($iono_phase) <= 1.57 ) {
      my $aux1       = 1 - ($iono_phase**2/2) + ($iono_phase**4/24);
      $iono_delay_f1 = ( 5.1e-9 + $iono_amplitude*$aux1 )*$slant_fact;
    } elsif ( abs($iono_phase) >= 1.57 ) {
      $iono_delay_f1 = 5.1e-9*$slant_fact;
    }

    # Transform ionospheric time delay into meters:
    $iono_delay_f1 *= SPEED_OF_LIGHT;

    # Compute ionospheric time delay for configured frequency [m]:
    my $iono_delay_f2 =
      ( ($carrier_freq_f1/$carrier_freq_f2)**2 )*$iono_delay_f1;

    # PrintTitle3(*STDOUT, "Ionosphere Klobuchar computed parameters:");
    # PrintBulletedInfo(*STDOUT, "\t\t - ",
    #   "Earth center angle = $earth_center_angle",
    #   "IPP's lat    = $ipp_lat",
    #   "IPP's lon    = $ipp_lon",
    #   "IPP's GM lat = $geomag_lat_ipp",
    #   "Iono delay amplitude = $iono_amplitude",
    #   "Iono delay period    = $iono_period",
    #   "Slant factor         = $slant_fact",
    #   "Iono delay at L1     = $iono_delay_f1",
    #   "Iono delay at L2     = $iono_delay_f2");


  # Return ionospheric delays for both frequencies:
  return ($iono_delay_f1, $iono_delay_f2)
} # end sub ComputeIonoKlobucharDelay

sub ComputeIonoNeQuickDelay {
  my ( $gps_epoch,
       $leap_sec,
       $ref_sat_xyz,
       $ref_rec_lat_lon_h,
       $azimut, $elevation,
       $ref_iono_coeff, $ref_null_coeff,
       $carrier_freq_f1, $carrier_freq_f2, $elip ) = @_;

  # ***************** #
  # Preliminary steps #
  # ***************** #

    # De-reference input arguments:
    my ( $sat_x,   $sat_y,   $sat_z     ) = @{ $ref_sat_xyz       };
    my ( $rec_lat, $rec_lon, $rec_helip ) = @{ $ref_rec_lat_lon_h };

    # Retrieve Hour and Month from UTC time:
    my ( $year, $month, $day,
         $hour, $min,   $sec ) = GPS2Date( $gps_epoch - $leap_sec );

    # Compute geodetic coordinates for satellite:
    my ( $sat_lat,
         $sat_lon,
         $sat_helip ) = ECEF2Geodetic( $sat_x, $sat_y, $sat_z, $elip );


  # ********************************* #
  # NeQuick delay computation routine #
  # ********************************* #

    # ******************** #
    # 1. MODIP computation #
    # ******************** #

    # ***************************************** #
    # 2. Effective Ionisation Level computation #
    # ***************************************** #

    # ********************************** #
    # 3. NeQuick G Slant TEC integration #
    # ********************************** #

    # *********************************************** #
    # 4. Delay computation for configured observation #
    # *********************************************** #


} # end sub ComputeIonoNeQuickDelay


# Private Subroutines: #
# ............................................................................ #


TRUE;
