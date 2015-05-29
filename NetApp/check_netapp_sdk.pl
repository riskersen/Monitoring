#!/usr/bin/perl
#-------------------------------------------
# Author: Oliver Skibbe
# Date: 2014-10-29
# Purpose: Check Netapp 
#      - Volume size (+ perf)
#      - LUN size, alignment, online (+ perf)
#      - Aggregate size, inconsistency, raid state, mirror state, mount state (+ perf)
#      - Snapmirror state (+ perf)
#      - Cluster state (+ hw_assist if available)
#      - license expiration / is licensed
#      - System info
#      - Shelf state
# TODO
#      - diagnosis
#      - samba service?
#      - Performance data
#
# Changelog:
#      2014-10-29: Oliver Skibbe (https://github.com/riskersen):
#        - fixed: failed snapmirror were filtered
#      2014-10-08: Oliver Skibbe (https://github.com/riskersen):
#        - code cleanup, according to PBP (still not done yet)
#        - fixed --help
#      2014-10-03: PLZ (https://github.com/plz):
#        - Fixed typo
#      2014-08-06: Oliver Skibbe (https://github.com/riskersen):
#        - first release
#-------------------------------------------

use strict;
use warnings;


use lib "/usr/local/share/perl/5.14.2/NetApp";         # this has to be adjusted!
use Nagios::Plugin;                                    # Nagios helper functions
use NaServer;                                          # class for managing NetApp storage systems using ONTAPI(tm) APIs.
use Pod::Usage;                                        # Perl module that allows the programmer to use POD
use File::Basename;                                    # Basename of plugin
use Getopt::Long qw(:config no_ignore_case bundling);  # Get options

die pod2usage( -message => "UNKNOWN: no arguments given",
  -exitval => 3,
  -verbose => 1
) unless $ARGV[0];

my $VERSION = '0.7.8';
my $PROGNAME = basename($0);
my $np = Nagios::Plugin->new(
  version   => $VERSION,
  plugin    => $PROGNAME,
  shortname   => uc($PROGNAME)  
);

# helper vars
my %command_table = (
  'check-volume'     => \&check_volume,
  'check-snapmirror' => \&check_snapmirror,
  'check-lun'        => \&check_lun,
  'check-aggr'       => \&check_aggr,
  'check-cluster'    => \&check_cluster,
  'check-shelf'      => \&check_shelf,
  'check-volume'     => \&check_volume,
  'get-netapp-info'  => \&get_netapp_info,
  'check-version'    => \&get_netapp_info,
);

my %netapp;
my %exit_hash;
$exit_hash{exit_state} = OK;
$exit_hash{exit_msg} = "";

# defaults
my $host = "";
my $dossl = 1;
my $command = "get-info";
my $name = "";
my $user = "";
my $password = "";
my $warn = 85;
my $crit = 90;
my $timeout = 30;
my $debug = 0;
my $help = 0;
my $full_help = 0;
my $no_perfdata = 0;
my $wafl_reserve = 1.03; # netapp wafl fs reserve in volume

# parse arguments
($host, $user, $password, $command, $name, $timeout, $dossl, $warn, $crit, $no_perfdata, $debug) = parse_args();

# netapp stuff
my $server_type = "FILER"; # could be an argument
my $port = $dossl ? 443 : 80;
my $response;

# set nagios thresholds
$np->set_thresholds(critical => $crit, warning => $warn);

# init netapp
my $s = NaServer->new($host, 1, 1);

# connection stuff (timeout, http(s), user/pw,...)
%exit_hash = init_netapp();
  
if ( $exit_hash{exit_state} == OK ) { 
  ($command_table{$command} ||sub { $exit_hash{exit_msg} = "INVALID COMMAND"; $exit_hash{exit_state} = UNKNOWN; return %exit_hash })->();
}

# remove trailing and leading white spaces from exit message
$exit_hash{exit_msg} =~ s/^\s+|\s+$//g;

# exit
$np->nagios_exit($exit_hash{exit_state}, $exit_hash{exit_msg});



###
### Subs - actual work is done there
###
sub init_netapp {
  # set http/https port
  $s->set_port($port);
  if ($dossl) {
      $response = $s->set_transport_type("HTTPS");
      if (ref ($response) eq "NaElement" && $response->results_errno != 0) {
          my $r = $response->results_reason();
          $exit_hash{exit_state} = CRITICAL;
          $exit_hash{exit_msg} = "Unable to set HTTPS transport $r";
      }
  }
  $s->set_admin_user($user, $password); # set the admin username and password

  # set server type
  $response = $s->set_server_type($server_type);
  if (ref ($response) eq "NaElement") {
      if ($response->results_errno != 0) {
          my $r = $response->results_reason();
          $exit_hash{exit_state} = CRITICAL;
          $exit_hash{exit_msg} = "CRITICAL: Unable to set server type $r";
      }
  }

  # set timeout, defaults to 30
  if($timeout > 0) {
    $s->set_timeout($timeout);
  } else {
    $exit_hash{exit_state} = CRITICAL;
    $exit_hash{exit_msg} = "Invalid value for connection timeout. Connection timeout value should be greater than 0";
  }

  return (%exit_hash);
}

sub get_netapp_info {
  
  # get system info
  my $output = $s->invoke( "system-get-info" );
  if ($output->results_errno != 0) {
    my $r = $output->results_reason();
    $np->nagios_exit(CRITICAL, "System info failed: $r");
  } else {
    my $netapp_info = $output->child_get("system-info");
    $netapp{name} = lc($netapp_info->child_get_string("system-name"));
    $netapp{id} = lc($netapp_info->child_get_string("system-id"));
    $netapp{serial} = $netapp_info->child_get_string("system-serial-number");
    $netapp{model} = $netapp_info->child_get_string("system-model");
  }
  
  $output = $s->invoke( "system-get-version" ); # Submit an XML request already encapsulated as  an NaElement and return the result in another  NaElement.

  if ($output->results_errno != 0) {
    my $r = $output->results_reason();
    $np->nagios_exit(CRITICAL, "Version info failed: $r");
  } else {
    $netapp{version} = $output->child_get_string( "version" );
  }
  $exit_hash{exit_msg} = "System-Name: " . $netapp{name} . " System-ID: " . $netapp{id} . " Model: " . $netapp{model} . " Serial: " . $netapp{serial} . " Version: " . $netapp{version};
  $exit_hash{exit_state} = OK;

  return %exit_hash;
}

