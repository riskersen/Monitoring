#!/usr/bin/perl
# nagios: -epn
# This Plugin checks the cluster state of FortiGate
#
# Tested on: FortiGate 100D / FortiGate 300C (both 5.0.3)
# Tested on: FortiGate 200B (5.0.6), Fortigate 800C (5.2.2)
#
# Author: Oliver Skibbe (oliskibbe (at) gmail.com)
# Date: 2015-04-08
#
# Changelog:
# Release 1.0 (2013)
# - initial release (cluster, cpu, memory, session support)
# - added vpn support, based on check_fortigate_vpn.pl: Copyright (c) 2009 Gerrit Doornenbal, g(dot)doornenbal(at)hccnet(dot)nl
# Release 1.4 (2015-02-26) Oliver Skibbe (oliskibbe (at) gmail.com)
# - some code cleanup
# - whitespace fixes
# - added snmp debug
# - added SNMP V3 support
# Release 1.4.1 (2015-02-26) Oliver Skibbe (oliskibbe (at) gmail.com)
# - updated POD
# - fixed line 265: $help_serials[$#help_serials] construct
# - fixed snmp error check
# Release 1.4.1 (2015-02-26) Oliver Skibbe (oliskibbe (at) gmail.com)
# - removing any non digits in warn/crit
# Release 1.4.2 (2015-03-04) Oliver Skibbe (oliskibbe (at) gmail.com)
# - removing any non digits in returning health value at sub get_health_value
# Release 1.4.3 (2015-03-11) Mikael Cam (mikael (at) nateis.com)
# - added WiFi AC (controller) to wtp access points monitoring support
# Release 1.4.4 (2015-03-11) Oliver Skibbe (oliskibbe (at) gmail.com)
# - fixed white spaces
# - added string compare for noSuchInstance
# - fixed enumeration return state
# Release 1.4.5 (2015-03-30) Oliver Skibbe (oliskibbe (at) gmail.com)
# - fixed description - username was missing
# Release 1.4.6 (2015-04-01) Alexandre Rigaud (arigaud.prosodie.cap (at) free.fr)
# - added path option
# - minor bugfixes (port option missing in snmp subs, wrong oid device s/n)
# Release 1.5 (2015-04-08) Oliver Skibbe (oliskibbe (at) gmail.com)
# - added check for cluster synchronization state
# - temp disabled ipsec vpn check, OIDs seem missing
# Release 1.5.1 (2015-04-14) Alexandre Rigaud (arigaud.prosodie.cap (at) free.fr)
# - enabled ipsec vpn check
# - added check hardware
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# If you wish to receive a copy of the GNU General Public License,
# write to the Free Software Foundation, Inc.,
# 59 Temple Place - Suite 330, Boston, MA 02111-130

use strict;
use Net::SNMP;
use List::Compare;
use Switch;
use Getopt::Long qw(:config no_ignore_case bundling);
use Pod::Usage;
use Socket;

my $script = "check_fortigate.pl";
my $script_version = "1.5.1";

# Parse out the arguments...
my ($ip, $port, $community, $type, $warn, $crit, $slave, $pri_serial, $reset_file, $mode, $vpnmode,
    $version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot, $path) = parse_args();

# Initialize variables....
my $net_snmp_debug_level = 0x00; # See http://search.cpan.org/~dtown/Net-SNMP-v6.0.1/lib/Net/SNMP.pm#debug()_-_set_or_get_the_debug_mode_for_the_module

# for more information.
my %status = (     # Enumeration for the output Nagios states
  'OK'       => '0',
  'WARNING'  => '1',
  'CRITICAL' => '2',
  'UNKNOWN'  => '3'
);

my $session = "";
my $error = "";

## SNMP ##
if ( $version == 3 ) {
  ($session, $error) = get_snmp_session_v3(
                            $ip,
                            $user_name,
                            $auth_password,
                            $auth_prot,
                            $priv_password,
                            $priv_prot,
                            $port,
                       ); # Open SNMP connection...
} else {
  ($session, $error) = get_snmp_session(
                            $ip,
                            $community,
                            $port,
                       ); # Open SNMP connection...
}

if ( $error ne "" ) {
  print "\n$error\n";
  exit(1);
}

