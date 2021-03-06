#!/usr/bin/perl -w

# TODO: Package description goes here...

# Package declaration:
package PlotPosPerformance;

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
  our @EXPORT_CONST = qw(  );

  # Define subroutines to export:
  our @EXPORT_SUB   = qw( &PlotReceiverPosition
                          &PlotAccuracyPerformance
                          &PlotIntegrityPerformance );

  # Merge constants and subroutines:
  our @EXPORT_OK = (@EXPORT_CONST, @EXPORT_SUB);

  # Define export tags:
  our %EXPORT_TAGS = ( ALL         => \@EXPORT_OK,
                       DEFAULT     => \@EXPORT,
                       CONSTANTS   => \@EXPORT_CONST,
                       SUBROUTINES => \@EXPORT_SUB );
}

# ---------------------------------------------------------------------------- #
# Import common perl modules:

use Carp;         # advanced warning and failure raise...
use strict;       # strict syntax and common mistakes advisory...

use Data::Dumper;       # var pretty print...
use feature qq(say);    # print adding line jump...
use feature qq(switch); # advanced switch statement...

# Perl Data Language (PDL) modules:
use PDL;
use PDL::NiceSlice;
use Math::Trig qq(pi);

# Perl-Gnuplot conection module:
use Chart::Gnuplot;

# ---------------------------------------------------------------------------- #
# Load bash enviroments:

use lib $ENV{ ENV_ROOT };
use Enviroments qq(:CONSTANTS);

# ---------------------------------------------------------------------------- #
# Load dedicated libraries:

use lib LIB_ROOT_PATH;
use MyUtil   qq(:ALL); # ancillary utilities...
use MyMath   qq(:ALL); # dedicated math toolbox...
use MyPrint  qq(:ALL); # plain text print layouts...
use TimeGNSS qq(:ALL); # GNSS time conversion tools...
use Geodetic qq(:ALL); # dedicated geodesy utilities...

# Load general configuration and interfaces module:
use lib SRC_ROOT_PATH;
use GeneralConfiguration qq(:ALL);

# Load common GSPA utils:
use lib GSPA_ROOT_PATH;
use CommonUtil qq(:ALL);

# ---------------------------------------------------------------------------- #
# Public Subroutines: #

