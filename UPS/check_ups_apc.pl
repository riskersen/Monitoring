#!/usr/bin/perl
# nagios: -epn
# icinga: -epn
#    Copyright (C) 2004 Altinity Limited
#    E: info@altinity.com    W: http://www.altinity.com/
#    Modified by pierre.gremaud@bluewin.ch
#    Modified by Oliver Skibbe oliver.skibbe at mdkn.de
#    Modified by Alexander Rudolf alexander.rudolf (at) saxsys.de
#    
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#    
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.    See the
#    GNU General Public License for more details.
#    
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA    02111-1307    USA
#
# 2017-05-29: Momcilo Medic medicmomcilo (at) gmail.com
#	- added battery temperature thresholds support
# 2017-02-07: Oliver Skibbe oliskibbe (at) gmail.com
#	- added SNMPv1 support
# 2016-11-29: Oliver Skibbe oliskibbe (at) gmail.com
#       - disabling icinga embedded perl interpreter
#       - fixed external sensor option
#       - improved option handling
# 2015-11-20: Oliver Skibbe oliskibbe (at) gmail.com
#	- disabling nagios embedded perl interpreter
# 2015-10-08: Oliver Skibbe oliver.skibbe (at) mdkn.de
#	- updated help
# 2015-03-09: Oliver Skibbe oliver.skibbe (at) mdkn.de
#	- disabled epn, leads to a warning with using mod_gearman
#	- disabled warning for using given/when
#	- fixed SNMP error comparison 
# 2015-02-09: Oliver Skibbe oliver.skibbe (at) mdkn.de
#	- added snmp v3 support
# 2014-01-08: Alexander Rudolf alexander.rudolf (at) saxsys.de
#	- added support for external temperature sensor (exttemp...)
#         Hint: expecting the value unit is Celsius ('1'), if iemStatusProbeTempUnits.1
#         (.1.3.6.1.4.1.318.1.1.10.2.3.2.1.5.1) is Fahrenheit ('2') we will get wrong data
#	- changed battery temperature values from 'temp...' to 'battemp...' and output
#               Before: OK - Smart-UPS RT 8000 RM XL ... - TEMPERATURE 27 C - ...
#               After:  OK - Smart-UPS RT 8000 RM XL ... - BATT TEMP 27 C - EXT TEMP 23 C - ...
#	- added warn and crit values to performance data output as well as units
#       - tested with Smart-UPS 5000/8000 and "PowerNet SNMP Agent SW v2.2 compatible"
# 2013-07-08: Oliver Skibbe oliver.skibbe (at) mdkn.de
#	- warn/crit values defined per variable
# 	- get watt hour if oid exists (Smart UPS 2200)
# 	- calculate remaining time in minutes on battery (bit ugly, but seems working)
#		critical if below $remaining_time_crit value
# 	- changed return string to add CRIT/WARN to corresponding failed value
#		Before: CRIT - Smart-UPS RT 10000 XL - BATTERY CAPACITY 100% - STATUS NORMAL - OUTPUT LOAD 31% - TEMPERATURE 23 C 
#		After: CRIT - Smart-UPS RT 10000 XL - CRIT BATTERY CAPACITY 50% - STATUS NORMAL - OUTPUT LOAD 31% - TEMPERATURE 23 C
#	- Added multiline output for firmware,manufacture date and serial number

use feature ":5.10";
use Net::SNMP;
use Getopt::Std;
use Getopt::Long qw(:config no_ignore_case bundling);

# Do we have enough information?
if (@ARGV < 1) {
     print "Too few arguments\n";
     usage();
}

# Parse out the arguments...
my ($ip, $community, $battemperature_warn, $battemperature_crit, $version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot, $with_external_sensor) = parse_args();

# Initialize variables....
my $net_snmp_debug_level = 0x00;	# See http://search.cpan.org/~dtown/Net-SNMP-v6.0.1/lib/Net/SNMP.pm#debug()_-_set_or_get_the_debug_mode_for_the_module

$script    = "check_ups_apc.pl";
$script_version = "1.5";

$timeout = 10;			# SNMP query timeout
$status = 0;
$returnstring = "";
$perfdata = "";