# check volumes for size and print them with perf data
sub check_volume {

  # variables
  my $output;
  my $counter = 0;

  # if no additional name is given, lookup all volumes
  if( $name eq "" ) {
    $output = $s->invoke( "volume-list-info");
  }
  else {
    $output = $s->invoke( "volume-list-info", "volume", $name );
  }

  if ($output->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, "Volume-list-info: " . $output->results_reason());
  }

  my $volume_info = $output->child_get("volumes");
  my @result = $volume_info->children_get();

  foreach my $vol (@result){
    # fetch results
    my $vol_name = $vol->child_get_string("name");
    my $vol_size_total = $vol->child_get_int("size-total") ? $vol->child_get_int("size-total") : 0;
    my $vol_size_used = $vol->child_get_int("size-used") ? $vol->child_get_int("size-used") : 0;
    # calc pct
    my $vol_size_pct = ( $vol_size_total > 0 && $vol_size_used > 0 ) ? sprintf("%.2f", ($vol_size_used/$vol_size_total)*100) : 0;
    # convert to highest available uom
    $vol_size_total = ($vol_size_total/1024) . " B";
    $vol_size_used  = ($vol_size_used/1024) . " B";
    
    # split uom and size for perfdata
    my @vol_size_used = split(' ', $vol_size_used);
    my @vol_size_total = split(' ', $vol_size_total);
    
    if ( ! $no_perfdata ) {
      my $warn_size = sprintf("%.0f", ($warn*$vol_size_total[0])/100);
      my $crit_size = sprintf("%.0f", ($crit*$vol_size_total[0])/100);
      # perfdata: actual size
      $np->set_thresholds(critical => $crit_size, warning => $warn_size);
      $np->add_perfdata( 
        label => $vol_name . "_size_used",
        value => $vol_size_used[0],
        uom => $vol_size_used[1],
        threshold => $np->threshold,
      );
      $np->add_perfdata( 
        label => $vol_name . "_size_total",
        value => $vol_size_total[0],
        uom => $vol_size_total[1],
        threshold => $np->threshold,
      );
      
      # perfdata: pct
      $np->set_thresholds(critical => $crit, warning => $warn);
      $np->add_perfdata( 
        label => $vol_name . "_size_pct",
        value => $vol_size_pct,
        uom => "%",
        threshold => $np->threshold,
      );
    }
    
    # prepare exit code & check against threshold
    my $code = $np->check_threshold(check => $vol_size_pct);
    
    # set exit_state to crit if current exit_state is OK or warning
    # if exit_state is OK and code is Warning => set warning
    # if exit_state is CRITICAL and code is warning -> add warning msg
    if ( $code == CRITICAL ) {
      # we catched a critical return value
      $exit_hash{exit_msg} .= "C->" . $vol_name . ": " . $vol_size_pct . "% ";
      $exit_hash{exit_state} = $code;
      $counter++;
    } elsif ( $code == WARNING ) {
      # if warning is catched, but critical is already set, add warning msg and warning code
      $exit_hash{exit_state} = $code if ( $exit_hash{exit_state} == OK );      
      $exit_hash{exit_msg} .= "W->" . $vol_name . ": " . $vol_size_pct . "% ";
      $counter++;
    }
  }
  
  # nicer output, adds a ": " if suspicious volumes are found
  my $exit_msg_part = $counter > 0 ? ":" : "";
  $exit_hash{exit_msg} = $counter . " suspicious volumes found" . $exit_msg_part . " " . $exit_hash{exit_msg};
  return (%exit_hash);
}