sub PlotReceiverPosition {
  my ($ref_gen_conf, $inp_path, $out_path, $marker_name) = @_;

  # Select receiver position dumper file:
  my $ref_file_layout =
     GetFileLayout($inp_path."/receiver-xyz.out", 8,
                   $ref_gen_conf->{DATA_DUMPER}{DELIMITER});

  my $pdl_rec_xyz = pdl( LoadFileByLayout($ref_file_layout) );

  # Observation epochs:
  my $pdl_epochs =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{Epoch}{INDEX});

  # Get first and last observation epochs:
  my $ini_epoch = min($pdl_epochs);
  my $end_epoch = max($pdl_epochs);

  # Get number of epochs:
  my ($num_epochs, undef) = dims($pdl_epochs->flat);

  # Retrieve days's 00:00:00 in GPS epoch format:
  my $ini_day_epoch = Date2GPS( (GPS2Date($ini_epoch))[0..2], 0, 0, 0 );
  my $pdl_epoch_day_hour = ($pdl_epochs - $ini_day_epoch)/SECONDS_IN_HOUR;

  # Retrieve Easting and Northing values:
  my $pdl_rec_easting =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{REF_IE}{INDEX});
  my $pdl_rec_northing =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{REF_IN}{INDEX});
  my $pdl_rec_upping =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{REF_IU}{INDEX});

  # Get maximum upping absolute value:
  my $max_upping     = max($pdl_rec_upping);
  my $min_upping     = min($pdl_rec_upping);
  my $max_abs_upping = max( pdl [abs($max_upping), abs($min_upping)] );

  # Retrieve standard deviations for ENU coordinates:
  my $pdl_std_easting =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{Sigma_E}{INDEX});
  my $pdl_std_northing =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{Sigma_N}{INDEX});
  my $pdl_std_upping =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{Sigma_U}{INDEX});

  # Compute horizontal standard deviation:
  my $pdl_std_en = ($pdl_std_easting**2 + $pdl_std_northing**2)**0.5;

  # Retrieve receiver clock bias estimation and associated error:
  my $pdl_rec_clk_bias =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{ClkBias}{INDEX});
  my $pdl_std_clk_bias =
     $pdl_rec_xyz($ref_file_layout->{ITEMS}{Sigma_ClkBias}{INDEX});

  # Build polar coordinates from easting and northing components:
  my ($pdl_rec_azimut, $pdl_rec_distance) =
    RecPolarCoordinates($pdl_rec_easting, $pdl_rec_northing);

  # Compute max rec distance for polar plot and add 1 meter.
  # This is for setting the polar plot bound on the ro domain:
  my $max_rec_distance = int(max($pdl_rec_distance)) + 1;

  # Set EN polar title:
  # Get initial epoch date in 'yyyy/mo/dd' format:
  my $chart_en_polar_sigma_h_title =
    SetReportTitle("Receiver Easting, Northing and Sigma(H)",
                   $ref_gen_conf, $marker_name, $ini_epoch);
  my $palette_label_sigmah_cmm = 'cblabel "Horizontal Sigma [m]"';

  # Create polar plot object for plotting EN components:
  my $chart_en_polar_sigma_h =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,874',
      output => $out_path."/Receiver-EN-SigmaH-polar.png",
      title  => {
        text => $chart_en_polar_sigma_h_title,
        font => ':Bold',
      },
      border => undef,
      xtics  => undef,
      ytics  => undef,
      $palette_label_sigmah_cmm => '',
      timestamp =>  {
        fmt  => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
    );
  # Set chart polar properties:
    $chart_en_polar_sigma_h->set(
      size   => "0.9, 0.9",
      origin => "0.085, 0.06",
      polar  => "",
      grid   => "polar front",
      'border polar' => '',
      angle  => "radians",
      theta  => "top clockwise",
      trange => "[0:2*pi]",
      rrange => "[0:$max_rec_distance]",
      rtics  => "1",
      ttics  => 'add ("N" 0, "NE" 45, "E" 90, "SE" 135, '.
                     '"S" 180, "SW" 225, "W" 270, "NW" 315)',
      colorbox => "",
    );
  # Set point style properties:
    $chart_en_polar_sigma_h->set(
      style => "fill transparent solid 0.04 noborder",
      style => "circle radius 0.05",
    );

  # Set polar EN plot with epoch in the Z domain:
  my $chart_en_epoch_polar_title =
    SetReportTitle("Receiver Easting, Northing and Epoch",
                   $ref_gen_conf, $marker_name, $ini_epoch);
  my $palette_label_epoch_cmm = 'cblabel "Epoch [h]"';
  my $palette_color_epoch_cmm =
    'palette defined (0 0 0 0, 1 0 0 1, 3 0 1 0, 4 1 0 0, 6 1 1 1)';

  my $chart_en_epoch_polar =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,874',
      output => $out_path."/Receiver-EN-Epoch-polar.png",
      title  => {
        text => $chart_en_epoch_polar_title,
        font => ':Bold',
      },
      border => undef,
      xtics  => undef,
      ytics  => undef,
      $palette_label_epoch_cmm => '',
      $palette_color_epoch_cmm => '',
      # $palette_range_epoch_cmm => '',
      timestamp =>  {
        fmt  => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
    );
  # Set chart polar properties:
    $chart_en_epoch_polar->set(
      size   => "0.9, 0.9",
      origin => "0.085, 0.06",
      polar  => "",
      grid   => "polar front",
      'border polar' => '',
      angle  => "radians",
      theta  => "top clockwise",
      trange => "[0:2*pi]",
      rrange => "[0:$max_rec_distance]",
      rtics  => "1",
      ttics  => 'add ("N" 0, "NE" 45, "E" 90, "SE" 135, '.
                     '"S" 180, "SW" 225, "W" 270, "NW" 315)',
      # cbtics => 0.25,
      colorbox => "",
    );
  # Set point style properties:
    $chart_en_epoch_polar->set(
      style => "fill transparent solid 0.04 noborder",
      style => "circle radius 0.05",
    );

  # Plor for polar EN and upping in Z domain:
  my $chart_enu_polar_title =
    SetReportTitle("Receiver Easting, Northing and Upping",
                   $ref_gen_conf, $marker_name, $ini_epoch);
  my $palette_label_upping_cmm = 'cblabel "Upping [m]"';
  my $palette_color_upping_cmm = 'palette rgb 33,13,10;';
  my $palette_range_upping_cmm = "cbrange [-$max_abs_upping:$max_abs_upping]";

  my $chart_enu_polar =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,874',
      output => $out_path."/Receiver-EN-Upping-polar.png",
      title  => {
        text => $chart_enu_polar_title,
        font => ':Bold',
      },
      border => undef,
      xtics  => undef,
      ytics  => undef,
      $palette_label_upping_cmm => '',
      $palette_color_upping_cmm => '',
      $palette_range_upping_cmm => '',
      timestamp =>  {
        fmt  => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
    );
  # Set chart polar properties:
    $chart_enu_polar->set(
      size   => "0.9, 0.9",
      origin => "0.085, 0.06",
      polar  => "",
      grid   => "polar front",
      'border polar' => '',
      angle  => "radians",
      theta  => "top clockwise",
      trange => "[0:2*pi]",
      rrange => "[0:$max_rec_distance]",
      rtics  => "1",
      ttics  => 'add ("N" 0, "NE" 45, "E" 90, "SE" 135, '.
                     '"S" 180, "SW" 225, "W" 270, "NW" 315)',
      colorbox => "",
    );
  # Set point style properties:
    $chart_enu_polar->set(
      style => "fill transparent solid 0.04 noborder",
      style => "circle radius 0.05",
    );

  # Set ENU multiplot chart title:
  my $chart_enu_title =
    SetReportTitle("Receiver Easting, Northing and Upping",
                   $ref_gen_conf, $marker_name, $ini_epoch);

  # Create parent object for ENU multiplot:
  my $chart_enu =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,540',
      output => $out_path."/Receiver-ENU-plot.png",
      title => $chart_enu_title,
      # NOTE: this does not works properly
      timestamp => "on",
    );

  # ENU individual charts for multiplot:
  my $chart_e =
    Chart::Gnuplot->new(
      grid => "on",
      ylabel => "Easting [m]",
      xrange => [$ini_epoch, $end_epoch],
      cbtics => 1,
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
   );
  my $chart_n =
    Chart::Gnuplot->new(
      grid => "on",
      ylabel => "Northing [m]",
      xrange => [$ini_epoch, $end_epoch],
      cbtics => 1,
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
   );
  my $chart_u =
    Chart::Gnuplot->new(
      grid => "on",
      xlabel => "Observation Epochs [HH::MM]",
      ylabel => "Upping [m]",
      xrange => [$ini_epoch, $end_epoch],
      cbtics => 1,
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
   );

  my $chart_clk_bias_title =
    SetReportTitle("Receiver Clock Bias",
                   $ref_gen_conf, $marker_name, $ini_epoch);

  # Create chart object for receiver clock bias:
  my $palette_label_std_cmm = 'cblabel "Sigma Time [m]"';
  my $chart_clk_bias =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,540',
      grid => "on",
      output => $out_path."/Receiver-clk-bias-plot.png",
      title  => {
        text => $chart_clk_bias_title,
        font => ':Bold',
      },
      xlabel => "Observation Epochs [HH::MM]",
      ylabel => "Clock Bias [m]",
      xrange => [$ini_epoch, $end_epoch],
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
      $palette_label_std_cmm => "",
      timestamp =>  {
        fmt  => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
    );


  # Build EN polar datasets:
  # EN polar dataset with horizontal accuracy:
  my $rec_en_sigma_h_polar_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_rec_azimut->flat),
      ydata => unpdl($pdl_rec_distance->flat),
      zdata => unpdl($pdl_std_en->flat),
      style => "circles linecolor pal z",
      fill => { density => 0.8 },
    );
  # EN polar dataset with upping component:
  my $rec_enu_polar_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_rec_azimut->flat),
      ydata => unpdl($pdl_rec_distance->flat),
      zdata => unpdl($pdl_rec_upping->flat),
      style => "circles linecolor pal z",
      fill => { density => 0.8 },
    );
  my $rec_en_epoch_polar_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_rec_azimut->flat),
      ydata => unpdl($pdl_rec_distance->flat),
      zdata => unpdl($pdl_epoch_day_hour->flat),
      style => "circles linecolor pal z",
      fill => { density => 0.8 },
    );

  # Reference dataset for ENU multiplot:
  my $rec_ref_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl(zeros($num_epochs)->flat),
      style => "lines",
      color => "#888A85",
      width => 2,
      timefmt => "%s",
    );

  # Build receiver E positions dataset:
  my $rec_e_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_rec_easting->flat),
      zdata => unpdl($pdl_std_easting->flat),
      style => "lines linecolor pal z",
      width => 2,
      timefmt => "%s",
    );
  # Build receiver N positions dataset:
  my $rec_n_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_rec_northing->flat),
      zdata => unpdl($pdl_std_northing->flat),
      style => "lines linecolor pal z",
      width => 2,
      timefmt => "%s",
    );
  # Build receiver U positions dataset:
  my $rec_u_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_rec_upping->flat),
      zdata => unpdl($pdl_std_upping->flat),
      style => "lines linecolor pal z",
      width => 2,
      timefmt => "%s",
    );
  # Build receiver clock bias dataset:
  my $rec_clk_bias_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_rec_clk_bias->flat),
      zdata => unpdl($pdl_std_clk_bias->flat),
      style => "points pointtype 7 ps 0.3 linecolor pal z",
      width => 3,
      timefmt => "%s",
    );

  # Build receiver ENU positions dataset:
  my $rec_enu_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_rec_easting->flat),
      ydata => unpdl($pdl_rec_northing->flat),
      zdata => unpdl($pdl_rec_upping->flat),
      style => "points",
    );

  # Plot the datasets on their respectives graphs:
    # ENU multiplot:
      # Add datasets to their respective charts:
      $chart_e->add2d( $rec_ref_dataset, $rec_e_dataset );
      $chart_n->add2d( $rec_ref_dataset, $rec_n_dataset );
      $chart_u->add2d( $rec_ref_dataset, $rec_u_dataset );

      # And set plot matrix in parent chart object:
      $chart_enu->multiplot([ [$chart_e],
                              [$chart_n],
                              [$chart_u] ]);

    # Receiver clock bias plot:
    $chart_clk_bias->plot2d((
                              $rec_clk_bias_dataset
                           ));

    # EN 2D polar plot:
    $chart_en_polar_sigma_h->plot2d( $rec_en_sigma_h_polar_dataset );
    $chart_en_epoch_polar->plot2d( $rec_en_epoch_polar_dataset );
    $chart_enu_polar->plot2d( $rec_enu_polar_dataset );

  return TRUE;
}