## OIDs
$oid_sysDescr = ".1.3.6.1.2.1.1.1.0";
$oid_serial_number = ".1.3.6.1.4.1.318.1.1.1.1.2.3.0";
$oid_firmware = ".1.3.6.1.4.1.318.1.1.1.1.2.1.0";
$oid_manufacture_date = ".1.3.6.1.4.1.318.1.1.1.1.2.2.0";
$oid_upstype = ".1.3.6.1.4.1.318.1.1.1.1.1.1.0";
$oid_battery_capacity = ".1.3.6.1.4.1.318.1.1.1.2.2.1.0";
$oid_output_status = ".1.3.6.1.4.1.318.1.1.1.4.1.1.0";
$oid_output_current = ".1.3.6.1.4.1.318.1.1.1.4.2.4.0";
$oid_output_load = ".1.3.6.1.4.1.318.1.1.1.4.2.3.0";
$oid_battemperature = ".1.3.6.1.4.1.318.1.1.1.2.2.2.0";
$oid_exttemperature = ".1.3.6.1.4.1.318.1.1.10.2.3.2.1.4.1";
$oid_remaining_time = ".1.3.6.1.4.1.318.1.1.1.2.2.3.0";
# optional, Smart-UPS 2200 support this
$oid_current_load_wh = ".1.3.6.1.4.1.318.1.1.1.4.3.6.0";

$oid_battery_replacment = ".1.3.6.1.4.1.318.1.1.1.2.2.4.0";

# helper
$upstype = "";
$battery_capacity = 0;
$output_status = 0;
$output_current = 0;
$output_load = 0;
$battemperature = 0;
$exttemperature = 0;
$exttemperature = undef;


# crit / warn values
$remaining_time_crit = 5;
$remaining_time_warn = 15;
$output_load_crit = 80;
$output_load_warn = 70;
$exttemperature_crit = 30;
$exttemperature_warn = 26;
$battery_capacity_crit = 35;
$battery_capacity_warn = 65;


## SNMP ##
if ( $version == 3 ) {
	($s, $e) = get_snmp_session_v3(
				$ip, 
				$user_name,
				$auth_password, 
				$auth_prot,
				$priv_password,
				$priv_prot
			);	# Open an SNMP connection...
} else {
	($s, $e) = get_snmp_session(
				$ip, 
				$community, 
				$version
			);	# Open an SNMP connection...
}


if ( $e ne "" ) {
	print "CRITICAL: SNMP Error $e\n";
	exit(2);
}

main();

# Close the session
$s->close();

if ($status == 0){
    print "OK - $returnstring|$perfdata\n";
}
elsif ($status == 1){
    print "WARNING - $returnstring|$perfdata\n";
}
elsif ($status == 2){
    print "CRITICAL - $returnstring|$perfdata\n";
}
elsif ($status == 3){
    print "UNKNOWN - $returnstring|$perfdata\n";
}
else{
    print "No response from SNMP agent.\n";
}
 
exit $status;


####################################################################
# This is where we gather data via SNMP and return results         #
####################################################################