# check lun for size and print them with perf data
sub check_lun {

  # variables
  my $output;
  my $counter = 0;

  # if no additional name is given, lookup all luns
  if( $name eq "" ) {
    $output = $s->invoke( "lun-list-info");
  }
  else {
    $output = $s->invoke( "lun-list-info", "path", $name );
  }

  if ($output->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, "Lun-list-info failed: " . $output->results_reason());
  }

  my $lun_info = $output->child_get("luns");
  my @result = $lun_info->children_get();

  foreach my $lun (@result){
    # skip if offline?
    next if ( $lun->child_get_string("online") eq "false" && $lun->child_get_string("mapped") eq "false" );
    
    # fetch results
    my $lun_path = $lun->child_get_string("path");
    my @lun_name_arr = split('/', $lun_path);
    # sample output: /vol/foobar_vol/foobar_lun
    my $lun_name = $lun_name_arr[3];
    my $lun_size_total = $lun->child_get_int("size");
    my $lun_size_used = $lun->child_get_int("size-used");
    my $lun_alignment = $lun->child_get_string("alignment");
    my $lun_online = ( $lun->child_get_string("online") eq "true" ) ? "online" : "offline";
    # calc pct
    my $lun_size_pct = ( $lun_size_total > 0 && $lun_size_used > 0 ) ? sprintf("%.2f", ($lun_size_used/$lun_size_total)*100) : 0;

    $lun_size_total = ($lun_size_total/1024) . " B";
    $lun_size_used  = ($lun_size_used/1024) . " B";
    
    # split uom and size for perfdata
    my @lun_size_used = split(' ', $lun_size_used);
    my @lun_size_total = split(' ', $lun_size_total);
    my $warn_size = sprintf("%.0f", ($warn*$lun_size_total[0])/100);
    my $crit_size = sprintf("%.0f", ($crit*$lun_size_total[0])/100);
    
    if ( ! $no_perfdata ) {
      # perfdata: actual size
      $np->set_thresholds(critical => $crit_size, warning => $warn_size);
      $np->add_perfdata( 
        label => $lun_name . "_size_used",
        value => $lun_size_used[0],
        uom => $lun_size_used[1],
        threshold => $np->threshold,
      );
      $np->add_perfdata( 
        label => $lun_name . "_size_total",
        value => $lun_size_total[0],
        uom => $lun_size_total[1],
        threshold => $np->threshold,
      );
      
      # perfdata: pct
      $np->set_thresholds(critical => $crit, warning => $warn);
      $np->add_perfdata( 
        label => $lun_name . "_size_pct",
        value => $lun_size_pct,
        uom => "%",
        threshold => $np->threshold,
      );
    }
    
    # prepare exit code & check against threshold
    # check for size
    my $lun_size_code = $np->check_threshold(check => $lun_size_pct);
    my $lun_align_code = ( $lun_alignment eq "misaligned" ) ? WARNING : OK;
    my $lun_online_code = ( $lun_online ne "online" ) ? CRITICAL : OK;
    
    if ( $lun_size_code == CRITICAL || $lun_align_code == CRITICAL || $lun_online_code == CRITICAL )  {
      # we catched a critical return value
      $exit_hash{exit_msg} .= "C->" . $lun_name . ": " . $lun_size_pct . "% ";
      $exit_hash{exit_state} = CRITICAL;
      $counter++;
    } elsif ( $lun_size_code == WARNING || $lun_align_code == WARNING || $lun_online_code == WARNING ) {
      # if warning is catched, but critical is already set, add warning msg and warning code
      $exit_hash{exit_state} = WARNING if ( $exit_hash{exit_state} == OK ) ;
      $exit_hash{exit_msg} .= "W->" . $lun_name . ": " . $lun_size_pct . "% ";
      $counter++;
    }
    
    $exit_hash{exit_msg} .= $lun_alignment . " " if ( $lun_align_code != OK );
    $exit_hash{exit_msg} .= "(" . $lun_online . "!) " if ( $lun_online_code != OK );
  }
  
  # nicer output, adds a ": " if suspicious lunS are found
  my $exit_msg_part = $counter > 0 ? ":" : "";
  $exit_hash{exit_msg} = $counter . " suspicious luns found" . $exit_msg_part . " " . $exit_hash{exit_msg};
  return (%exit_hash);
}

