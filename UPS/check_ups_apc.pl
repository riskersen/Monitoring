#!/usr/bin/perl

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

use Net::SNMP;
use Getopt::Std;
# DEBUGGING PURPOSE 
#use Data::Dumper;

$script    = "check_ups_apc.pl";
$script_version = "1.3";

$version = "1";			# SNMP version
$timeout = 3;			# SNMP query timeout
# $warning = 100;			
# $critical = 150;
$status = 0;
$returnstring = "";
$perfdata = "";

$community = "public"; 		# Default community string

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
$battemperature_crit = 33;
$battemperature_warn = 31;
$exttemperature_crit = 30;
$exttemperature_warn = 26;
$battery_capacity_crit = 35;
$battery_capacity_warn = 65;

# Do we have enough information?
if (@ARGV < 1) {
     print "Too few arguments\n";
     usage();
}

getopts("h:H:C:w:c:S");
if ($opt_h){
    usage();
    exit(0);
}
if ($opt_H){
    $hostname = $opt_H;
}
else {
    print "No hostname specified\n";
    usage();
}
if ($opt_C){
    $community = $opt_C;
}

$with_external_sensor = defined $opt_S ? 1 : undef;


# Create the SNMP session
my ($s, $e) = Net::SNMP->session(
     -community  =>  $community,
     -hostname   =>  $hostname,
     -version    =>  $version,
     -timeout    =>  $timeout,
);

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
    if (defined($s->get_request($oid_current_load_wh))) {
	     	foreach ($s->var_bind_names()) {
        		$output_current_load_wh = $s->var_bind_list()->{$_};
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
    if ( $with_external_sensor ) {
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
    elsif ($battery_capacity < $battery_capacity_crit) {
        $returnstring = $returnstring . "CRIT BATTERY CAPACITY $battery_capacity% - ";
        $status = 2;
    }
    elsif ($battery_capacity < $battery_capacity_warn ) {
        $returnstring = $returnstring . "WARN BATTERY CAPACITY $battery_capacity% - ";
        $status = 1 if ( $status != 2 );
    }
    elsif ($battery_capacity <= 100) {
        $returnstring = $returnstring . "BATTERY CAPACITY $battery_capacity% - ";
    }
    else {
        $returnstring = $returnstring . "UNKNOWN BATTERY CAPACITY! - ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
    }

    if ($output_status eq "2"){
        $returnstring = $returnstring . "STATUS NORMAL - ";
    }
    elsif ($output_status eq "3"){
        $returnstring = $returnstring . "UPS RUNNING ON BATTERY! - ";
        $status = 1 if ( $status != 2 );
    }
    elsif ($output_status eq "9"){
        $returnstring = $returnstring . "UPS RUNNING ON BYPASS! - ";
        $status = 1 if ( $status != 2 );
    }
    elsif ($output_status eq "10"){
        $returnstring = $returnstring . "HARDWARE FAILURE UPS RUNNING ON BYPASS! - ";
        $status = 1 if ( $status != 2 );
    }
    elsif ($output_status eq "6"){
        $returnstring = $returnstring . "UPS RUNNING ON BYPASS! - ";
        $status = 1 if ( $status != 2 );
    }
    else {
        $returnstring = $returnstring . "UNKNOWN OUTPUT STATUS! - ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
    }


    if ($output_load > $output_load_crit) {
        $returnstring = $returnstring . "CRIT OUTPUT LOAD $output_load% - ";
        $perfdata = $perfdata . "'load'=${output_load}%;$output_load_warn;$output_load_crit;; ";
        $status = 2;
    }
    elsif ($output_load > $output_load_warn) {
        $returnstring = $returnstring . "WARN OUTPUT LOAD $output_load% - ";
        $perfdata = $perfdata . "'load'=${output_load}%;$output_load_warn;$output_load_crit;; ";
        $status = 1 if ( $status != 2 );
    }
    elsif ($output_load >= 0) {
        $returnstring = $returnstring . "OUTPUT LOAD $output_load% - ";
        $perfdata = $perfdata . "'load'=${output_load}%;$output_load_warn;$output_load_crit;; ";
    }
    else {
        $returnstring = $returnstring . "UNKNOWN OUTPUT LOAD! - ";
        $perfdata = $perfdata . "'load'=NAN ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
    }

    # battery temperature
    if ($battemperature > $battemperature_crit) {
        $returnstring = $returnstring . "CRIT BATT TEMP $battemperature C - ";
        $perfdata = $perfdata . "'temp'=${battemperature}C;$battemperature_warn;$battemperature_crit;; ";
        $status = 2;
    }
    elsif ($battemperature > $battemperature_warn) {
        $returnstring = $returnstring . "WARN BATT TEMP $battemperature C - ";
        $perfdata = $perfdata . "'temp'=${battemperature}C;$battemperature_warn;$battemperature_crit;; ";
        $status = 1 if ( $status != 2 );
    }
    elsif ($battemperature >= 0) {
        $returnstring = $returnstring . "BATT TEMP $battemperature C - ";
        $perfdata = $perfdata . "'temp'=${battemperature}C;$battemperature_warn;$battemperature_crit;; ";
    }
    else {
        $returnstring = $returnstring . "UNKNOWN BATT TEMP! - ";
        $perfdata = $perfdata . "'temp'=NAN ";
        $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
    }

    # external temperature
    if ( defined ( $exttemperature ) ) {
        if ($exttemperature > $exttemperature_crit) {
            $returnstring = $returnstring . "CRIT EXT TEMP $exttemperature C - ";
            $perfdata = $perfdata . "'exttemp'=${exttemperature}C;$exttemperature_warn;$exttemperature_crit;; ";
            $status = 2;
        }
        elsif ($exttemperature > $exttemperature_warn) {
            $returnstring = $returnstring . "WARN EXT TEMP $exttemperature C - ";
            $perfdata = $perfdata . "'exttemp'=${exttemperature}C;$exttemperature_warn;$exttemperature_crit;; ";
            $status = 1 if ( $status != 2 );
        }
        elsif ($exttemperature >= 0) {
            $returnstring = $returnstring . "EXT TEMP $exttemperature C - ";
            $perfdata = $perfdata . "'exttemp'=${exttemperature}C;$exttemperature_warn;$exttemperature_crit;; ";
        }
        else {
            $returnstring = $returnstring . "UNKNOWN EXT TEMP! - ";
            $perfdata = $perfdata . "'exttemp'=NAN ";
            $status = 3 if ( ( $status != 2 ) && ( $status != 1 ) );
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

	if ( $minutes <= $remaining_time_crit ) {
		$returnstring = $returnstring . "CRIT $minutes MINUTES REMAINING";
	       	$status = 2;
	} elsif ( $minutes <= $remaining_time_warn ) {
		$returnstring = $returnstring . "WARN $minutes MINUTES REMAINING";
	       	$status = 1;
	} else {
		$returnstring = $returnstring . "$minutes MINUTES REMAINING";
	}

	$perfdata = $perfdata . "'remaining_minutes'=${minutes}min;;$remaining_time_crit;; ";
    }

    # load in watthour
    if ( defined ($output_current_load_wh) ) {	
	    	$perfdata = $perfdata . "'loadwh'=${output_current_load_wh}Wh;;;; ";
   		$returnstring = $returnstring . " - CURRENT LOAD $output_current_load_wh Wh";
    }

    $returnstring = $returnstring . "\nFIRMWARE: $firmware - MANUFACTURE DATE: $manufacture_date - SERIAL: $serial_number";
}

####################################################################
# help and usage information                                       #
####################################################################

sub usage {
    print << "USAGE";
-----------------------------------------------------------------	 
$script v$script_version

Monitors APC SmartUPS via AP9617 SNMP management card.

Usage: $script -H <hostname> -C <community> [...]

Options: -H 	Hostname or IP address
         -C 	Community (default is public)
         -S 	with external sensor (like PowerNet)
	 
-----------------------------------------------------------------	 
Copyright 2004 Altinity Limited	 
	 
This program is free software; you can redistribute it or modify
it under the terms of the GNU General Public License
-----------------------------------------------------------------

USAGE
     exit 1;
}



