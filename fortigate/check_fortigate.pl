#!/usr/bin/perl
# nagios: -epn
# This  Plugin checks the cluster state of FortiGate
# Tested on: FortiGate 100D / FortiGate 300C (both 5.0.3) 
#
# Author: Oliver Skibbe (oliskibbe (at) gmail.com)
# Date: 2015-02-26
#
# Changelog:
#  - initial release (cluster, cpu, memory, session support)
#  - added vpn support, based on check_fortigate_vpn.pl: Copyright (c) 2009 Gerrit Doornenbal, g(dot)doornenbal(at)hccnet(dot)nl
# Changelog (2015-02-26) Oliver Skibbe (oliskibbe (at) gmail.com)
#  - some code cleanup
#  - whitespace fixes
#  - added snmp debug
#  - added SNMP V3 support
#
# This program is free software; you can redistribute it and/or 
# modify it under the terms of the GNU General Public License 
# as published by the Free Software Foundation; either version 2 
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
# GNU General Public License for more details.
#
# If you wish to receive a copy of the GNU General Public License, 
# write to the Free Software Foundation, Inc., 
# 59 Temple Place - Suite 330, Boston, MA 02111-130
# Description:

use strict;
use Net::SNMP;
use List::Compare;
use Switch;
use Getopt::Long qw(:config no_ignore_case bundling);
use Pod::Usage;

my $script         = "check_fortigate.pl";
my $script_version = "1.4";

# Parse out the arguments...
my ($ip, $port, $community, $type, $warn, $crit, $slave, $pri_serial, $reset_file, $mode, $vpnmode, 
  $version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot) = parse_args();

# Initialize variables....
my $net_snmp_debug_level = 0x00;     # See http://search.cpan.org/~dtown/Net-SNMP-v6.0.1/lib/Net/SNMP.pm#debug()_-_set_or_get_the_debug_mode_for_the_module
                                     # for more information.
my %status = (                       # Enumeration for the output Nagios states 
    'UNKNOWN'  => '-1',
    'OK'       => '0',
    'WARNING'  => '1',
    'CRITICAL' => '2' 
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
        $priv_prot
      );  # Open an SNMP connection...
} else {
  ($session, $error) = get_snmp_session(
        $ip, 
        $community, 
      );  # Open an SNMP connection...
}

if ( $error != "" ) {
  print "\n$error\n";
  exit(1);
}

## OIDs ##
my $oid_unitdesc = ".1.3.6.1.2.1.1.1.0";                        # Location of Fortinet device description... (String)
my $oid_serial = ".1.3.6.1.2.1.1.5.0";                          # Location of Fortinet serial number (String)
my $oid_cluster_type = ".1.3.6.1.4.1.12356.101.13.1.1.0";       # Location of Fortinet serial number (String)
my $oid_cluster_serials = ".1.3.6.1.4.1.12356.101.13.2.1.1.2";  # Location of Cluster serials (String)
my $oid_cpu = ".1.3.6.1.4.1.12356.101.13.2.1.1.3";              # Location of cluster member CPU (%)
my $oid_net = ".1.3.6.1.4.1.12356.101.13.2.1.1.5";              # Location of cluster member Net (?)
my $oid_mem = ".1.3.6.1.4.1.12356.101.13.2.1.1.4";              # Location of cluster member Mem (%)
my $oid_ses = ".1.3.6.1.4.1.12356.101.13.2.1.1.6";              # Location of cluster member Sessions (int)

# VPN OIDs
my $oid_ActiveSSL = ".1.3.6.1.4.1.12356.101.12.2.3.1.2.1";        # Location of Fortinet firewall SSL VPN Tunnel connection count
my $oid_ActiveSSLTunnel = ".1.3.6.1.4.1.12356.101.12.2.3.1.6.1";  # Location of Fortinet firewall SSL VPN Tunnel connection count
my $oid_ipsectuntableroot = ".1.3.6.1.4.1.12356.101.12.2.2.1";    # Table of IPSec VPN tunnels
my $oidf_tunstatus = ".20";                                       # Location of a tunnel's connection status
my $oidf_tunndx = ".1";                                           # Location of a tunnel's index...
my $oidf_tunname = ".3";                                          # Location of a tunnel's name...