sub PlotAccuracyPerformance {
  my ($ref_gen_conf, $inp_path, $out_path, $marker_name) = @_;

  # Load dumper file:
  my $ref_file_layout =
    GetFileLayout( join('/', ($inp_path, "sigma-info.out")), 5,
                   $ref_gen_conf->{DATA_DUMPER}{DELIMITER} );

  my $pdl_sigma_info = pdl( LoadFileByLayout($ref_file_layout) );

  my $pdl_epochs =
     $pdl_sigma_info($ref_file_layout->{ITEMS}{EpochGPS}{INDEX});

  my $ini_epoch = min($pdl_epochs);
  my $end_epoch = max($pdl_epochs);

  my $pdl_sigma_g = $pdl_sigma_info($ref_file_layout->{ITEMS}{SigmaG}{INDEX});
  my $pdl_sigma_p = $pdl_sigma_info($ref_file_layout->{ITEMS}{SigmaP}{INDEX});
  my $pdl_sigma_t = $pdl_sigma_info($ref_file_layout->{ITEMS}{SigmaT}{INDEX});
  my $pdl_sigma_h = $pdl_sigma_info($ref_file_layout->{ITEMS}{SigmaH}{INDEX});
  my $pdl_sigma_v = $pdl_sigma_info($ref_file_layout->{ITEMS}{SigmaV}{INDEX});

  # Set chart's titles:
  my $chart_ecef_title =
    SetReportTitle("ECEF Frame Accuracy Performance",
                   $ref_gen_conf, $marker_name, $ini_epoch);
  my $chart_enu_title =
    SetReportTitle("ENU Frame Accuracy Performance",
                   $ref_gen_conf, $marker_name, $ini_epoch);

  # Create chart for ECEF frame sigma:
  my $chart_ecef =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,540',
      output => $out_path."/Sigma-ECEF-plot.png",
      title  => {
        text => $chart_ecef_title,
        font => ':Bold',
      },
      grid   => "on",
      xlabel => "Observation Epochs [HH::MM]",
      ylabel => "Sigma [m]",
      xrange => [$ini_epoch, $end_epoch],
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
      timestamp =>  {
        fmt => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
   );

  # Create chart for ENU frame sigma:
  my $chart_enu =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,540',
      output => $out_path."/Sigma-ENU-plot.png",
      title  => {
        text => $chart_enu_title,
        font => ':Bold',
      },
      grid   => "on",
      xlabel => "Observation Epochs [HH::MM]",
      ylabel => "Sigma [m]",
      xrange => [$ini_epoch, $end_epoch],
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
      timestamp =>  {
        fmt => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
   );

  # Create sigma datasets:
  my $sigma_g_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_sigma_g->flat),
      style => "points pointtype 7 ps 0.3",
      width => 3,
      timefmt => "%s",
      title => "Geometric Sigma*1",
    );
  my $sigma_p_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_sigma_p->flat),
      style => "points pointtype 7 ps 0.3",
      width => 3,
      timefmt => "%s",
      title => "Position Sigma*1",
    );
  my $sigma_t_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_sigma_t->flat),
      style => "points pointtype 7 ps 0.3",
      width => 3,
      timefmt => "%s",
      title => "Time Sigma*1",
    );
  my $sigma_h_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_sigma_h->flat),
      style => "points pointtype 7 ps 0.3",
      width => 3,
      timefmt => "%s",
      title => "Horizontal Sigma*1",
    );
  my $sigma_v_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_sigma_v->flat),
      style => "points pointtype 7 ps 0.3",
      width => 3,
      timefmt => "%s",
      title => "Vertical Sigma*1",
    );

  # Plot datasets on their respective chart:
  $chart_ecef -> plot2d((
                          $sigma_g_dataset,
                          $sigma_p_dataset,
                          $sigma_t_dataset
                        ));
  $chart_enu  -> plot2d((
                          $sigma_p_dataset,
                          $sigma_v_dataset,
                          $sigma_h_dataset,
                        ));

  return TRUE;
}