## OIDs ##
my $oid_unitdesc         = ".1.3.6.1.2.1.1.1.0";                   # Location of Fortinet device description... (String)
my $oid_serial           = ".1.3.6.1.4.1.12356.100.1.1.1.0";       # Location of Fortinet serial number (String)
my $oid_cpu              = ".1.3.6.1.4.1.12356.101.13.2.1.1.3";    # Location of cluster member CPU (%)
my $oid_net              = ".1.3.6.1.4.1.12356.101.13.2.1.1.5";    # Location of cluster member Net (kbps)
my $oid_mem              = ".1.3.6.1.4.1.12356.101.13.2.1.1.4";    # Location of cluster member Mem (%)
my $oid_ses              = ".1.3.6.1.4.1.12356.101.13.2.1.1.6";    # Location of cluster member Sessions (int)

# Cluster
my $oid_cluster_type     = ".1.3.6.1.4.1.12356.101.13.1.1.0";      # Location of Fortinet cluster type (String)
my $oid_cluster_serials  = ".1.3.6.1.4.1.12356.101.13.2.1.1.2";    # Location of Cluster serials (String)
my $oid_cluster_sync_state = ".1.3.6.1.4.1.12356.101.13.2.1.1.12"; # Location of cluster sync state (int)

# VPN OIDs
# XXX to be checked
my $oid_ActiveSSL         = ".1.3.6.1.4.1.12356.101.12.2.3.1.2.1"; # Location of Fortinet firewall SSL VPN Tunnel connection count
my $oid_ActiveSSLTunnel   = ".1.3.6.1.4.1.12356.101.12.2.3.1.6.1"; # Location of Fortinet firewall SSL VPN Tunnel connection count
my $oid_ipsectuntableroot = ".1.3.6.1.4.1.12356.101.12.2.2.1";     # Table of IPSec VPN tunnels
my $oidf_tunstatus        = ".20";                                 # Location of a tunnel's connection status
my $oidf_tunndx           = ".1";                                  # Location of a tunnel's index...
my $oidf_tunname          = ".3";                                  # Location of a tunnel's name...

# WTP
my $oid_apstatetableroot  = ".1.3.6.1.4.1.12356.101.14.4.4.1.7";   # Represents the connection state of a WTP to AC : offLine(1), onLine(2), downloadingImage(3), connectedImage(4), other(0)
my $oid_wtpsessions       = ".1.3.6.1.4.1.12356.101.14.2.5.0";     # Represents the number of WTPs that are connecting to the AC.
my $oid_wtpmanaged        = ".1.3.6.1.4.1.12356.101.14.2.4.0";     # Represents the number of WTPs being managed on the AC
my $oid_apipaddrtableroot = ".1.3.6.1.4.1.12356.101.14.4.4.1.3" ;  # Represents the IP address of a WTP
my $oid_apidtableroot     = ".1.3.6.1.4.1.12356.101.14.4.4.1.1" ;  # Represents the unique identifier of a WTP

# HARDWARE SENSORS
# "A list of device specific hardware sensors and values. Because different devices have different hardware sensor capabilities, this table may or may not contain any values."
my $oid_hwsensorid       = ".1.3.6.1.4.1.12356.101.4.3.2.1.1";     # Hardware Sensor index
my $oid_hwsensorname     = ".1.3.6.1.4.1.12356.101.4.3.2.1.2";     # Hardware Sensor Name
my $oid_hwsensorvalue    = ".1.3.6.1.4.1.12356.101.4.3.2.1.3";     # Hardware Sensor Value
my $oid_hwsensoralarm    = ".1.3.6.1.4.1.12356.101.4.3.2.1.4";     # Hardware Sensor Alarm (not all sensors have alarms!)

## Stuff ##
my $return_state;                                     # return state
my $return_string;                                    # return string
my $filename = $path . "/" . $ip;                     # file name to store serials
my $oid;                                              # helper var
my $value;                                            # helper var
my $perf;                                             # performance data

# Check SNMP connection and get the description of the device...
my $curr_device = get_snmp_value($session, $oid_unitdesc);
# Check SNMP connection and get the serial of the device...
my $curr_serial = get_snmp_value($session, $oid_serial);