sub main {

    #######################################################
 
    if (!defined($s->get_request($oid_upstype))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID UPSTYPE does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
         $upstype = $s->var_bind_list()->{$_};
    }
    #######################################################
 
    if (!defined($s->get_request($oid_battery_capacity))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID BATTERY CAPACITY does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
         $battery_capacity = $s->var_bind_list()->{$_};
    }
    #######################################################
 
    if (!defined($s->get_request($oid_output_status))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID OUTPUT STATUS does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
         $output_status = $s->var_bind_list()->{$_};
    }
    #######################################################
 
    if (!defined($s->get_request($oid_output_current))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID OUTPUT CURRENT does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
        $output_current = $s->var_bind_list()->{$_};
    }
    #######################################################

    # special.. added for SMART-UPS 2200 
    if (defined($s->get_request($oid_current_load_wh)))  {
      if ( $oid_current_load_wh =~ /noSuchInstance/ ) {
	     	foreach ($s->var_bind_names()) {
        		$output_current_load_wh = $s->var_bind_list()->{$_};
		}
      }
    }

	# some useful stuff
    if (defined($s->get_request($oid_firmware))) {
	foreach ($s->var_bind_names()) {
              	$firmware = $s->var_bind_list()->{$_};
        }
    }
    if ( defined (  $s->get_request($oid_serial_number))) {
	foreach ($s->var_bind_names()) {
               	$serial_number = $s->var_bind_list()->{$_};
	}
    }
    if ( defined (  $s->get_request($oid_manufacture_date))) {
	foreach ($s->var_bind_names()) {
                $manufacture_date = $s->var_bind_list()->{$_};
	}
    }

	# external temperature sensor,
    if ( defined($with_external_sensor) ) {
	if (!defined($s->get_request($oid_exttemperature))) {
        	if (!defined($s->get_request($oid_sysDescr))) {
	            $returnstring = "SNMP agent not responding";
        	    $status = 1;
	            return 1;
        	}
	        else {
        	    $returnstring = "SNMP OID EXT TEMPERATURE does not exist, is there any sensor connected?";
	            $status = 1;
        	    return 1;
	        }
    	}
	foreach ($s->var_bind_names()) {
        	$exttemperature = $s->var_bind_list()->{$_};
	}
    }

    #######################################################

    if (!defined($s->get_request($oid_output_load))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID OUTPUT LOAD does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
         $output_load = $s->var_bind_list()->{$_};
    }
    #######################################################
    
    if (!defined($s->get_request($oid_battery_replacment))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID BATTERY REPLACEMENT does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
         $battery_replacement = $s->var_bind_list()->{$_};
    }

    #######################################################

    if (!defined($s->get_request($oid_remaining_time))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID REMAINING TIME does not exist";
            $status = 1;
            return 1;
        }
    }
    foreach ($s->var_bind_names()) {
        $remaining_time = $s->var_bind_list()->{$_}; # returns (days),(hours),(minutes),seconds
    }

    #######################################################
  
    if (!defined($s->get_request($oid_battemperature))) {
        if (!defined($s->get_request($oid_sysDescr))) {
            $returnstring = "SNMP agent not responding";
            $status = 1;
            return 1;
        }
        else {
            $returnstring = "SNMP OID BATTERY TEMPERATURE does not exist";
            $status = 1;
            return 1;
        }
    }
     foreach ($s->var_bind_names()) {
         $battemperature = $s->var_bind_list()->{$_};
    }

    #######################################################
 
    $returnstring = "";
    $status = 0;
    $perfdata = "";

    if (defined($oid_upstype)) {
        $returnstring = "$upstype - ";
    }

    if ( $battery_replacement == 2 ) {
        $returnstring = $returnstring . "CRIT BATTERY REPLACEMENT NEEDED - ";
        $status = 2;
    }

    given ( $battery_capacity ) {
      when ( $_ < $battery_capacity_crit) {
        $returnstring = $returnstring . "CRIT BATTERY CAPACITY $battery_capacity% - ";
        $status = 2;
      }
      when ( $_ < $battery_capacity_warn ) {
        $returnstring = $returnstring . "WARN BATTERY CAPACITY $battery_capacity% - ";
        $status = 1 if ( $status != 2 );
      }
      when ( $_ <= 100) {
        $returnstring = $returnstring . "BATTERY CAPACITY $battery_capacity% - ";
      }
      default {
        $returnstring = $returnstring . "UNKNOWN BATTERY CAPACITY! - ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
      }
    }

    given($output_status) {
      when (2) { $returnstring = $returnstring . "STATUS NORMAL - "; }
      when (3) {
        $returnstring = $returnstring . "UPS RUNNING ON BATTERY! - ";
        $status = 1 if ( $status != 2 );
      }
      when (6 || 9 ) {
        $returnstring = $returnstring . "UPS RUNNING ON BYPASS! - ";
        $status = 1 if ( $status != 2 );
      }
      when (10) {
        $returnstring = $returnstring . "HARDWARE FAILURE UPS RUNNING ON BYPASS! - ";
        $status = 1 if ( $status != 2 );
      }
      default {
        $returnstring = $returnstring . "UNKNOWN OUTPUT STATUS! - ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
      }
    }

    
    given ( $output_load ) {
      when ( $_ > $output_load_crit) {
        $returnstring = $returnstring . "CRIT OUTPUT LOAD $output_load% - ";
        $perfdata = $perfdata . "'load'=${output_load}%;$output_load_warn;$output_load_crit;; ";
        $status = 2;
      }
      when ( $_ > $output_load_warn) {
        $returnstring = $returnstring . "WARN OUTPUT LOAD $output_load% - ";
        $perfdata = $perfdata . "'load'=${output_load}%;$output_load_warn;$output_load_crit;; ";
        $status = 1 if ( $status != 2 );
      }
      when ($_ >= 0) {
        $returnstring = $returnstring . "OUTPUT LOAD $output_load% - ";
        $perfdata = $perfdata . "'load'=${output_load}%;$output_load_warn;$output_load_crit;; ";
      }
      default {
        $returnstring = $returnstring . "UNKNOWN OUTPUT LOAD! - ";
        $perfdata = $perfdata . "'load'=NAN ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
      }
    }

    # battery temperature
    given ( $battemperature ) {
      when ( $_ > $battemperature_crit ) {
        $returnstring = $returnstring . "CRIT BATT TEMP $battemperature C - ";
        $perfdata = $perfdata . "'temp'=${battemperature};$battemperature_warn;$battemperature_crit;; ";
        $status = 2;
      }
      when ( $_ > $battemperature_warn ) {
        $returnstring = $returnstring . "WARN BATT TEMP $battemperature C - ";
        $perfdata = $perfdata . "'temp'=${battemperature};$battemperature_warn;$battemperature_crit;; ";
        $status = 1 if ( $status != 2 );
      }
      when ($_ >= 0 ) {
        $returnstring = $returnstring . "BATT TEMP $battemperature C - ";
        $perfdata = $perfdata . "'temp'=${battemperature};$battemperature_warn;$battemperature_crit;; ";
      }
      default {
        $returnstring = $returnstring . "UNKNOWN BATT TEMP! - ";
        $perfdata = $perfdata . "'temp'=NAN ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
      }
    }

    # external temperature
    if ( defined ( $exttemperature ) && $exttemperature !~ /noSuchInstance/ ) {
       given ( $exttemperature ) {
          when ( $_ > $exttemperature_crit) {
            $returnstring = $returnstring . "CRIT EXT TEMP $exttemperature C - ";
            $perfdata = $perfdata . "'exttemp'=${exttemperature};$exttemperature_warn;$exttemperature_crit;; ";
            $status = 2;
          }
          when ( $_ > $exttemperature_warn ) {
            $returnstring = $returnstring . "WARN EXT TEMP $exttemperature C - ";
            $perfdata = $perfdata . "'exttemp'=${exttemperature};$exttemperature_warn;$exttemperature_crit;; ";
            $status = 1 if ( $status != 2 );
          }
          when ( $_ >= 0 ) {
            $returnstring = $returnstring . "EXT TEMP $exttemperature C - ";
            $perfdata = $perfdata . "'exttemp'=${exttemperature};$exttemperature_warn;$exttemperature_crit;; ";
          }
          default {
            $returnstring = $returnstring . "UNKNOWN EXT TEMP! - ";
            $perfdata = $perfdata . "'exttemp'=NAN ";
            $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
          }
       }
    }

    # remaining time
    if ( defined ( $remaining_time ) ) {
	# convert time to minutes
	my @a = split(/ /,$remaining_time);
	my $timeUnit = @a[1];
	my $minutes = 0;

	if ( $timeUnit =~ /hour/ ) {
		# hours returned
		my @minutesArray = split(/:/,@a[2]);
		$minutes = @a[0] * 60;
		$minutes = $minutes + @minutesArray[0];
	} elsif ( $timeUnit =~ /minute/ ) {
		# minutes returned
		$minutes = @a[0];
	} else {
		# seconds returned?
		$minutes = 0;
	}

        given ( $minutes ) {
	  when( $_ <= $remaining_time_crit ) {
		$returnstring = $returnstring . "CRIT $minutes MINUTES REMAINING";
	       	$status = 2;
	  } 
          when ( $_ <= $remaining_time_warn ) {
		$returnstring = $returnstring . "WARN $minutes MINUTES REMAINING";
	       	$status = 1;
	  } 
          default {
		$returnstring = $returnstring . "$minutes MINUTES REMAINING";
	  }
        }
	$perfdata = $perfdata . "'remaining_sec'=" . $minutes*60 . "s;" . $remaining_time_warn*60 . ";" . $remaining_time_crit*60 . ";0; ";
    }

    # load in watthour
    if ( defined ($output_current_load_wh) ) {	
	    	$perfdata = $perfdata . "'loadwh'=${output_current_load_wh}Wh;;;; ";
   		$returnstring = $returnstring . " - CURRENT LOAD $output_current_load_wh Wh";
    }

    $returnstring = $returnstring . "\nFIRMWARE: $firmware - MANUFACTURE DATE: $manufacture_date - SERIAL: $serial_number";
}