# check shelf for size and print them with perf data
sub check_shelf {

  # variables
  my $output;  
  my $counter = 0;
  my $shelf;
  my $cmd = "storage-shelf-environment-list-info";
  
  my @good_shelf_states = qw/normal/;
  my @warning_shelf_states = qw/informational non_critical/;
  my @critical_shelf_states = qw/unrecoverable critical/;
  
  my $shelf_power_supply_failure = "";
  my $shelf_voltage_sensor_failure = "";
  my $shelf_temp_sensor_failure = "";
  
  # use netapp defaults
  my $temp_low_warn = 10;
  my $temp_low_crit = 5;
  my $temp_high_warn = 50;
  my $temp_high_crit = 55;

  # if no additional name is given, lookup all shelf
  if( $name eq "" ) {
    $output = $s->invoke($cmd);
  }
  else {
    $output = $s->invoke( $cmd, "channel-name", $name );
  }

  if ($output->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, $cmd . ": " . $output->results_reason());
  }

  my $shelf_infos = $output->child_get("shelf-environ-channel-list");
  my $shelf_channel_infos = $shelf_infos->child_get("shelf-environ-channel-info");
  
  # number of shelves
  my $shelf_present = $shelf_channel_infos->child_get_string("shelves-present");
  my $shelf_channel_failure = $shelf_channel_infos->child_get_string("is-shelf-channel-failure");
  
  # 
  my $shelf_environ_list = $shelf_channel_infos->child_get("shelf-environ-shelf-list");  
  my @result = $shelf_environ_list->children_get();
  
  foreach my $shelf (@result){    
    # fetch results
    my $shelf_id = $shelf->child_get_string("shelf-id");
    my $shelf_state = $shelf->child_get_string("shelf-status");
    
    ### shelf power supply
    my $shelf_power_supply_list = $shelf->child_get("power-supply-list");
    my $shelf_power_supply_infos = $shelf_power_supply_list->child_get("power-supply-info");
    my @shelf_power_supply_info = $shelf_power_supply_list->children_get();
    
    # foreach power supply
    foreach my $shelf_power_supply (@shelf_power_supply_info) {
      # skip if not installed
      my $shelf_power_supply_not_installed = $shelf_power_supply->child_get_string("power-supply-is-not-installed");      
      next if ( ! defined($shelf_power_supply_not_installed) );
      
      my $shelf_power_supply_is_error = $shelf_power_supply->child_get_string("power-supply-is-error");
      my $shelf_power_serial_no = $shelf_power_supply->child_get_string("power-supply-serial-no");
      $shelf_power_supply_failure .= "Failure power supply " . $shelf_power_serial_no . " " if ( defined($shelf_power_supply_is_error) );
    } # end foreach power supply
        
    
    ### shelf voltage sensor
    my $shelf_voltage_sensor_list = $shelf->child_get("voltage-sensor-list");
    my @shelf_voltage_sensor_info = $shelf_voltage_sensor_list->children_get();
    # foreach voltage sensor
    foreach my $shelf_voltage_sensor (@shelf_voltage_sensor_info) {
      # skip if not installed
      my $shelf_voltage_sensor_not_installed = $shelf_voltage_sensor->child_get_string("is-sensor-not-installed");
      next if ( defined($shelf_voltage_sensor_not_installed) );
      
      my $shelf_voltage_sensor_no = $shelf_voltage_sensor->child_get_string("voltage-sensor-no");
      my $shelf_voltage_sensor_state = $shelf_voltage_sensor->child_get_string("is-sensor-error");
      my $shelf_voltage_sensor_reading = $shelf_voltage_sensor->child_get_string("sensor-reading");
      $shelf_voltage_sensor_failure .= "Voltage sensor " . $shelf_voltage_sensor_no . 
                      " " . $shelf_voltage_sensor->child_get_string("sensor-condition")
                      if ( $shelf_voltage_sensor_state eq "true" );
                      
      # perfdata
      if ( ! $no_perfdata ) {
        my @voltage = split(' ', $shelf_voltage_sensor_reading);
        $np->add_perfdata( 
          label => "shelf_" . $shelf_id . "_volt_sensor_" . $shelf_voltage_sensor_no . "_read",
          value => $voltage[0],
          uom => "c"
        );
      }
    } # end foreach voltage sensor
    
    # shelf voltage sensor
    my $shelf_temp_sensor_list = $shelf->child_get("temp-sensor-list");    
    my @shelf_temp_sensor_info = $shelf_temp_sensor_list->children_get();
    
    # foreach temp sensor
    foreach my $shelf_temp_sensor (@shelf_temp_sensor_info) {
      # skip if not installed
      my $shelf_temp_sensor_is_not_installed = $shelf_temp_sensor->child_get_string("temp-sensor-is-not-installed");
      next if ( defined($shelf_temp_sensor_is_not_installed) );
      
      my $shelf_temp_sensor_no = $shelf_temp_sensor->child_get_int("temp-sensor-element-no");
      my $shelf_temp_sensor_state = $shelf_temp_sensor->child_get_string("temp-sensor-is-error");
      my $shelf_temp_sensor_current = $shelf_temp_sensor->child_get_string("temp-sensor-current-temperature");
        
      # temperature thresholds from netapp
      my $shelf_temp_sensor_low_crit = ( $shelf_temp_sensor->child_get_string("temp-sensor-low-critical") ) ? 
                        $shelf_temp_sensor->child_get_string("temp-sensor-low-critical") : 
                        $temp_low_crit;
      my $shelf_temp_sensor_low_warn = ( $shelf_temp_sensor->child_get_string("temp-sensor-low-warning") ) ? 
                        $shelf_temp_sensor->child_get_string("temp-sensor-low-warning") :
                        $temp_low_warn;
      my $shelf_temp_sensor_high_crit = ( $shelf_temp_sensor->child_get_string("temp-sensor-hi-critical") ) ?
                        $shelf_temp_sensor->child_get_string("temp-sensor-hi-critical") :
                        $temp_high_crit;
      my $shelf_temp_sensor_high_warn = ( $shelf_temp_sensor->child_get_string("temp-sensor-hi-warning") ) ?
                        $shelf_temp_sensor->child_get_string("temp-sensor-hi-warning") :
                        $temp_high_warn;
      
      # XXX
      $np->set_thresholds(critical => $shelf_temp_sensor_low_crit . ":" . $shelf_temp_sensor_high_crit,
                warning => $shelf_temp_sensor_low_warn . ":" . $shelf_temp_sensor_high_warn);
      
      my $temp_sensor_code = $np->check_threshold(check => $shelf_temp_sensor_current);
      
      my $part_string = ( $temp_sensor_code == CRITICAL ) ? "C->" : ( $temp_sensor_code == WARNING ) ? "W->" : "";
      
      $shelf_temp_sensor_failure .= $part_string . "Temp sensor " . $shelf_temp_sensor_no . " [" .
                      $shelf_temp_sensor->child_get_string("temp-sensor-current-condition") .
                      " (" . $shelf_temp_sensor_current . " C)] "
                      if ( $temp_sensor_code != OK );
      ### perfdata
      if ( ! $no_perfdata ) {
        my @temperature = split(' ', $shelf_temp_sensor_current);
        $np->add_perfdata( 
          label => "shelf_" . $shelf_id . "_temp_sensor_" . $shelf_temp_sensor_no,
          value => $temperature[0],
          threshold => $np->threshold
        );      
      }
    } # end foreach Temperature sensor
    
    # prepare exit code & check against threshold
    my $shelf_state_code = ( in_array ( \@good_shelf_states, $shelf_state ) ) ? OK : ( in_array ( \@warning_shelf_states, $shelf_state ) ) ? WARNING : CRITICAL;
    my $shelf_power_supply_code = ( length($shelf_power_supply_failure) > 0 ) ? CRITICAL: OK;
    my $shelf_voltage_sensor_code = ( length($shelf_voltage_sensor_failure) > 0 ) ? CRITICAL: OK;
    my $shelf_temp_sensor_code = ( $shelf_temp_sensor_failure =~ /C->/ ) ? CRITICAL : ( $shelf_temp_sensor_failure =~ /W->/ ) ? WARNING : OK;
    
    # set exit_state to crit if current exit_state is OK or warning
    # if exit_state is OK and code is Warning => set warning
    # if exit_state is CRITICAL and code is warning -> add warning msg
    if (  $shelf_state_code == CRITICAL || $shelf_power_supply_code == CRITICAL || $shelf_voltage_sensor_code == CRITICAL ||
        $shelf_temp_sensor_code == CRITICAL ) {
      # we catched a critical return value
      $exit_hash{exit_msg} .= "C->";
      $exit_hash{exit_state} = CRITICAL;
      $counter++;
    } elsif (   $shelf_state_code == WARNING || $shelf_power_supply_code == WARNING || $shelf_voltage_sensor_code == WARNING || 
          $shelf_temp_sensor_code == WARNING ) {
      # if warning is catched, but critical is already set, add warning msg and warning code
      $exit_hash{exit_msg} .= "W->";
      # text      
      $exit_hash{exit_state} = WARNING if ( $exit_hash{exit_state} == OK );
      $counter++;
    }    
    
    # just to see something
    $exit_hash{exit_msg} .= "Shelf " . $shelf_id . " (Shelf-State: " . $shelf_state . ")";
    
    # only on purpose
    $exit_hash{exit_msg} .= " (Temp: " . $shelf_temp_sensor_failure . ")" if ( $shelf_temp_sensor_code != OK );
    $exit_hash{exit_msg} .= " (Volt sensor: " . $shelf_voltage_sensor_failure . ")" if ( $shelf_voltage_sensor_code != OK );
    $exit_hash{exit_msg} .= " (Power supply: " . $shelf_power_supply_failure . ")" if ( $shelf_power_supply_code != OK );
    
    # multiline, otherwise output might be unreadable :(
    $exit_hash{exit_msg} .= "\n";
  } #end foreach shelf
  
  # nicer output, adds a ": " if suspicious shelfs are found
  my $exit_msg_part = $counter > 0 ? ":" : "";
  $exit_hash{exit_msg} = $counter . "/" . $shelf_present . " suspicious shelves found" . $exit_msg_part . "\n" . $exit_hash{exit_msg};
  return (%exit_hash);
}