switch ( lc($type) ) {
  case "cpu" { ($return_state, $return_string) = get_health_value($oid_cpu, "CPU", "%"); }
  case "mem" { ($return_state, $return_string) = get_health_value($oid_mem, "Memory", "%"); }
  case "net" { ($return_state, $return_string) = get_health_value($oid_net, "Network", ""); }
  case "ses" { ($return_state, $return_string) = get_health_value($oid_ses, "Session", ""); }
  case "vpn" { ($return_state, $return_string) = get_vpn_state(); }
  case "wtp" { ($return_state, $return_string) = get_wtp_state("%"); }
  case "hw" { ($return_state, $return_string) = get_hw_state("%"); }
  else { ($return_state, $return_string) = get_cluster_state(); }
}

# Close the connection
close_snmp_session($session);

# exit with a return code matching the return_state...
print $return_string."\n";
exit($status{$return_state});

########################################################################
## Subroutines below here....
########################################################################
sub get_snmp_session {
  my $ip = $_[0];
  my $community = $_[1];
  my $port = $_[2];
  my ($session, $error) = Net::SNMP->session(
                              -hostname  => $ip,
                              -community => $community,
                              -port      => $port,
                              -timeout   => 10,
                              -retries   => 3,
                              -debug     => $net_snmp_debug_level,
                              -version   => 2,
                              -translate => [-timeticks => 0x0] # disable timetick translation
                          );

  return ($session, $error);
} # end get snmp session

# SNMP V3 with auth+priv
sub get_snmp_session_v3 {
  my $ip = $_[0];
  my $user_name = $_[1];
  my $auth_password = $_[2];
  my $auth_prot = $_[3];
  my $priv_password = $_[4];
  my $priv_prot = $_[5];
  my $port = $_[6];
  my ($session, $error) = Net::SNMP->session(
                              -hostname     => $ip,
                              -port         => $port,
                              -timeout      => 10,
                              -retries      => 3,
                              -debug        => $net_snmp_debug_level,
                              -version      => 3,
                              -username     => $user_name,
                              -authpassword => $auth_password,
                              -authprotocol => $auth_prot,
                              -privpassword => $priv_password,
                              -privprotocol => $priv_prot,
                              -translate    => [-timeticks => 0x0] #schaltet Umwandlung von Timeticks in Zeitformat aus
                          );
  return ($session, $error);
} # end get snmp session

sub get_health_value {
  my $label = $_[1];
  my $UOM = $_[2];
 
  if ( $slave == 1 ) {
    $oid = $_[0] . ".2";
    $label = "slave_" . $label;
  } else {
    $oid = $_[0] . ".1";
  }

  $value = get_snmp_value($session, $oid);

  # strip any leading or trailing non zeros
  $value =~ s/\D*(\d+)\D*/$1/g;

  if ( $value >= $crit ) {
    $return_state = "CRITICAL";
    $return_string = $label . " is critical: " . $value . $UOM;
  } elsif ( $value >= $warn ) {
    $return_state = "WARNING";
    $return_string = $label . " is warning: " . $value . $UOM;
  } else {
    $return_state = "OK";
    $return_string = $label . " is okay: " . $value. $UOM;
  }

  $perf = "|'" . lc($label) . "'=" . $value . $UOM . ";" . $warn . ";" . $crit;
  $return_string = $return_state . ": " . $curr_device . " (Master: " . $curr_serial .") " . $return_string . $perf;

  return ($return_state, $return_string);
} # end health value