sub PlotIntegrityPerformance {
  my ($ref_gen_conf, $inp_path, $out_path, $marker_name) = @_;

  # Retrieve alert limits and sigma scale factors:
  my $v_al  = $ref_gen_conf->{ INTEGRITY }{ VERTICAL   }{ ALERT_LIMIT  };
  my $h_al  = $ref_gen_conf->{ INTEGRITY }{ HORIZONTAL }{ ALERT_LIMIT  };
  my $v_ssf = $ref_gen_conf->{ ACCURACY  }{ VERTICAL   }{ SIGMA_FACTOR };
  my $h_ssf = $ref_gen_conf->{ ACCURACY  }{ HORIZONTAL }{ SIGMA_FACTOR };

  # Load dumper file:
  my $ref_file_layout;

  # Horizontal integrity:
  $ref_file_layout =
     GetFileLayout( join('/', ($inp_path, "integrity-horizontal.out")),
                    4, $ref_gen_conf->{DATA_DUMPER}{DELIMITER} );

  # Make piddle from loaded file:
  my $pdl_int_h = pdl( LoadFileByLayout($ref_file_layout) );

  # Vertical integrity:
  $ref_file_layout =
     GetFileLayout( join('/', ($inp_path, "integrity-vertical.out")),
                    4, $ref_gen_conf->{DATA_DUMPER}{DELIMITER} );

  # Make piddle from loaded file:
  my $pdl_int_v = pdl( LoadFileByLayout($ref_file_layout) );

  # Retrieve file information in piddles:
  #   Epochs
  #   Position status
  my $pdl_epochs = $pdl_int_h($ref_file_layout->{ITEMS}{ EpochGPS }{INDEX});
  my $pdl_status = $pdl_int_h($ref_file_layout->{ITEMS}{ Status   }{INDEX});

  # Get first and last observation epochs:
  my $ini_epoch = min($pdl_epochs);
  my $end_epoch = max($pdl_epochs);

  # Retrieve vertical info:
  my $pdl_v_al  = $pdl_int_v($ref_file_layout->{ITEMS}{ AlertLimit }{INDEX});
  my $pdl_v_err = $pdl_int_v($ref_file_layout->{ITEMS}{ Error      }{INDEX});
  my $pdl_v_acc = $pdl_int_v($ref_file_layout->{ITEMS}{ Precision  }{INDEX});
  my $pdl_v_mi  = $pdl_int_v($ref_file_layout->{ITEMS}{ MI         }{INDEX});
  my $pdl_v_hmi = $pdl_int_v($ref_file_layout->{ITEMS}{ HMI        }{INDEX});
  my $pdl_v_sa  = $pdl_int_v($ref_file_layout->{ITEMS}{ Available  }{INDEX});

  # MI, HMI and SA are multiplied by the AL for a better plot display
  $pdl_v_mi  *= $v_al;
  $pdl_v_hmi *= $v_al;
  $pdl_v_sa  *= $v_al;

  # Retrieve horizontal info:
  my $pdl_h_al  = $pdl_int_h($ref_file_layout->{ITEMS}{ AlertLimit }{INDEX});
  my $pdl_h_err = $pdl_int_h($ref_file_layout->{ITEMS}{ Error      }{INDEX});
  my $pdl_h_acc = $pdl_int_h($ref_file_layout->{ITEMS}{ Precision  }{INDEX});
  my $pdl_h_mi  = $pdl_int_h($ref_file_layout->{ITEMS}{ MI         }{INDEX});
  my $pdl_h_hmi = $pdl_int_h($ref_file_layout->{ITEMS}{ HMI        }{INDEX});
  my $pdl_h_sa  = $pdl_int_h($ref_file_layout->{ITEMS}{ Available  }{INDEX});

  # MI, HMI and SA are multiplied by the AL for a better plot display
  $pdl_h_mi  *= $h_al;
  $pdl_h_hmi *= $h_al;
  $pdl_h_sa  *= $h_al;

  # ************** #
  # Chart objects: #
  # ************** #

  # Titles:
  my $chart_v_title =
    SetReportTitle("Integrity performance on vertical domain",
                   $ref_gen_conf, $marker_name, $ini_epoch);

  my $chart_h_title =
    SetReportTitle("Integrity performance on horizontal domain",
                   $ref_gen_conf, $marker_name, $ini_epoch);

  # Vertical chart:
  my $chart_v =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,540',
      grid => "on",
      output => $out_path."/Integrity-Vertical-plot.png",
      title  => {
        text => $chart_v_title,
        font => ':Bold',
      },
      xlabel => "Observation Epochs [HH::MM]",
      xrange => [$ini_epoch, $end_epoch],
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
      legend => {
        position => "inside top",
        order => "horizontal",
        align => "right",
        sample   => {
             length => 5,
         },
      },
      timestamp =>  {
        fmt  => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
    );

  # Horizontal chart:
  my $chart_h =
    Chart::Gnuplot->new(
      terminal => 'pngcairo size 874,540',
      grid => "on",
      output => $out_path."/Integrity-Horizontal-plot.png",
      title  => {
        text => $chart_h_title,
        font => ':Bold',
      },
      xlabel => "Observation Epochs [HH::MM]",
      xrange => [$ini_epoch, $end_epoch],
      timeaxis => "x",
      xtics => { labelfmt => "%H:%M" },
      legend => {
        position => "inside top",
        order => "horizontal",
        align => "center",
        sample   => {
             length => 5,
         },
      },
      timestamp =>  {
        fmt  => 'Created on %d/%m/%y %H:%M:%S',
        font => "Helvetica Italic, 10",
      },
    );

  # **************** #
  # Dataset objects: #
  # **************** #

  # Vertical component:
  my $v_st_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl(($pdl_status*$v_al)->flat),
      style => "filledcurve y=0",
      color => "#CC729FCF",
      timefmt => "%s",
      title => "Position Status",
    );

  my $v_al_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_v_al->flat),
      style => "lines",
      color => "#555753",
      width => 3,
      timefmt => "%s",
      title => "Alert Limit ($v_al)",
    );

  my $v_err_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_v_err->flat),
      style => "lines",
      color => "#CE5C00",
      timefmt => "%s",
      title => "Error",
    );

  my $v_acc_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_v_acc->flat),
      style => "lines",
      color => "#EDD400",
      timefmt => "%s",
      title => "Precision*$v_ssf",
    );

  my $v_mi_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_v_mi->flat),
      style => "filledcurve y=0",
      color => "#88EF2929",
      timefmt => "%s",
      title => "MI",
    );

  my $v_hmi_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_v_hmi->flat),
      style => "filledcurve y=0",
      color => "#33A40000",
      timefmt => "%s",
      title => "HMI",
    );

  my $v_sa_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_v_sa->flat),
      style => "filledcurve y=0",
      color => "#DD4E9A06",
      timefmt => "%s",
      title => "Avail.",
    );

  # Horizontal component:
  my $h_st_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl(($pdl_status*$h_al)->flat),
      style => "filledcurve y=0",
      color => "#CC729FCF",
      timefmt => "%s",
      title => "Position Status",
    );

  my $h_al_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_h_al->flat),
      style => "lines",
      color => "#555753",
      width => 3,
      timefmt => "%s",
      title => "Alert Limit ($h_al)",
    );

  my $h_err_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_h_err->flat),
      style => "lines",
      color => "#CE5C00",
      timefmt => "%s",
      title => "Error",
    );

  my $h_acc_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_h_acc->flat),
      style => "lines",
      color => "#EDD400",
      timefmt => "%s",
      title => "Precision*$h_ssf",
    );

  my $h_mi_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_h_mi->flat),
      style => "filledcurve y=0",
      color => "#88EF2929",
      timefmt => "%s",
      title => "MI",
    );

  my $h_hmi_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_h_hmi->flat),
      style => "filledcurve y=0",
      color => "#33A40000",
      timefmt => "%s",
      title => "HMI",
    );

  my $h_sa_dataset =
    Chart::Gnuplot::DataSet->new(
      xdata => unpdl($pdl_epochs->flat),
      ydata => unpdl($pdl_h_sa->flat),
      style => "filledcurve y=0",
      color => "#DD4E9A06",
      timefmt => "%s",
      title => "Avail.",
    );

  # ***************** #
  # Plot arrangement: #
  # ***************** #

  $chart_v->plot2d(
                    $v_st_dataset,
                    $v_sa_dataset,
                    $v_mi_dataset,
                    $v_hmi_dataset,
                    $v_al_dataset,
                    $v_err_dataset,
                    $v_acc_dataset,
                  );

  $chart_h->plot2d(
                    $h_st_dataset,
                    $h_sa_dataset,
                    $h_mi_dataset,
                    $h_hmi_dataset,
                    $h_al_dataset,
                    $h_err_dataset,
                    $h_acc_dataset,
                  );

  return TRUE;
}

# ---------------------------------------------------------------------------- #
# Private Subroutines: #

sub RecPolarCoordinates {
  my ($pdl_east, $pdl_north) = @_;

  # Distance is computed as:
  my $pdl_distance = ($pdl_east**2 + $pdl_north**2)**0.5;

  # Get array lsit from piddles:
  my @east  = list( $pdl_east  -> flat() );
  my @north = list( $pdl_north -> flat() );

  # Init azmiut array:
  my @azimut;

  for my $i (keys @east) {
    my ($az, $ze, $dist) = Venu2AzZeDs($east[$i], $north[$i], 1);
    push(@azimut, $az);
  }

  my $pdl_azimut = pdl(@azimut);

  return ($pdl_azimut, $pdl_distance);
}

TRUE;