# check aggr for size and print them with perf data
sub check_aggr {

  # variables
  my $output;
  my $counter = 0;

  # if no additional name is given, lookup all aggrs
  if( $name eq "" ) {
    $output = $s->invoke( "aggr-list-info");
  }
  else {
    $output = $s->invoke( "aggr-list-info", "aggregate", $name );
  }

  if ($output->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, "aggr-list-info failed: " . $output->results_reason());
  }

  my $aggr_info = $output->child_get("aggregates");
  my @result = $aggr_info->children_get();
  foreach my $aggr (@result){
    
    # fetch results
    my $aggr_name = $aggr->child_get_string("name");
    my $aggr_size_total = $aggr->child_get_int("size-total"); 
    my $aggr_size_used = $aggr->child_get_int("size-used") * 0.97;    # dont forget 3% wafl reserve
    my $aggr_state = $aggr->child_get_string("state");
    my $aggr_mount_state = $aggr->child_get_string("mount-state");    # possible values: unmounted, online, frozen, destroying, creating, mounting, unmounting, 
                                      # consistent, inconsistent, reverted, quiescing, quiesced, iron restricted
    my @good_mount_states = qw/online consistent quiesced/;
    my @warning_mount_states = qw/creating mounting unmounting quiescing/;
    
    my $aggr_mirror_state = $aggr->child_get_string("mirror-status");   # possible values: invalid, uninitialized, needs CP count check, limbo,
                                      # CP count check in progress, mirrored, mirror degraded, mirror resyncing, failed
    my @good_mirror_states = qw/mirrored unmirrored/;
    my @warning_mirror_states = ("CP count check in progress");
                                      
    my @aggr_raid_state = split(", ", $aggr->child_get_string("raid-status"));     # possible values: normal, verifying, mirrored, resyncing, SnapMirrored, copying, ironing
                                      # degraded, invalid, needs check, initializing, growing, partial, noparity, mirror degraded,
                                      # reconstruct, out-of-date, foreign
                                      # sample: raid_dp, mirrored (we might split these values)                                      
    $aggr_raid_state[1] = "normal" if (@aggr_raid_state == 1);      # small hack, needed if unmirrored
    
    my @good_raid_states = qw/normal mirrored/;
    my @warning_raid_states = qw/resyncing copying growing reconstruct/;
    
                                      
    my $aggr_is_inconsistent = $aggr->child_get_string("is-inconsistent"); # possible values: true/false
    
    ### XXX this is ugly :( 
    ### TODO change this to invoke -> child_get
    my $aggr_space_details = $aggr->child_get("aggregate-space-details");
    my $aggr_space_info = $aggr_space_details->child_get("aggregate-space-info");
    my $snapshot_space = $aggr_space_info->child_get("snapshot-space");
    my $snapshot_info = $snapshot_space->child_get("snapshot-space-info");
    my @snapshot_space_info = $snapshot_space->children_get();
    
    # should return only 1 snap
    foreach my $snap (@snapshot_space_info) {
      $aggr_size_total += $snap->child_get_int("snapshot-size-used");
    }
    
    # calc pct
    my $aggr_size_pct = ( $aggr_size_total > 0 && $aggr_size_used > 0 ) ? sprintf("%.2f", ($aggr_size_used/$aggr_size_total)*100) : 0;
    
    # convert to highest available uom
    $aggr_size_total = ($aggr_size_total/1024) . " B";
    $aggr_size_used  = ($aggr_size_used/1024) . " B";
    
    if ( ! $no_perfdata ) {
      # split uom and size for perfdata
      my @aggr_size_used = split(' ', $aggr_size_used);
      my @aggr_size_total = split(' ', $aggr_size_total);
      my $warn_size = sprintf("%.0f", ($warn*$aggr_size_total[0])/100);
      my $crit_size = sprintf("%.0f", ($crit*$aggr_size_total[0])/100);
      
      # perfdata: actual size
      $np->set_thresholds(critical => $crit_size, warning => $warn_size);
      $np->add_perfdata( label => $aggr_name . "_size_used", value => $aggr_size_used[0],uom => $aggr_size_used[1], threshold => $np->threshold);
      $np->add_perfdata( label => $aggr_name . "_size_total", value => $aggr_size_total[0], uom => $aggr_size_total[1]);
      
      # perfdata: pct
      $np->set_thresholds(critical => $crit, warning => $warn);
      $np->add_perfdata( label => $aggr_name . "_size_pct", value => $aggr_size_pct, uom => "%", threshold => $np->threshold);
    }
    
    # prepare exit code & check against threshold
    # check for size
    my $agrr_size_code = $np->check_threshold(check => $aggr_size_pct);
    my $inconsistent_code = ( $aggr_is_inconsistent ) ? OK : CRITICAL;
    my $raid_code = ( in_array ( \@good_raid_states, $aggr_raid_state[1] ) ) ? OK : ( in_array ( \@warning_raid_states, $aggr_raid_state[1] ) ) ? WARNING : CRITICAL;
    my $mirror_state_code = ( in_array ( \@good_mirror_states, $aggr_mirror_state ) ) ? OK : ( in_array ( \@warning_mirror_states, $aggr_mirror_state ) ) ? WARNING : CRITICAL;
    my $mount_state_code = ( in_array ( \@good_mount_states, $aggr_mount_state ) ) ? OK : ( in_array ( \@warning_mount_states, $aggr_mount_state ) ) ? WARNING : CRITICAL;
    
    # set exit_state to crit if current exit_state is OK or warning
    # if exit_state is OK and code is Warning => set warning
    # if exit_state is CRITICAL and code is warning -> add warning msg
    if (  $agrr_size_code == CRITICAL || $inconsistent_code == CRITICAL || $raid_code == CRITICAL ||
        $mirror_state_code == CRITICAL || $mount_state_code == CRITICAL ) {
      # we catched a critical return value
      $exit_hash{exit_msg} .= "C->" . $aggr_name . ": " . $aggr_size_pct . "% ";
      $exit_hash{exit_state} = CRITICAL;
      $counter++;
    } elsif (   $agrr_size_code == WARNING || $inconsistent_code == WARNING || $raid_code == WARNING || 
          $mirror_state_code == WARNING || $mount_state_code == WARNING ) {
      # if warning is catched, but critical is already set, add warning msg and warning code
      $exit_hash{exit_msg} .= "W->" . $aggr_name . ": " . $aggr_size_pct . "% ";
      $exit_hash{exit_state} = WARNING if ( $exit_hash{exit_state} == OK );
      $counter++;
    }
    
    $exit_hash{exit_msg} .= "(not consistent!) " if ( $inconsistent_code != OK );
    $exit_hash{exit_msg} .= "(raid: " . $aggr_raid_state[1] . ") " if ( $raid_code != OK );
  }
  
  # nicer output, adds a ": " if suspicious aggrs are found
  my $exit_msg_part = $counter > 0 ? ":" : "";
  $exit_hash{exit_msg} = $counter . " suspicious aggregate found" . $exit_msg_part . " " . $exit_hash{exit_msg};
  return (%exit_hash);
}