sub get_cluster_state {
  my @help_serials; # helper array

  # before launch snmp requests, test write access on path directory
  if ( ! -w $path ) {
        $return_state = "CRITICAL";
        $return_string = "$return_state: Error writing on $path directory, permission denied";
        return ($return_state, $return_string);
  }

  # get all cluster member serials
  my %snmp_serials = %{get_snmp_table($session, $oid_cluster_serials)};
  my $cluster_type = get_snmp_value($session, $oid_cluster_type);
  my %cluster_types = (
                        1 => "Standalone", 
                        2 => "Active/Active", 
                        3 => "Active/Passive"
  );
  my %cluster_sync_states = (
                        0 => 'Not Synchronized',
                        1 => 'Synchronized'
  );
  my $sync_string = "Sync-State: " . $cluster_sync_states{1};

  # first time, write cluster members to helper file
  if ( ! -e $filename || $reset_file ) {
    # open file handle to write (create/truncate)
    open (SERIALHANDLE,"+>$filename") || die "Error while creating $filename";
    # write serials to file
    while (($oid, $value) = each (%snmp_serials)) {
      print (SERIALHANDLE $value . "\n");
    }
  }

  # snmp serials
  while (($oid, $value) = each (%snmp_serials)) {
    chomp; # remove "\n" if exists
    push @help_serials, $value;
  }

  # if less then 2 nodes found: critical
  if ( scalar(@help_serials) < 2 ) {
    $return_string = "HA (" . $cluster_types{$cluster_type} . ") inactive, single node found: " . $curr_serial;
    $return_state = "CRITICAL";
  # else check if there are differences in ha nodes
  } else {
    # open existing serials
    open ( SERIALHANDLE, "$filename") || die "Error while opening file $filename";
    my @file_serials = <SERIALHANDLE>; # push lines into file_serials
    chomp(@file_serials);              # remove "\n" if exists in array elements
    close (SERIALHANDLE);              # close file handle

    # compare serial arrays
    my $comparedList = List::Compare->new('--unsorted', \@help_serials, \@file_serials);
    if ( $comparedList->is_LequivalentR ) {
      $return_string = "HA (" . $cluster_types{$cluster_type} . ") is active";
      $return_state = "OK";
    } else {
      $return_string = "Unknown node in active HA (" . $cluster_types{$cluster_type} . ") found, maybe a --reset is nessessary?";
      $return_state = "WARNING";
    } # end compare serial list
  } # end scalar count

  if ( $return_state eq "OK" ) {
    my %cluster_sync_state = %{get_snmp_table($session, $oid_cluster_sync_state)};
    while (($oid, $value) = each (%cluster_sync_state)) {
      if ( $value == 0 ) {
         $sync_string = "Sync-State: " . $cluster_sync_states{$value};
         $return_state = "CRITICAL";
         last;
      }
    }
  }
  # if preferred master serial is not master
  if ( $pri_serial && ( $pri_serial ne $curr_serial ) ) {
    $return_string = $return_string . ", preferred master " . $pri_serial . " is not master!";
    $return_state = "CRITICAL";
  }

  # Write an output string...
  $return_string = $return_state . ": " . $curr_device . " (Master: " . $curr_serial . ", Slave: " . $help_serials[$#help_serials] . "): " . $return_string . ", " . $sync_string;
  return ($return_state, $return_string);
} # end cluster state

sub get_vpn_state {
  my $ipstunsdown = 0;
  my $ipstuncount = 0;
  my $ipstunsopen = 0;
  my $ActiveSSL = 0;
  my $ActiveSSLTunnel = 0;
  my $return_string_errors = "";

  # Enumeration for the tunnel up/down states
  my %entitystate = ( 
                      '1' => 'down',
                      '2' => 'up' 
                    );
  $return_state = "OK";

  # Unless specifically requesting IPSec checks only, do an SSL connection check
  if ($vpnmode ne "ipsec"){
    $ActiveSSL = get_snmp_value($session, $oid_ActiveSSL);
    $ActiveSSLTunnel = get_snmp_value($session, $oid_ActiveSSLTunnel);
  }
  # Unless specifically requesting SSL checks only, do an IPSec tunnel check
  if ($vpnmode ne "ssl") {
  # N/A as of 2015    
#    # Get just the top level tunnel data
    my %tunnels = %{get_snmp_table($session, $oid_ipsectuntableroot . $oidf_tunndx)};

    while (($oid, $value) = each (%tunnels)) {
      #Bump the total tunnel count
      $ipstuncount++;
      #If the tunnel is up, bump the connected tunnel count
      if ( $entitystate{get_snmp_value($session, $oid_ipsectuntableroot . $oidf_tunstatus . "." . $ipstuncount)} eq "up" ) {
        $ipstunsopen++;
      } else {
        #Tunnel is down. Add it to the failed counter
        $ipstunsdown++;
        # If we're counting failures and/or monitoring, put together an output error string of the tunnel name and its status
        if ($mode >= 1){
        $return_string_errors .= ", ";
        $return_string_errors .= get_snmp_value($session, $oid_ipsectuntableroot . $oidf_tunname . "." . $ipstuncount)." ".$entitystate{get_snmp_value($session, $oid_ipsectuntableroot . $oidf_tunstatus . "." . $ipstuncount)};
        }
      } # end tunnel count
    }
  }
  #Set Unitstate
  if (($mode >= 2 ) && ($vpnmode ne "ssl")) {
    if ($ipstunsdown == 1) { $return_state = "WARNING"; }
    if ($ipstunsdown >= 2) { $return_state = "CRITICAL"; }
  }

  # Write an output string...
  $return_string = $return_state . ": " . $curr_device . " (Master: " . $curr_serial .")";

  if ($vpnmode ne "ipsec") {
    #Add the SSL tunnel count
    $return_string = $return_string . ": Active SSL-VPN Connections/Tunnels: " . $ActiveSSL."/".$ActiveSSLTunnel."";
  }
  if ($vpnmode ne "ssl") {
    #Add the IPSec tunnel count and any errors....
    $return_string = $return_string . ": IPSEC Tunnels: Configured/Active: " . $ipstuncount . "/" . $ipstunsopen. " " . $return_string_errors;
  }
  # Create performance data
  $perf="|'ActiveSSL-VPN'=".$ActiveSSL." 'ActiveIPSEC'=".$ipstunsopen;
  $return_string .= $perf;

  # Check to see if the output string contains either "unkw", "WARNING" or "down", and set an output state accordingly...
  if($return_string =~/uknw/){
    $return_state = "UNKNOWN";
  }
  if($return_string =~/WARNING/){
    $return_state = "WARNING";
  }
  if($return_string =~/down/){
    $return_state = "CRITICAL";
  }
  return ($return_state, $return_string);
} # end vpn state

sub get_wtp_state {
  # Connection state of a WTP to AC : offLine(1), onLine(2), downloadingImage(3), connectedImage(4), other(0)
  my $UOM = $_[0];
  my $wtpcount = 0;
  my $wtpoffline = 0;
  my $wtponline = 0;
  my $k;
  my $return_string_errors = "";
  my $downwtp = "";

  # Enumeration for the wtp up/down states
  my %entitystate = ( 
                       '1' => 'down', 
                       '2' => 'up' 
                    );

  $return_state = "OK";
  
  $wtpcount = get_snmp_value($session, $oid_wtpmanaged);
  
  if ($wtpcount > 0) {
    my %wtp_id_table = %{get_snmp_table($session, $oid_apidtableroot)};
    my %wtp_ipaddr_table = %{get_snmp_table($session, $oid_apipaddrtableroot)};
    my %wtp_state_table = %{get_snmp_table($session, $oid_apstatetableroot)};
    
    foreach $k (keys(%wtp_state_table)) {
      if ( $entitystate{$wtp_state_table{$k}} eq "up" )  {
        $wtponline++;
      } else {
        $wtpoffline ++;
        my $apk = $k;
        $apk =~ s/^$oid_apstatetableroot//;

        if ($downwtp ne "") { $downwtp .=","; }
        $downwtp .= get_snmp_value($session, $oid_apidtableroot . $apk)."/".inet_ntoa( pack( "N", hex( get_snmp_value($session, $oid_apipaddrtableroot . $apk)) ) );
      } # end wtp state up down
    } # end wtp while
  
    $value = ($wtpoffline / $wtpcount) * 100;
      
    if ( $value >= $crit ) {
      $return_state = "CRITICAL";
    } elsif ( $value >= $warn ) {
      $return_state = "WARNING";
    }
  
    $return_string = "$return_state - $wtpoffline offline WiFi access point(s) over $wtpcount found : ".(sprintf("%.2f",$value))." $UOM : ".$downwtp;
  } else  {
    $return_string = "No wtp configured.";
  }
  
  return ($return_state, $return_string);
} # end wtp state

sub get_hw_state{
   my $k;
   my %hw_name_table = %{get_snmp_table($session, $oid_hwsensorname)};


   my %hwsensoralarmstatus= (
      0 => 'False',
      1 => 'True'
   );

   $return_state = "OK";
   $return_string = "All components are in appropriate state";
   foreach $k (keys(%hw_name_table)) {
         my $unit;
         my $hw_name = $hw_name_table{$k};
         my $sensoralr;
         if ($hw_name  =~ /Fan\s/) { $unit = "RPM"; }
         elsif ($hw_name  =~ /^DTS\sCPU[0-9]?|Temp|LM75|^ADT74(90|62)\s.+/) { $unit = "C"; }
         elsif ($hw_name  =~ /^VCCP|^P[13]V[138]_.+|^AD[_\+].+|^\+(12|5|3\.3|1\.5|1\.25|1\.1)V|^PS[0-9]\s(VIN|VOUT|12V\sOutput)|^AD[_\+].+|^INA219\sPS[0-9]\sV(sht|bus)/) { $unit = "V"; }
         else { $unit = "?"; }
         my @num = split(/\./, $k);
         my $sensorid = $num[$#num];
         my $oid_alarm = $oid_hwsensoralarm . ".$sensorid";
         my $oid_value = $oid_hwsensorvalue . ".$sensorid";
         $sensoralr = get_snmp_value($session, $oid_alarm);
      if ($sensoralr == 1){
            my $sensorval = get_snmp_value($session, $oid_value);
            $return_string = "$hw_name alarm is $hwsensoralarmstatus{$sensoralr} ($sensorval $unit)";
          $return_state = "CRITICAL";
      }
   }
   return ($return_state, $return_string);
} # end hw state

sub close_snmp_session{
  my $session = $_[0];

  $session->close();
} # end close snmp session

sub get_snmp_value{
  my $session = $_[0];
  my $oid = $_[1];

  my (%result) = %{get_snmp_request($session, $oid) || die ("SNMP service is not available on ".$ip) };

  if ( ! %result ||  $result{$oid} =~ /noSuchInstance/ ) {
    $return_state = "UNKNOWN";

    print $return_state . ": OID $oid does not exist\n";
    exit($status{$return_state});
  }
  return $result{$oid};
} # end get snmp value

sub get_snmp_request{
  my $session = $_[0];
  my $oid = $_[1];

  my $sess_get_request = $session->get_request($oid);

  if ( ! defined($sess_get_request) ) {
    $return_state = "UNKNOWN";

    print $return_state . ": session get request failed\n";
    exit($status{$return_state});
  }

  return $sess_get_request;
} # end get snmp request

sub get_snmp_table{
  my $session = $_[0];
  my $oid = $_[1];

  my $sess_get_table = $session->get_table(
                       -baseoid =>$oid
  );

  if ( ! defined($sess_get_table) ) {
    $return_state = "UNKNOWN";

    print $return_state . ": session get table failed for $oid \n";
    exit($status{$return_state});
  }
  return $sess_get_table;
} # end get snmp table


sub parse_args {
  my $ip            = "";       # snmp host
  my $port          = 161;      # snmp port
  my $version       = "2";      # snmp version
  my $community     = "public"; # only for v1/v2c
  my $user_name     = "public"; # v3
  my $auth_password = "";       # v3
  my $auth_prot     = "sha";    # v3 auth algo
  my $priv_password = "";       # v3
  my $priv_prot     = "aes";    # v3 priv algo
  my $pri_serial    = "";       # primary fortinet serial no
  my $reset_file    = "";
  my $type          = "status";
  my $warn          = 80;
  my $crit          = 90;
  my $slave         = 0;
  my $vpnmode       = "both";
  my $mode          = 2;
  my $path          = "/usr/lib/nagios/plugins/FortiSerial";
  my $help          = 0;

  pod2usage(-message => "UNKNOWN: No Arguments given", -exitval => 3, -verbose => 0) if ( !@ARGV );

  GetOptions(
          'host|H=s'         => \$ip,
          'port|P=i'         => \$port,
          'version|v:s'      => \$version,
          'community|C:s'    => \$community,
          'username|U:s'     => \$user_name,
          'authpassword|A:s' => \$auth_password,
          'authprotocol|a:s' => \$auth_prot,
          'privpassword|X:s' => \$priv_password,
          'privprotocol|x:s' => \$priv_prot,
          'type|T=s'         => \$type,
          'serial|S:s'       => \$pri_serial,
          'vpnmode|V:s'      => \$vpnmode,
          'mode|M:s'         => \$mode,
          'warning|w:s'      => \$warn,
          'critical|c:s'     => \$crit,
          'slave|s:1'        => \$slave,
          'reset|R:1'        => \$reset_file,
          'path|p:s'         => \$path,
          'help|?!'          => \$help,
  ) or pod2usage(-exitval => 3, -verbose => 0);

  pod2usage(-exitval => 3, -verbose => 3) if $help;

  # removing any non digits
  $warn =~ s/\D*(\d+)\D*/$1/g;
  $crit =~ s/\D*(\d+)\D*/$1/g;

  return (
    $ip, $port, $community, $type, $warn, $crit, $slave, $pri_serial, $reset_file, $mode, $vpnmode,
    $version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot, $path
  );
}
__END__
=head1 NAME
Check Fortinet FortiGate Appliances
=head1 SYNOPSIS
=over
=item S<check_fortigate.pl -H -C -T [-w|-c|-S|-s|-R|-M|-V|-U|-A|-a|-X|-x-?]>
Options:
-H --host STRING or IPADDRESS Check interface on the indicated host
-P --port INTEGER Port of indicated host, defaults to 161
-v --version STRING SNMP Version, defaults to SNMP v2, v1-v3 supported
-T --type STRING CPU, MEM, Ses, VPN, wtp, Cluster, hw
-S --serial STRING Primary serial number
-s --slave get values of slave
-w --warning INTEGER Warning threshold, applies to cpu, mem, session wtp.
-c --critical INTEGER Critical threshold, applies to cpu, mem, session, wtp.
-R --reset Resets ip file (cluster only)
-M --mode STRING Output-Mode: 0 => just print, 1 => print and show failed tunnel, 2 => critical
-V --vpnmode STRING VPN-Mode: both => IPSec & SSL/OpenVPN, ipsec => IPSec only, ssl => SSL/OpenVPN only
-p --path STRING Path to store serial filenames, default /usr/lib/nagios/plugins/FortiSerial
SNMP v1/v2c only
-C --community STRING Community-String for SNMP, only at SNMP v1/v2c, defaults to public
SNMP v3 only
SNMP v3 only
-U --username STRING username 
-A --authpassword STRING auth password
-a --authprotocol STRING auth algorithm, defaults to sha
-X --privpassword STRING private password
-x --privprotocol STRING private algorithm, defaults to aes
-? --help Returns full help text
=back
=head1 OPTIONS
=over
=item B<-H|--host>
STRING or IPADDRESS - Check interface on the indicated host
=item B<-P|--port>
INTEGER - SNMP Port on the indicated host, defaults to 161
=item B<-v|--version>
INTEGER - SNMP Version on the indicated host, possible values 1,2,3 and defaults to 2
=back
=head3 SNMP v3
=over
=item B<-U|--username>
STRING - username 
=item B<-A|--authpassword>
STRING - authentication password
=item B<-a|--authprotocol>
STRING - authentication algorithm, defaults to sha
=item B<-X|--privpassword>
STRING - private password
=item B<-x|--privprotocol>
STRING - private algorithm, defaults to aes
=back
=head3 SNMP v1/v2c
=over
=item B<-C|--community>
STRING - Community-String for SNMP, defaults to public only used with SNMP version 1 and 2
=back
=head3 Other
=over
=item B<-T|--type>
STRING - CPU, MEM, Ses, VPN, net, Cluster, wtp, hw
=item B<-S|--serial>
STRING - Primary serial number.
=item B<-s|--slave>
BOOL - Get values of slave
=item B<-w|--warning>
INTEGER - Warning threshold, applies to cpu, mem, session.
=item B<-c|--critical>
INTEGER - Critical threshold, applies to cpu, mem, session.
=item B<-R|--reset>
BOOL - Resets ip file (cluster only)
=item B<-M|--mode>
STRING - Output-Mode: 0 => just print, 1 => print and show failed tunnel, 2 => critical
=item B<-V|--vpnmode>
STRING - VPN-Mode: both => IPSec & SSL/OpenVPN, ipsec => IPSec only, ssl => SSL/OpenVPN only
=item B<-p|--path>
STRING - Path to store serial filenames
=back
=head1 DESCRIPTION
This plugin checks Fortinet FortiGate devices via SNMP
=head2 From Web
=over 4
=item 1. Select Network -> Interface -> Local interface
=item 2. Administrative Access: Enable SNMP
=item 3. Select Config -> SNMP
=item 4. Enable SNMP, fill your details
=item 5. SNMP v1/v2c: Create new
=item 6. Configure for your needs, Traps are not required for this plugin!
=back
=head2 From CLI
config system interface
edit "internal"
set allowaccess ping https ssh snmp fgfm
next
end
config system snmp sysinfo
set description "DMZ1 FortiGate 300C"
set location "Room 404"
set conctact-info "BOFH"
set status enable
end
config system snmp community
edit 1
set events cpu-high mem-low fm-if-change
config hosts
edit 1
set interface "internal"
set ip %SNMP Client IP%
next
end
set name "public"
set trap-v1-status disable
set trap-v2c-status disable
next
end
Thats it!
=cut
# EOF