####################################################################
# snmp session stuff
####################################################################

sub get_snmp_session {
  my $ip        = $_[0];
  my $community = $_[1];
  my $version   = $_[2];
  my ($session, $error) = Net::SNMP->session(
             	-hostname  => $ip,
             	-community => $community,
             	-port      => 161,
             	-timeout   => 5,
             	-retries   => 3,
		-debug	   => $net_snmp_debug_level,
		-version   => $version,
              );
  return ($session, $error);
} # end get snmp session

# SNMP V3 with auth+priv
sub get_snmp_session_v3 {
  my $ip        	= $_[0];
  my $user_name		= $_[1];
  my $auth_password 	= $_[2];
  my $auth_prot		= $_[3];
  my $priv_password 	= $_[4];
  my $priv_prot 	= $_[5];
  my ($session, $error) = Net::SNMP->session(
             	-hostname  	=> $ip,
             	-port      	=> 161,
             	-timeout   	=> 5,
             	-retries   	=> 3,
		-debug	   	=> $net_snmp_debug_level,
		-version   	=> 3,
		-username  	=> $user_name,
		-authpassword 	=> $auth_password,
		-authprotocol 	=> $auth_prot,
		-privpassword 	=> $priv_password,
		-privprotocol 	=> $priv_prot,
              );
  return ($session, $error);
} # end get snmp session