## Stuff ##
my $state;                                             # return state
my $path = "/usr/lib/nagios/plugins/FortiSerial";      # path to store serial filenames
my $filename = $path . "/" . $ip;                      # file name to store serials
my $oid;                                               # helper var
my $value;                                             # helper var
my $string;                                            # return string
my $perf;                                              # performance data

# Check SNMP connection and get the description of the device...
my $curr_device  = get_snmp_value($session, $oid_unitdesc);
# Check SNMP connection and get the serial of the device...
my $curr_serial  = get_snmp_value($session, $oid_serial);

switch ( lc($type) ) {
  case "cpu" { ($state, $string) = get_health_value($oid_cpu, "CPU", "%"); }
  case "mem" { ($state, $string) = get_health_value($oid_mem, "Memory", "%"); }
  case "net" { ($state, $string) = get_health_value($oid_net, "Network", ""); }
  case "ses" { ($state, $string) = get_health_value($oid_ses, "Session", ""); }
  case "vpn" { ($state, $string) = get_vpn_state(); }
  else { ($state, $string) = get_cluster_state(); }
}

# Close the connection
close_snmp_session($session);  

# exit with a return code matching the state...
print $string."\n";
exit($status{$state});

########################################################################
##  Subroutines below here....
########################################################################
sub get_snmp_session {
  my $ip        = $_[0];
  my $community = $_[1];
  my ($session, $error) = Net::SNMP->session(
               -hostname  => $ip,
               -community => $community,
               -port      => 161,
               -timeout   => 5,
               -retries   => 3,
               -debug     => $net_snmp_debug_level,
               -version   => 2,
               -translate => [-timeticks => 0x0] #schaltet Umwandlung von Timeticks in Zeitformat aus
           );
  return ($session, $error);
} # end get snmp session