# check cluster
sub check_cluster {

  # variables
  my $cf_hwassist_local_code = OK;
  my $cf_hwassist_partner_code = OK;
  
  # cf-status
  my $cf = $s->invoke( "cf-status");
  
  if ($cf->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, "Cluster-status failed: " . $cf->results_reason());
  }

  if ( $cf->child_get_string("is-enabled") ) {
    my $cf_state = lc($cf->child_get_string("state"));
    my @good_cf_states = qw/connected/;
    my @warning_cf_states = qw/takeover_scheduled takeover_started giving_back giveback_partial_connected waiting in_maintenance_mode pending_shutdown/;
    my @critical_cf_states = qw/takeover takeover_failed giveback_partial_waiting waiting_for_root_aggr error/;
    
    my $cf_interconnect = ( $cf->child_get_string("is-interconnect-up") eq "true" ) ? "up" : "down";
    
    my $cf_partner_name = lc($cf->child_get_string("partner"));
    
    my $cf_takeover_failure_reason = $cf->child_get_string("takover-failure-reason") ? $cf->child_get_string("takover-failure-reason") : "-";
    
    # cf-hwassist-status
    my $cf_hwassist_status = $s->invoke("cf-hwassist-status");  
    # no-status is set if there is no hardware assisted cluster
    if ( ! $cf_hwassist_status->child_get_string("no-status") ) {
      my $cf_hwassist_local_status = $cf_hwassist_status->child_get_string("local-hwassist-status");
      my $cf_hwassist_partner_status = $cf_hwassist_status->child_get_string("partner-hwassist-status");
      
      # possible values: hw_assist funtionality is active or inactive
      $cf_hwassist_local_code = CRITICAL if ( $cf_hwassist_local_status =~ /inactive/ );
      $cf_hwassist_partner_code = CRITICAL if ( $cf_hwassist_partner_status =~ /inactive/ );
    }
    
    my $cf_state_code = ( in_array ( \@good_cf_states, $cf_state ) ) ? OK : ( in_array ( \@warning_cf_states, $cf_state ) ) ? WARNING : CRITICAL;
    my $cf_interconnect_code = ( $cf_interconnect eq "up" ) ? OK : CRITICAL;
    
    if ($cf_state_code == CRITICAL || $cf_interconnect_code == CRITICAL || $cf_hwassist_local_code == CRITICAL || $cf_hwassist_partner_code == CRITICAL ) {        
      $exit_hash{exit_state} = CRITICAL;
    } elsif ( $cf_state_code == WARNING || $cf_interconnect_code == WARNING || $cf_hwassist_local_code == WARNING || $cf_hwassist_partner_code == WARNING ) {
      $exit_hash{exit_state} = WARNING if ( $exit_hash{exit_state} == OK );
    } else {
      $exit_hash{exit_msg} .= "Partner " . $cf_partner_name . " is " . $cf_state;
    }
    
    # exit_msgs on error
    $exit_hash{exit_msg} .= "Cluster takeover failed: " . $cf_takeover_failure_reason . " " if ( $cf_takeover_failure_reason ne "-" );
    $exit_hash{exit_msg} .= "Cluster state is: " . $cf_state . " " if ( $cf_state_code != OK );
    $exit_hash{exit_msg} .= "Partner HW_Assist is inactive! " if ( $cf_hwassist_partner_code != OK );
    $exit_hash{exit_msg} .= "Local HW_Assist is inactive! " if ( $cf_hwassist_local_code != OK );
  }

  if ( $exit_hash{exit_state} == OK ) {
    $exit_hash{exit_msg} = "Cluster is fine!";
  } else {
    $exit_hash{exit_msg} = " " . $exit_hash{exit_msg};
  }

  return (%exit_hash);
}