####################################################################
# Arguments
####################################################################
sub parse_args
{
	my $ip = "";
	my $version = "2";
	my $community = "public";	# v1/v2c
	my $battemperature_crit = "31";
	my $battemperature_crit = "33";
	
	my $user_name = "public"; 	# v3
	my $auth_password = "";		# v3
	my $auth_prot = "sha";		# v3 auth algo
	my $priv_password = "";		# v3
	my $priv_prot = "aes";		# v3 priv algo
	
	my $with_external_sensor = undef; # external sensor
	my $help = undef;

	pod2usage(-message => "UNKNOWN: No Arguments given", -exitval => 3, -verbose => 0) if ( !@ARGV );

	GetOptions(
		'host|H=s'		=> \$ip,
		'version|v:s'		=> \$version,
		'warntemp|w:s'		=> \$battemperature_warn,
		'crittemp|c:s'		=> \$battemperature_crit,
		'community|C:s' 	=> \$community,
		'externalsensor|S!' 	=> \$with_external_sensor,
		'username|U:s'  	=> \$user_name,
		'authpassword|A:s' 	=> \$auth_password,
		'authprotocol|a:s' 	=> \$auth_prot,
		'privpassword|X:s' 	=> \$priv_password,
		'privprotocol|x:s' 	=> \$priv_prot,
		'help|h|?!'		=> \$help,
	) or usage();

	usage() if $help;

  	return (
		$ip, $community, $battemperature_warn, $battemperature_crit, $version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot, $with_external_sensor
		); 
}	

####################################################################
# help and usage information                                       #
####################################################################

sub usage {
    print << "USAGE";
-----------------------------------------------------------------	 
Monitors APC SmartUPS via AP9617 SNMP management card.

Usage: -H <hostname> -C <community> [...]

Options: 
         -H     Hostname or IP address
         -S     with external sensor (like PowerNet)
         -w     Warning threshold for battery temperature
         -c     Critical threshold for battery temperature
   SNMPv1/2
         -C     Community (default is public)
   SNMPv3
         -A     Authentication password
         -a     Authentication protocl
         -X     Private password
         -x     Private procotol


	 
-----------------------------------------------------------------	 
Copyright 2004 Altinity Limited	 
	 
This program is free software; you can redistribute it or modify
it under the terms of the GNU General Public License
-----------------------------------------------------------------

USAGE
     exit 1;
}