# SNMP V3 with auth+priv
sub get_snmp_session_v3 {
  my $ip             = $_[0];
  my $user_name      = $_[1];
  my $auth_password  = $_[2];
  my $auth_prot      = $_[3];
  my $priv_password  = $_[4];
  my $priv_prot      = $_[5];

  my ($session, $error) = Net::SNMP->session(
               -hostname      => $ip,
               -port          => 161,
               -timeout       => 5,
               -retries       => 3,
               -debug         => $net_snmp_debug_level,
               -version       => 3,
               -username      => $user_name,
               -authpassword  => $auth_password,
               -authprotocol  => $auth_prot,
               -privpassword  => $priv_password,
               -privprotocol  => $priv_prot,
               -translate     => [-timeticks => 0x0] #schaltet Umwandlung von Timeticks in Zeitformat aus
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

  if ( $value >= $crit . $UOM ) {
    $state = "CRITICAL";
    $string = $label . " is critical: " . $value . $UOM; 
  } elsif ( $value >= $warn . $UOM ) {
    $state = "WARNING";
    $string = $label . " is warning: " . $value . $UOM;
  } else {
    $state = "OK";
    $string = $label . " is okay: " . $value. $UOM;
  }

  $perf = "|'" . lc($label) . "'=" . $value . $UOM . ";" . $warn . ";" . $crit;
  $string = $state . ": " . $curr_device . " (Master: " . $curr_serial .") " . $string . $perf;
  return ($state, $string);

} # end health value

sub get_cluster_state {

  my @help_serials;            # helper array

  # get all cluster member serials
  my %snmp_serials = %{get_snmp_table($session, $oid_cluster_serials)};
  my $cluster_type = get_snmp_value($session, $oid_cluster_type);

  my %cluster_types = (1 => "Standalone", 2 => "Active/Active", 3 => "Active/Passive");

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
          chomp;                          # remove "\n" if exists
          push @help_serials, $value;
  }

  # if less then 2 nodes found: critical
  if ( scalar(@help_serials) < 2 ) {
          $string = "HA (" . $cluster_types{$cluster_type} . ") inactive, single node found: " . $curr_serial;
          $state = "CRITICAL";
  # else check if there are differences in ha nodes
  } else {
          # open existing serials
          open ( SERIALHANDLE, "$filename") || die "Error while opening file $filename";
          my @file_serials = <SERIALHANDLE>;                      # push lines into file_serials
          chomp(@file_serials);                           # remove "\n" if exists in array elements
          close (SERIALHANDLE);                           # close file handle
  
    
          # compare serial arrays
          my $comparedList = List::Compare->new('--unsorted', \@help_serials, \@file_serials);
  
          if ( $comparedList->is_LequivalentR ) {
                  $string = "HA (" . $cluster_types{$cluster_type} . ") is active";
                  $state = "OK";
          } else {
                  $string = "Unknown node in active HA (" . $cluster_types{$cluster_type} . ") found";
                  $state = "WARNING";
          }
  } # end scalar count
  
  # if preferred master serial is not master
  if ( $pri_serial && ( $pri_serial ne $curr_serial ) ) {
          $string = $string . ", preferred master " . $pri_serial . " is not master!";
          $state = "CRITICAL";
  }

  # Write an output string...
  $string = $state . ": " . $curr_device . " (Master: " . $curr_serial . ", Slave: " . @help_serials[$#help_serials] . "): " . $string;

  return ($state, $string);
} # end cluster state

sub get_vpn_state {

  my $ipstunsdown = 0;
  my $ipstuncount = 0;
  my $ipstunsopen = 0;
  my $ActiveSSL = 0;
  my $ActiveSSLTunnel = 0;
  my $string_errors = "";
  my %entitystate = (     '1' => 'down',                          # Enumeration for the tunnel up/down states
                          '2' => 'up' );
  $state = "OK";

  # Unless specifically requesting IPSec checks only, do an SSL connection check
  if ($vpnmode ne "ipsec"){
    $ActiveSSL = get_snmp_value($session, $oid_ActiveSSL);
    $ActiveSSLTunnel = get_snmp_value($session, $oid_ActiveSSLTunnel);
  }

  # Unless specifically requesting SSL checks only, do an IPSec tunnel check
  if ($vpnmode ne "ssl"){
    # Get just the top level tunnel data
    my %tunnels = %{get_snmp_table($session, $oid_ipsectuntableroot . $oidf_tunndx)};
    while (($oid, $value) = each (%tunnels)) {
      #Bump the total tunnel count
      $ipstuncount++;
      
      #If the tunnel is up, bump the connected tunnel count
      if ( $entitystate{get_snmp_value($session, $oid_ipsectuntableroot . $oidf_tunstatus . "." . $ipstuncount)} eq "up" )
      {
        $ipstunsopen++;
      } else {
        #Tunnel is down.  Add it to the failed counter
        $ipstunsdown++;
        # If we're counting failures and/or monitoring, put together an output error string of the tunnel name and its status
        if ($mode >= 1){
          $string_errors .= ", ";
          $string_errors .= get_snmp_value($session, $oid_ipsectuntableroot . $oidf_tunname . "." . $ipstuncount)." ".$entitystate{get_snmp_value($session, $oid_ipsectuntableroot . $oidf_tunstatus . "." . $ipstuncount)};
        }
      }
    }
  }

  #Set Unitstate
  my $unitstate="OK";
  if (($mode >= 2 ) && ($vpnmode ne "ssl")) {
    if ($ipstunsdown == 1) { $unitstate="WARNING"; }
    if ($ipstunsdown >= 2) { $unitstate="CRITICAL";  }
  }

  # Write an output string...
  $string = $unitstate . ": " .  $curr_device . " (Master: " . $curr_serial .")";

  if ($vpnmode ne "ipsec") {
      #Add the SSL tunnel count
      $string = $string . ": Active SSL-VPN Connections/Tunnels: " . $ActiveSSL."/".$ActiveSSLTunnel."";
  }
  if ($vpnmode ne "ssl") {
      #Add the IPSec tunnel count and any errors....
      $string = $string . ": IPSEC Tunnels: Configured/Active: " . $ipstuncount . "/" . $ipstunsopen. " " . $string_errors;
  }

  # Create performance data
  $perf="|'ActiveSSL-VPN'=".$ActiveSSL." 'ActiveIPSEC'=".$ipstunsopen;

  $string = $string.$perf;

  # Check to see if the output string contains either "unkw", "WARNING" or "down", and set an output state accordingly...
  if($string =~/uknw/){
      $state = "UNKNOWN";
  }
  if($string =~/WARNING/){
      $state = "WARNING";
  }
  if($string =~/down/){
      $state = "CRITICAL";
  }

  return ($state, $string);

} # end vpn state


sub close_snmp_session{
  my $session = $_[0];
  $session->close();
} # end close snmp session

sub get_snmp_value{
  my $session = $_[0];
  my $oid     = $_[1];
  my (%result) = %{get_snmp_request($session, $oid) or die ("SNMP service is not available on ".$ip) }; 
  return $result{$oid};
} # end get snmp value

sub get_snmp_request{
  my $session = $_[0];
  my $oid     = $_[1];
  return $session->get_request($oid) || die ("SNMP service not responding");
} # end get snmp request

sub get_snmp_table{
  my $session = $_[0];
  my $oid     = $_[1];
  return $session->get_table(  
      -baseoid =>$oid
      ); 
} # end get snmp table


sub parse_args
{
  my $ip        = "";           # snmp host
  my $port      = 161;          # snmp port
  my $version   = "2";          # snmp version
  my $community = "public";     # only for v1/v2c
  
  my $user_name     = "public"; # v3
  my $auth_password = "";       # v3
  my $auth_prot     = "sha";    # v3 auth algo
  my $priv_password = "";       # v3
  my $priv_prot     = "aes";    # v3 priv algo

  my $pri_serial = "";          # primary fortinet serial no
  my $reset_file = "";
  my $type       = "status";
  my $warn       = 80;
  my $crit       = 90;
  my $slave      = 0;
  my $vpnmode    = "both";
  my $mode       = 2;
  my $help       = 0;

  pod2usage(-message => "UNKNOWN: No Arguments given", -exitval => 3, -verbose => 0) if ( !@ARGV );

  GetOptions(
    'host|H=s'         => \$ip,
    'port|P=s'         => \$port,
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
    'warning|w:i'      => \$warn,
    'critical|c:i'     => \$crit,
    'slave|s:1'        => \$slave,
    'reset|R:1'        => \$reset_file,
    'help|?!'          => \$help,
  ) or pod2usage(-exitval => 3, -verbose => 0);

  pod2usage(-exitval => 3, -verbose => 2) if $help;

    return (
    $ip, $port, $community, $type, $warn, $crit, $slave, $pri_serial, $reset_file, $mode, $vpnmode,
    $version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot
    ); 
}    

__END__

=head1 NAME

Check Fortinet FortiGate Appliances

=head1 SYNOPSIS

=item S<check_fortigate.pl -H -C -T [-w|-c|-S|-s|-R|-M|-V|-?]>

Options:

  -H --host STRING or IPADDRESS  Check interface on the indicated host
  -P --port INTEGER Port of indicated host, defaults to 161
  -v --version STRING SNMP Version, defaults to SNMP v2, v1-v3 supported
  -T --type STRING CPU, MEM, Ses, VPN, Cluster
  -S --serial STRING Primary serial number
  -s --slave get values of slave
  -w --warning INTEGER Warning threshold, applies to cpu, mem, session. 
  -c --critical INTEGER Critical threshold,  applies to cpu, mem, session. 
  -R --reset Resets ip file (cluster only)
  -M --mode STRING Output-Mode: 0 => just print, 1 => print and show failed tunnel, 2 => critical 
  -V --vpnmode STRING VPN-Mode: both => IPSec & SSL/OpenVPN, ipsec => IPSec only, ssl => SSL/OpenVPN only
  SNMP v1/v2c only
  -C --community STRING Community-String for SNMP, only at SNMP v1/v2c, defaults to public
  SNMP v3 only
  -A --authpassword STRING auth password
  -a --authprotocol STRING auth algorithm, defaults to sha
  -X --privpassword STRING private password
  -x --privprotocol STRING private algorithm, defaults to aes

  -? --help Returns full help text

  
=head1 OPTIONS

=over 8
   
=item B<-H--host>
 
STRING or IPADDRESS - Check interface on the indicated host.

=item B<-C|--community>

STRING - Community-String for SNMP
   
=item B<-T|--type>

STRING - CPU, MEM, Ses, VPN, net, Cluster

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

=back

=head1 DESCRIPTION
  
This plugin checks Fortinet FortiGate devices via SNMP 

=head2 From Web: 

=item 1. Select Network -> Interface -> Local interface

=item 2. Administrative Access: Enable SNMP

=item 3. Select Config -> SNMP

=item 4. Enable SNMP, fill your details

=item 5. SNMP v1/v2c: Create new

=item 6. Configure for your needs, Traps are not required for this plugin!

=head2 From CLI:

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