sub check_snapmirror {

  # variables
  my $output;
  my $counter = 0;
  my @snap_transfer_type = ("scheduled", "retry", "resync", "update", "initialize", "store", "retrieve");

  # if no additional name is given, lookup all snapmirror
  if( $name eq "" ) {
    $output = $s->invoke( "snapmirror-get-status");
  }
  else {
    $output = $s->invoke( "snapmirror-get-status", "location", $name );
  }

  if ($output->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, "SnapMirror-get-status failed: " . $output->results_reason());
  }

  my $snapmirror_info = $output->child_get("snapmirror-status");
  my @result = $snapmirror_info->children_get();

  foreach my $snap (@result){
    # fetch results
    my $raw_destination_location = $snap->child_get_string("destination-location");
    my $raw_source_location = $snap->child_get_string("source-location");
    
    # 0 => hostname; 1 => snapmirror name
    my @snapmirror_dst_loc = split(':', lc($raw_destination_location));
    my @snapmirror_src_loc = split(':', lc($raw_source_location));

    my $snap_cnt_xfer_err = $snap->child_get_string("current-transfer-error") ? $snap->child_get_string("current-transfer-error") : "-";
    my $snap_cnt_xfer_type = $snap->child_get_string("current-transfer-type") ? $snap->child_get_string("current-transfer-type") : "-";
    my $snap_last_xfer_type = $snap->child_get_string("last-transfer-type") ? $snap->child_get_string("last-transfer-type") : "-";
    
    # returns kB
    my $snap_last_xfer_size = $snap->child_get_string("last-transfer-size") ? ($snap->child_get_string("last-transfer-size")/1024) . " B" : 0;
    
    # returns seconds
    my $snap_last_xfer_dur = $snap->child_get_string("last-transfer-duration") ? $snap->child_get_string("last-transfer-duration") : 0;
    my $snap_lag_time = $snap->child_get_string("lag-time") ? $snap->child_get_string("lag-time") : 0;
    
    # prepare names
    my $snap_name = $snapmirror_src_loc[0] . "->" . $snapmirror_dst_loc[0] . ": " . $snapmirror_dst_loc[1];
    my $snap_perf_name = $snapmirror_src_loc[0] . "_" . $snapmirror_dst_loc[0] . "_" . $snapmirror_dst_loc[1];
    
    # split uom and size for perfdata
    my @snap_xfer_size = split(' ', $snap_last_xfer_size);
        
    # disable perfdata with -p
    if ( ! $no_perfdata ) {
      # perfdata: actual size
      $np->add_perfdata( 
        label     => $snap_perf_name . "_xfer_size",
        value     => $snap_xfer_size[0],
        uom     => $snap_xfer_size[1],
      );
      $np->add_perfdata( 
        label    => $snap_perf_name . "_lag_time",
        value     => $snap_lag_time,
        uom     => "s",
        threshold   => $np->threshold,
      );
    }
    
    my $snap_lag_code = ( $snap_lag_time > 0 ) ? $np->check_threshold(check => $snap_lag_time) : OK;
    $snap_lag_time = timeconv($snap_lag_time);    
    
    # critical if xfer err is present
    my $code = ( $snap_cnt_xfer_err ne "-" ) ? CRITICAL : OK;
    
    # set exit_state to crit if current exit_state is OK or warning
    # if exit_state is OK and code is Warning => set warning
    # if exit_state is CRITICAL and code is warning -> add warning msg
    if ( $code == CRITICAL || $snap_lag_code == CRITICAL)  {
      # we catched a critical return value
      $exit_hash{exit_msg} .= "C->";
      $exit_hash{exit_state} = CRITICAL;
      $counter++;
    } elsif ( $code == WARNING || $snap_lag_code == WARNING ) { 
      # if warning is catched, but critical is already set, add warning msg and warning code
      $exit_hash{exit_msg} .= "W->";
      $exit_hash{exit_state} = WARNING if ( $exit_hash{exit_state} == OK );  
      $counter++;
    } # end code check
    
    $exit_hash{exit_msg} .= $snap_name . ": Lag-time: " . $snap_lag_time . " " if ($snap_lag_code != OK || $code != OK);
    $exit_hash{exit_msg} .= "Error: " . $snap_cnt_xfer_err . " " if ($snap_lag_code != OK || $code != OK);
    
  }
  my $exit_msg_part = $counter > 0 ? ": " : "";
  $exit_hash{exit_msg} = $counter . " failed snapmirror found" . $exit_msg_part . " " . $exit_hash{exit_msg};
  return (%exit_hash);
}

sub check_license {

  # variables
  my $output;
  my $warning_expiration = $warn; # warning 60 days left
  my $critical_expiration = $crit; # critical 30 days left
    
  my $counter = 0;
  my $max_counter = 0;
  my $timestamp = time();

  # if no additional name is given, lookup all licenses
  if( $name eq "" ) {
    $output = $s->invoke( "license-list-info");
  }

  if ($output->results_status() eq "failed"){
    $np->nagios_exit(CRITICAL, "license-list-info failed: " . $output->results_reason());
  }

  my $licenses = $output->child_get("licenses");
  my $license_info = $output->child_get("license-info");
  my @result = $licenses->children_get();

  foreach my $license (@result) {
    $max_counter++;
    my $license_name = $license->child_get_string("service");
    my $license_expired = $license->child_get_string("is-expired");
    my $license_licensed = $license->child_get_string("is-licensed");
    my $license_is_demo = $license->child_get_string("is-demo");
    my $license_auto_enabled = $license->child_get_string("is-auto-enabled");
    my $license_expiration_timestamp = $license->child_get_int("expiration-timestamp") ? $license->child_get_int("expiration-timestamp") : 0;
    my $license_installation_timestamp = $license->child_get_int("installation-timestamp") ? $license->child_get_int("installation-timestamp") : 0;
    
    next if ( $license_auto_enabled eq "true" || $license_is_demo eq "true" || $license_expiration_timestamp == 0 );  # skip if demo license or auto enabled license or non expiry
    
    my $expiration_seconds = ( $license_expiration_timestamp > 0 ) ? $license_expiration_timestamp - $timestamp : 0; # seconds till expiration  (negative)
    
    
    # warning if license is below $warn but above $crit
    my $time_expiring_code = ( $expiration_seconds <= $critical_expiration ) ? CRITICAL : ( $expiration_seconds <= $warning_expiration ) ? WARNING : OK;
    
    # critical if license is expired
    my $expire_code = ( $license_expired ) ? CRITICAL : OK;
    
    # set exit_state to crit if current exit_state is OK or warning
    # if exit_state is OK and code is Warning => set warning
    # if exit_state is CRITICAL and code is warning -> add warning msg
    if ( $expire_code == CRITICAL || $time_expiring_code == CRITICAL)  {
      # we catched a critical return value
      $exit_hash{exit_msg} .= "C->";
      $exit_hash{exit_state} = CRITICAL;
      $counter++;
    } elsif ( $expire_code == WARNING || $time_expiring_code == WARNING ) { ### currently not in use, maybe later for lag time
      # if warning is catched, but critical is already set, add warning msg and warning code
      $exit_hash{exit_msg} .= "W->";
      $exit_hash{exit_state} = WARNING if ( $exit_hash{exit_state} == OK );  
      $counter++;
    } # end code check
    
    $exit_hash{exit_msg} .= $license_name . " Expiration: " . localtime($license_expiration_timestamp) . " " if ( $exit_hash{exit_state} != OK );
    $exit_hash{exit_msg} .= "(expired!) " if ( $expire_code != OK );
  }
  my $exit_msg_part = $counter > 0 ? ": " : "";
  $exit_hash{exit_msg} = $counter . "/" . $max_counter . " expired licenses found" . $exit_msg_part . " " . $exit_hash{exit_msg};
  return (%exit_hash);
}

sub parse_args {
        GetOptions(
                'host|H=s'        => \$host,
                'command|C=s'     => \$command,
                'name|n:s'        => \$name,
                'username|U=s'    => \$user,
                'password|P=s'    => \$password,
                'ssl|S:1'         => \$dossl,
                'no-perfdata|p:1' => \$no_perfdata,
                'timeout|t:i'     => \$timeout,
                'warning|w:i'     => \$warn,
                'critical|c:i'    => \$crit,
                'debug|d:i'       => \$debug,
                'help|?!'         => \$help,
                'help|h!'         => \$help,
        ) or pod2usage("Try '$0 --help' for more information.");

        pod2usage(-exitval => 3, -verbose => 1) if $help;

        return ($host, $user, $password, $command, $name, $timeout, $dossl, $warn, $crit, $no_perfdata, $debug);
}

sub timeconv($) {
    my $secs = shift;
    if    ($secs >= 365*24*60*60) { return sprintf '%.1f years', $secs/(365*24*60*60) }
    elsif ($secs >=     24*60*60) { return sprintf '%.1f days', $secs/(24*60*60) }
    elsif ($secs >=        60*60) { return sprintf '%.1f hours', $secs/(60*60) }
    elsif ($secs >=           60) { return sprintf '%.1f minutes', $secs/(60) }
    else                          { return sprintf '%.1f seconds', $secs }
}

sub in_array {
    my ($arr,$search_for) = @_;
    foreach my $value (@$arr) {
        return 1 if $value eq $search_for;
    }
    return 0;
}

__END__

=head1 NAME

check_netapp_sdk.pl - NetApp Plugin via Data ONTAP

=head1 SYNOPSIS

check_netapp_sdk.pl -H -U -P [-S|-w|-c|-t|-d|-?]

  -H --host   STRING or IPADDRESS of Filer  
  -U --username   STRING Admin User  
  -P --password   STRING Admin Password  
  -C --command   STRING command name, defaults to version info
  -n --name  STRING addition to some commands, e.g. to specify volume/lun/... name
  -S --ssl   activates SSL HTTPS Transport  
  -w --warning   Warning threshold, depends on command, defaults to 80  
  -c --critical   Critical threshold, depends on command, defaults to 90
  -t --timeout  INTEGER Connection timeout filer
  -d --debug  Future: activates debug mode (more output)
  -? --help  full help
  
  Possible commands:
  
  check-volume [-n VOLUME_NAME] - List volumes use -n to specify volume
    -> size in percent (-w/-c)
  check-lun [-n LUN_NAME] - List LUNs, use -n to specify lun
    -> size in percent (-w/-c)
    -> misalignment results to warning
    -> offline state and is mapped results to critical
  check-snapmirror [-n SNAPMIRROR_NAME] - List snapmirrors, use -n to specify snapmirror
    -> lag_time in seconds (-w/-c)
    -> transfer error -> CRITICAL
  check-aggr [-n AGGREGATE_NAME] - List aggregates, use -n to specify lun
    -> size in percent (-w/-c)
    -> mount state: warning on creating, mounting, unmounting, quiescing; ok on online consistent quiesced; critical for the rest!
    -> mirror state: warning on 'CP count check in progress'; ok on mirrored, unmirrored; critical for the rest!
    -> raid state: warning on resyncing, copying, growing, reconstruct; ok on normal, mirrored; critical for the rest
    -> inconsistency results on critical
  check-cluster - checks for cluster state
    -> warning/critical on other state than connected
    -> warning on inactive hwassist (if available)
    -> interconnect state
  check-shelf
    -> critical on failed power-supply
    -> critical on failed voltage sensor
    -> critical on failed temp sensor
    -> temperature (values provided by netapp, is needed due to different sensor locations)
    -> shelf state : warning on informational, non_critical; ok on normal; critical for the rest!
  check-license - checks license
    -> expiry date (excludes demo, auto_enabled and non expiry lics)
    
  Dependencies

  NetApp SDK
  Nagios::Plugins
  
=head1 SEE ALSO

  NetApp ONTAP SDK

=head1 COPYRIGHT
  Oliver Skibbe (oliskibbe@gmail.com)
=cut
