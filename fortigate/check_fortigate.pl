#!/usr/bin/perl -w
# nagios: -epn
# icinga: -epn
# This Plugin checks the cluster state of FortiGate
#
# Tested on: Fortigate 80C (5.0.7b, 5.2.x)
# Tested on: FortiGate 100D / FortiGate 300C (5.0.3)
# Tested on: FortiGate 200B (5.0.6), Fortigate 800C (5.2.2)
# Tested on: FortiAnalyzer (5.2.4)
# Tested on: FortiAnalyzer (6.4.7)
# Tested on: FortiManager (6.4.4)
# Tested on: FortiManager (6.4.7)
# Tested on: FortiGate 100A (2.8)
# Tested on: FortiGate 800D (6.2.3)
# Tested on: FortiGate 900D (6.4.5)
# Tested on: FortiGate 60F (6.4.5, 6.4.7, 6.4.8, 6.4.9)
# Tested on: FortiGate 200F (6.4.5, 6.4.7, 6.4.8, 6.4.9)
# Tested on: FortiGate 300D (6.4.5, 6.4.7, 6.4.8, 6.4.9)
# Tested on: FortiGate 60E (6.4.5)
# Tested on: FortiGate 200E (6.4.5)
#
# Author: Sebastian Gruber (git (at) 94g.de)
# Date: 2022-09-29
#
# Changelog:
# Release 1.0 (2013)
# - initial release (cluster, cpu, memory, session support)
# - added vpn support, based on check_fortigate_vpn.pl:
#   Copyright (c) 2009 Gerrit Doornenbal, g(dot)doornenbal(at)hccnet(dot)nl
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
# Release 1.5.2 (2016-02-25) Oliver Skibbe (oliskibbe (at) gmail.com)
# - fixed pod2usage
# Release 1.6.0 (2016-02-25) Oliver Skibbe (oliskibbe (at) gmail.com)
# - added checks for FortiAnalyer (fazcpu, fazmem, fazdisk)
# Release 1.6.1 (2016-05-03) Oliver Skibbe (oliskibbe (at) gmail.com)
# - added retrieval of firmware version to disable sync check on older firmware
#   versions
# - fixed cluster check for standalone machines
# Release 1.7.0 (2016-06-02) Oliver Skibbe (oliskibbe (at) gmail.com) / Alexandre Rigaud (arigaud.prosodie.cap (at) free.fr)
# - added checks for FortiMail (cpu, mem, log disk,mail disk, load, ses)
# - autodetect device with s/n (http://kb.fortinet.com/kb/viewContent.do?externalId=FD31964)
# - added check for firmware version to disabled sync status (fw<v5 dont works)
# - fixed FQDN device name (#15@Napsty)
# - fixed nosuchobject value
# - fixed snmp version, now version 1 is also supported
# - fixed hardware check, return unk if no sensors available
# - added firmware check with -w/-c support
# Release 1.7.2 (2016-11-11) Oliver Skibbe (oliskibbe (at) gmail.com)
# - replaced switch/case by given/when to improve performance
# Release 1.7.3 (2016-11-14) Oliver Skibbe (oliskibbe (at) gmail.com)
# - fixed FortiAnalyzer detection (serial beginning with FL or FAZ)
# Release 1.7.4 (2017-01-11) Oliver Skibbe (oliskibbe (at) gmail.com)
# - fixed warnings on higher perl versions
# - fixed warnings regarding uninitialized values
# Release 1.8.0 (2017-01-12) Oliver Skibbe (oliskibbe (at) gmail.com)
# - Added cpu,mem,log disk, load FortiADC checks
# Release 1.8.1 (2017-06-28) Alexandre Rigaud (alexandre (at) rigaudcolonna.fr)
# - Added checks used by devices on output when selected type is missing
# - Added no check cluster option
# Release 1.8.3 (2017-11-22) Davide Foschi (argaar (at) gmail.com)
# - Added checks for FortiGate 100A (identified as legacy device, running O.S. version 2.8)
# Release 1.8.4 (2018-02-14) Davide Foschi (argaar (at) gmail.com)
# - Added HA/Disk/Uptime checks for Generic FortiGate (tested on Forti100D where common cluster OIDs fails)
# - Added perfdata to WTP
# Release 1.8.5 (2020-03-25) Boris PASCAULT (github (at) ituz.fr)
# - Change regex for IPSec VPN monitoring (tested on Forti800D running FortiOS 6.2.3)
# Release 1.8.6 (2021-04-06) Dariusz Zielinski-Kolasinski
# - Add SD-WAN Health Check monitoring (tested on Forti900D running FortiOS 6.4.5, Forti60F 6.4.5)
# Release 1.8.7 (2021-06-07) Sebastian Gruber  (git (at) 94g.de)
# - added FortiManager Health Checks (cpu, mem, disk)
# - added FortiManager Health Checks for connected devices health (up/down) and config-sync State (fmgdevice)
# - added Fortigate Uptime warn (behaviour if warn is set)
# - added Fortigate License expiration Check monitoring for FortiGate with critical & warning (license) and option mode for ignoring expired license
# - added Fortigate License Version Check for scheduled Updates on FortiGate (license-version)
# - added Link-Monitor Health Check (alive,dead), tested on Forti900D running FortiOS 6.4.5, Forti60F 6.4.5
# - added FortiGate conserve mode for proxy and kernel (conserve-proxy , conserve-kernel)
# Release 1.8.8 (2021-09-09) RenÃ© Riech (rene.riech (at) t-online.de)
# - Added checks for Fortigate FG201 (tested on FortiOS v6.4.5)
# Release 1.8.9 (2021-06-18) Sebastian Gruber  (git (at) 94g.de)
# - fixed Fortigate License Check
# Release 1.8.10 (2021-09-17) Sebastian Gruber  (git (at) 94g.de)
# - fixed checks for Fortigate system info introduced: cpu-sys , mem-sys
# - added Sessions check for IPv4 / IPv6 ses-ipv4, ses-ipv6
# - reorder OIDs
# Release 1.8.11 (2022-03-25) Muhammed Suhile
# - adedd sd-wan member health check for member 1(pktloss) and member 2(pktloss2)
# - added FortiGate managed forti-switchs status check (offline, online)
# Release 1.8.12 (2022-09-29) Dariusz Zielinski-Kolasinski
# - allow "any" value for critical/waring when in "wtp" mode (tested on Forti900D)
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
use feature ":5.10";
no if ($] >= 5.018), 'warnings' => 'experimental::smartmatch';

use Net::SNMP;
use List::Compare;
use Getopt::Long qw(:config no_ignore_case bundling);
use Pod::Usage;
use Socket;
use POSIX;
use Date::Parse;

my $script = "check_fortigate.pl";
my $script_version = "1.8.10";

# for more information.
my %status = (     # Enumeration for the output Nagios states
  'OK'       => '0',
  'WARNING'  => '1',
  'CRITICAL' => '2',
  'UNKNOWN'  => '3'
);

# Parse out the arguments...
my ($ip, $port, $community, $type, $warn, $crit, $expected, $slave, $pri_serial, $reset_file, $mode, $vpnmode,
    $blacklist, $whitelist, $nosync, $snmp_version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot, $path) = parse_args();

# Initialize variables....
my $net_snmp_debug_level = 0x00; # See http://search.cpan.org/~dtown/Net-SNMP-v6.0.1/lib/Net/SNMP.pm#debug()_-_set_or_get_the_debug_mode_for_the_module

my $session = "";
my $error = "";

## SNMP ##
if ( $snmp_version == 3 ) {
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
                            $snmp_version
                       ); # Open SNMP connection...
}

if ( $error ne "" ) {
  print "\n$error\n";
  exit(1);
}

## OIDs ##
my $oid_unitdesc         = ".1.3.6.1.2.1.1.5.0";                   # Location of Fortinet device description... (String)
my $oid_serial           = ".1.3.6.1.4.1.12356.100.1.1.1.0";       # Location of Fortinet serial number (String)
my $oid_firmware         = ".1.3.6.1.4.1.12356.101.4.1.1.0";       # Location of Fortinet firmware

# fg ha info / Cluster member
my $oid_ha               = ".1.3.6.1.4.1.12356.101.13.1.1.0";      # Location of HA Mode (int - standalone(1),activeActive(2),activePassive(3) )
my $oid_cpu              = ".1.3.6.1.4.1.12356.101.13.2.1.1.3";    # Location of cluster member CPU (%)
my $oid_mem              = ".1.3.6.1.4.1.12356.101.13.2.1.1.4";    # Location of cluster member Mem (%) (fgHaStatsMemUsage) counts the 'freeable cache' as 'used'
my $oid_net              = ".1.3.6.1.4.1.12356.101.13.2.1.1.5";    # Location of cluster member Net (kbps)
my $oid_ses_ha           = ".1.3.6.1.4.1.12356.101.13.2.1.1.6";    # Location of cluster member Sessions (int) (Current session count of specified cluster member)
my $oid_ha_sync_prefix   = ".1.3.6.1.4.1.12356.101.13.2.1.1.15";   # Location of HA Sync Checksum prefix (string - if match, nodes are synced )

# fg system-info
my $oid_cpu_sys          = ".1.3.6.1.4.1.12356.101.4.1.3.0";       # Location of Current CPU usage (percentage)
my $oid_mem_sysmem       = ".1.3.6.1.4.1.12356.101.4.1.4.0";       # Location Current memory utilization (%) (fgSysMemUsage)
my $oid_disk_usage       = ".1.3.6.1.4.1.12356.101.4.1.6.0";       # Location of disk usage value (int - used space kb)
my $oid_disk_cap         = ".1.3.6.1.4.1.12356.101.4.1.7.0";       # Location of disk capacity value (int - total capacity kb)
my $oid_ses_device_ipv4  = ".1.3.6.1.4.1.12356.101.4.1.8.0";       # Location of cluster member Number of active ipv4 sessions on the device (int)
my $oid_ses_device_ipv6  = ".1.3.6.1.4.1.12356.101.4.1.15.0";      # Location of cluster member Number of active ipv6 sessions on the device (int)
my $oid_uptime           = ".1.3.6.1.4.1.12356.101.4.1.20.0";      # Location of Uptime value (int - hundredths of a second)

## Legacy OIDs ##
my $oid_legacy_serial    = ".1.3.6.1.4.1.12356.1.2.0";             # Location of Fortinet serial number (String)
my $oid_legacy_cpu       = ".1.3.6.1.4.1.12356.1.8.0";             # Location of cluster member CPU (%)
my $oid_legacy_net       = ".1.3.6.1.4.1.12356.1.100.6.1.5.1";     # Location of cluster member Net (kbps)
my $oid_legacy_mem       = ".1.3.6.1.4.1.12356.1.9.0";             # Location of cluster member Mem (%)
my $oid_legacy_ses       = ".1.3.6.1.4.1.12356.1.10.0";            # Location of cluster member Sessions (int)

## FortiAnalyzer OIDs ##
my $oid_faz_cpu_used     = ".1.3.6.1.4.1.12356.103.2.1.1.0";       # Location of CPU for FortiAnalyzer (%)
my $oid_faz_mem_used     = ".1.3.6.1.4.1.12356.103.2.1.2.0";       # Location of Memory used for FortiAnalyzer (kb)
my $oid_faz_mem_avail    = ".1.3.6.1.4.1.12356.103.2.1.3.0";       # Location of Memory available for FortiAnalyzer (kb)
my $oid_faz_disk_used    = ".1.3.6.1.4.1.12356.103.2.1.4.0";       # Location of Disk used for FortiAnalyzer (Mb)
my $oid_faz_disk_avail   = ".1.3.6.1.4.1.12356.103.2.1.5.0";       # Location of Disk available for FortiAnalyzer (Mb)

## FortiAuthenticator OIDs ##
my $oid_fac_cpu          = ".1.3.6.1.4.1.12356.113.1.4.0";         # facSysCpuUsage - Instantaneous CPU usage (%)
my $oid_fac_mem          = ".1.3.6.1.4.1.12356.113.1.5.0";         # facSysMemUsage - Instantaneous memory usage (%)
my $oid_fac_ldisk        = ".1.3.6.1.4.1.12356.113.1.6.0";         # facSysLogDiskUsage - Instantaneous log disk usage (%)
my $oid_fac_ha           = ".1.3.6.1.4.1.12356.113.1.201.1.0";     # facHaCurrentStatus - Instantaneous HA status for this node
my $oid_fac_firmware     = ".1.3.6.1.4.1.12356.113.1.3.0";         # facSysVersion - Device firmware version

## FortiMail OIDs ##
my $oid_fe_cpu           = ".1.3.6.1.4.1.12356.105.1.6.0";         # Location of CPU for FortiMail (%)
my $oid_fe_mem           = ".1.3.6.1.4.1.12356.105.1.7.0";         # Location of Memory used for FortiMail (%)
my $oid_fe_ldisk         = ".1.3.6.1.4.1.12356.105.1.8.0";         # Location of Log Disk used for FortiMail (%)
my $oid_fe_mdisk         = ".1.3.6.1.4.1.12356.105.1.9.0";         # Location of Mail Disk used for FortiMail (%)
my $oid_fe_load          = ".1.3.6.1.4.1.12356.105.1.30.0";        # Location of Load used for FortiMail (%)
my $oid_fe_ses           = ".1.3.6.1.4.1.12356.105.1.10.0";        # Location of cluster member Sessions for FortiMail (int)

## FortiManager OIDS ###
my $oid_fmg_cpu_used     = ".1.3.6.1.4.1.12356.103.2.1.1.0";                   # Location of CPU for FortiManager (%)
my $oid_fmg_mem_used     = ".1.3.6.1.4.1.12356.103.2.1.2.0";                   # Location of Memory used for FortiManager (kb)
my $oid_fmg_mem_avail    = ".1.3.6.1.4.1.12356.103.2.1.3.0";                   # Location of Memory available for FortiManager (kb)
my $oid_fmg_disk_used    = ".1.3.6.1.4.1.12356.103.2.1.4.0";                   # Location of Disk used for FortiManager (Mb)
my $oid_fmg_disk_avail   = ".1.3.6.1.4.1.12356.103.2.1.5.0";                   # Location of Disk available for FortiManager (Mb)
my $oid_fmg_device_count   = ".1.3.6.1.4.1.12356.103.6.1.1.0";                 # Count of Devices for FortiManager
my $oid_fmg_device_table   = ".1.3.6.1.4.1.12356.103.6.2";                     # Location of Device Table for FortiManager
my $oid_fmg_device_name_table   = ".1.3.6.1.4.1.12356.103.6.2.1.2";            # Location of Device Table Name for FortiManager
my $oid_fmg_device_adom_table   = ".1.3.6.1.4.1.12356.103.6.2.1.5";            # Location of Device Table admom for FortiManager
my $oid_fmg_device_con_state_table   = ".1.3.6.1.4.1.12356.103.6.2.1.12";      # Location of Device Table connection state for FortiManager
my $oid_fmg_device_config_state_table   = ".1.3.6.1.4.1.12356.103.6.2.1.14";   # Location of Device Table config state for FortiManager

## FortiADC OIDs ##
my $oid_fad_mem           = ".1.3.6.1.4.1.12356.112.1.5.0";        # Location of Memory for FortiADC (%)
my $oid_fad_ldisk         = ".1.3.6.1.4.1.12356.112.1.6.0";        # Location of Log Disk Usage for FortiADC (%)
my $oid_fad_load          = ".1.3.6.1.4.1.12356.112.1.30.0";       # Location of Load used for FortiADC (%)
#  my $oid_fad_load       = ".1.3.6.1.4.1.12356.112.1.40.0";       # "SNMP No Such Object"
my $oid_fad_cpu           = ".1.3.6.1.4.1.12356.112.1.4.0";        # Location of CPU for FortiADC (%)

# Cluster
my $oid_cluster_type       = ".1.3.6.1.4.1.12356.101.13.1.1.0";      # Location of Fortinet cluster type (String)
my $oid_cluster_serials    = ".1.3.6.1.4.1.12356.101.13.2.1.1.2";    # Location of Cluster serials (String)
my $oid_cluster_sync_state = ".1.3.6.1.4.1.12356.101.13.2.1.1.12";   # Location of cluster sync state (int)

# VPN OIDs
# XXX to be checked
my $oid_ActiveSSL         = ".1.3.6.1.4.1.12356.101.12.2.3.1.2";   # Location of Fortinet firewall SSL VPN Tunnel connection count
my $oid_ActiveSSLTunnel   = ".1.3.6.1.4.1.12356.101.12.2.3.1.6";   # Location of Fortinet firewall SSL VPN Tunnel connection count
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

# Switch
my $oid_swstatetableroot  = ".1.3.6.1.4.1.12356.101.24.1.1.1";     # Represents the connection state of a SW to FG: offLine(1), onLine(2), downloadingImage(3), connectedImage(4), other(0)
my $oid_swstatus          = ".7";                                  # Represents the number of switchs status being managed on the FG
my $oid_swip              = ".9" ;                                 # Represents the IP address of a SW
my $oid_swname            = ".3" ;                                 # Represents the seriel number of a SW


# HARDWARE SENSORS
# "A list of device specific hardware sensors and values. Because different devices have different hardware sensor capabilities, this table may or may not contain any values."
my $oid_hwsensor_cnt     = ".1.3.6.1.4.1.12356.101.4.3.1.0";       # Hardware Sensor count
my $oid_hwsensorid       = ".1.3.6.1.4.1.12356.101.4.3.2.1.1";     # Hardware Sensor index
my $oid_hwsensorname     = ".1.3.6.1.4.1.12356.101.4.3.2.1.2";     # Hardware Sensor Name
my $oid_hwsensorvalue    = ".1.3.6.1.4.1.12356.101.4.3.2.1.3";     # Hardware Sensor Value
my $oid_hwsensoralarm    = ".1.3.6.1.4.1.12356.101.4.3.2.1.4";     # Hardware Sensor Alarm (not all sensors have alarms!)

# SD-WAN
my $oid_sdwan_healthcheck_count       = ".1.3.6.1.4.1.12356.101.4.9.1.0";    # SDWAN HealthCheck count
my $oid_sdwan_healthcheck_state_table = ".1.3.6.1.4.1.12356.101.4.9.2.1.4";  # SDWAN HealthCheck state table
my $oid_sdwan_healthcheck_name_table  = ".1.3.6.1.4.1.12356.101.4.9.2.1.2";  # SDWAN HealthCheck name table
my $oid_sdwan_healthcheck_iname_table = ".1.3.6.1.4.1.12356.101.4.9.2.1.14"; # SDWAN HealthCheck interface name table

# fg sdwan health
my $oid_chklink_pktloss1  = ".1.3.6.1.4.1.12356.101.4.9.2.1.9.1";  # Location of Current packet loss sdwan-memeber 1 (percentage)
my $oid_chklink_pktloss2  = ".1.3.6.1.4.1.12356.101.4.9.2.1.9.2";  # Location of Current packet loss sdwan-memeber 2 (percentage)


# conserve Mode
my $oid_lowmem_capacity     = ".1.3.6.1.4.1.12356.101.4.1.10.0";        #Total lowmem  memory (RAM) capacity (KB)
my $oid_mem_enter_ker_thrsh  = ".1.3.6.1.4.1.12356.101.4.6.1.5.0";      #Current memory threshold level to enter kernel conserve mode (KB)
my $oid_mem_leave_ker_thrsh  = ".1.3.6.1.4.1.12356.101.4.6.1.6.0";      #Current memory threshold level to leave kernel conserve mode (KB)
my $oid_mem_enter_proxy_thrsh  = ".1.3.6.1.4.1.12356.101.4.6.1.7.0";    #Current memory threshold level to enter proxy conserve mode (KB)
my $oid_mem_leave_proxy_thrsh  = ".1.3.6.1.4.1.12356.101.4.6.1.8.0";    #Current memory threshold level to leave proxy conserve mode (KB)

# Link-Monitor
my $oid_linkmonitor_healthcheck_count = ".1.3.6.1.4.1.12356.101.4.8.1.0";    # LinkMonitor HealthCheck count
my $oid_linkmonitor_healthcheck_state_table = ".1.3.6.1.4.1.12356.101.4.8.2.1.3";  # LinkMonitor HealthCheck state table
my $oid_linkmonitor_healthcheck_name_table  = ".1.3.6.1.4.1.12356.101.4.8.2.1.2";  # LinkMonitor HealthCheck name table

# License FortiGate
# license contract
my $oid_license_contract_count                = ".1.3.6.1.4.1.12356.101.4.6.3.1.1.0";    # License Contract Count
my $oid_license_contract_description_table    = ".1.3.6.1.4.1.12356.101.4.6.3.1.2.1.1";  # License Contract description
my $oid_license_contract_expiry_table         = "1.3.6.1.4.1.12356.101.4.6.3.1.2.1.2";   # License Contract expiry time

# license Version
my $oid_license_version_count                = ".1.3.6.1.4.1.12356.101.4.6.3.2.1.0";    # License Version Count
my $oid_license_version_description_table    = ".1.3.6.1.4.1.12356.101.4.6.3.2.2.1.1";  # License Version description
my $oid_license_version_upd_time_table       = ".1.3.6.1.4.1.12356.101.4.6.3.2.2.1.4";  # License Version update time
my $oid_license_version_upd_method_table     = ".1.3.6.1.4.1.12356.101.4.6.3.2.2.1.5";  # License Version update method
my $oid_license_version_try_time_table       = ".1.3.6.1.4.1.12356.101.4.6.3.2.2.1.6";  # License Version try time
my $oid_license_version_try_result_table     = ".1.3.6.1.4.1.12356.101.4.6.3.2.2.1.7";  # License Version try result

## Stuff ##
my $return_state;                                     # return state
my $return_string;                                    # return string
my $filename = $path . "/" . $ip;                     # file name to store serials
my $oid;                                              # helper var
my $value;                                            # helper var
my $perf;                                             # performance data

# Check SNMP connection and get the description of the device...
my $curr_device = get_snmp_value($session, $oid_unitdesc);

my $curr_serial = '';

if ( $curr_device=~/100A/) {
    $curr_serial = get_snmp_value($session, $oid_legacy_serial);
} else {
    # Check SNMP connection and get the serial of the device...
    $curr_serial = get_snmp_value($session, $oid_serial);
}

# Use s/n to determinate device
given ( $curr_serial ) {
   when ( /^(FL|FAZ)/ ) { # FL|FAZ = FORTIANALYZER
      given ( lc($type) ) {
         when ("cpu") { ($return_state, $return_string) = get_health_value($oid_faz_cpu_used, "CPU", "%"); }
         when ("mem") { ($return_state, $return_string) = get_faz_health_value($oid_faz_mem_used, $oid_faz_mem_avail, "Memory", "%"); }
         when ("disk") { ($return_state, $return_string) = get_faz_health_value($oid_faz_disk_used, $oid_faz_disk_avail, "Disk", "%"); }
         default { ($return_state, $return_string) = ('UNKNOWN',"UNKNOWN: This device supports only selected type -T cpu|mem|disk $curr_device is a FORTIANALYZER (S/N: $curr_serial)"); }
      }
   } when ( /^FAC/ ) { # FAC = FortiAuthenticator
      given ( lc($type) ) {
         when ("cpu") { ($return_state, $return_string) = get_health_value($oid_fac_cpu, "CPU", "%"); }
         when ("mem") { ($return_state, $return_string) = get_health_value($oid_fac_mem, "Memory", "%"); }
         when ("ldisk") { ($return_state, $return_string) = get_health_value($oid_fac_ldisk, "Log Disk", "%"); }
         when ("ha") {
            $oid_ha = $oid_fac_ha; # hack to get "ha" check going
            ($return_state, $return_string) = get_ha_mode();
         }
         when ("firmware") {
            $oid_firmware = $oid_fac_firmware; # hack to get "firmware" check going
            ($return_state, $return_string) = get_firmware_state();
         }
         default { ($return_state, $return_string) = ('UNKNOWN',"UNKNOWN: This device supports only selected type -T cpu|firmware|ha|mem|ldisk, $curr_device is a FORTIAUTHENTICATOR (S/N: $curr_serial)"); }
      }
   } when ( /^FMG/ ) { # FMG = FortiManager
      given ( lc($type) ) {
         when ("cpu") { ($return_state, $return_string) = get_health_value($oid_fmg_cpu_used, "CPU", "%"); }
         when ("mem") { ($return_state, $return_string) = get_fmg_health_value($oid_fmg_mem_used, $oid_fmg_mem_avail, "Memory", "%"); }
         when ("disk") { ($return_state, $return_string) = get_fmg_health_value($oid_fmg_disk_used, $oid_fmg_disk_avail, "Disk", "%"); }
         when ("fmgdevice") { ($return_state, $return_string) = get_fmg_device_state(); }
         default { ($return_state, $return_string) = ('UNKNOWN',"UNKNOWN: This device supports only selected type -T cpu|mem|disk|fmgdevice $curr_device is a FORTIMANAGER (S/N: $curr_serial)"); }
      }
   } when ( /^FE/ ) { # FE = FORTIMAIL
      given ( lc($type) ) {
         when ("cpu") { ($return_state, $return_string) = get_health_value($oid_fe_cpu, "CPU", "%"); }
         when ("mem") { ($return_state, $return_string) = get_health_value($oid_fe_mem, "Memory", "%"); }
         when ("disk") { ($return_state, $return_string) = get_health_value($oid_fe_mdisk, "Disk", "%"); }
         when ("ldisk") { ($return_state, $return_string) = get_health_value($oid_fe_ldisk, "Log Disk", "%"); }
         when ("load") { ($return_state, $return_string) = get_health_value($oid_fe_load, "Load", "%"); }
         when ("ses") { ($return_state, $return_string) = get_health_value($oid_fe_ses, "Session", ""); }
         default { ($return_state, $return_string) = ('UNKNOWN',"UNKNOWN: This device supports only selected type -T cpu|mem|disk|ldisk|load|ses, $curr_device is a FORTIMAIL (S/N: $curr_serial)"); }
      }
   } when ( /^FAD/ ) { # FAD = FortiADC
      given ( lc($type) ) {
         when ("cpu")   { ($return_state, $return_string) = get_health_value($oid_fad_cpu, "CPU", "%"); }
         when ("mem")   { ($return_state, $return_string) = get_health_value($oid_fad_mem, "Memory", "%"); }
         when ("ldisk") { ($return_state, $return_string) = get_health_value($oid_fad_ldisk, "Log Disk", "%"); }
         when ("load")  { ($return_state, $return_string) = get_health_value($oid_fad_load, "Load", "%"); }
         default { ($return_state, $return_string) = ('UNKNOWN',"UNKNOWN: This device supports only selected type -T cpu|mem|ldisk|load, $curr_device is a FortiADC (S/N: $curr_serial)"); }
      }
   } when ( /^FG100A/ ) { # 100A = Legacy Device
      given ( lc($type) ) {
         when ("cpu") { ($return_state, $return_string) = get_health_value($oid_legacy_cpu, "CPU", "%"); }
         when ("mem") { ($return_state, $return_string) = get_health_value($oid_legacy_mem, "Memory", "%"); }
         when ("ses") { ($return_state, $return_string) = get_health_value($oid_legacy_ses, "Session", ""); }
         when ("net") { ($return_state, $return_string) = get_health_value($oid_legacy_net, "Network", ""); }
		 when ("pktloss") { ($return_state, $return_string) = get_pktloss_value(); }
		 when ("pktloss2") { ($return_state, $return_string) = get_pktloss_value2(); }
         default { ($return_state, $return_string) = ('UNKNOWN',"UNKNOWN: This device supports only selected type -T cpu|mem|ses|net, $curr_device is a Legacy Fortigate (S/N: $curr_serial)"); }
      }
   } default { # OTHERS (FG = FORTIGATE...)
      given ( lc($type) ) {
         when ("cpu") { ($return_state, $return_string) = get_health_value($oid_cpu, "CPU", "%"); }
         when ("cpu-sys") { ($return_state, $return_string) = get_health_value($oid_cpu_sys, "CPU", "%"); }
         when ("mem") { ($return_state, $return_string) = get_health_value($oid_mem, "Memory", "%"); }
         when ("mem-sys") { ($return_state, $return_string) = get_health_value($oid_mem_sysmem, "Memory", "%"); }
         when ("net") { ($return_state, $return_string) = get_health_value($oid_net, "Network", "kb"); }
         when ("ses") { ($return_state, $return_string) = get_health_value($oid_ses_ha, "Session", ""); }
         when ("ses-ipv4") { ($return_state, $return_string) = get_health_value($oid_ses_device_ipv4, "Session IPv4", ""); }
         when ("ses-ipv6") { ($return_state, $return_string) = get_health_value($oid_ses_device_ipv6, "Session IPv6", ""); }
         when ("disk") { ($return_state, $return_string) = get_disk_usage(); }
         when ("ha") { ($return_state, $return_string) = get_ha_mode(); }
         when ("hasync") { ($return_state, $return_string) = get_ha_sync(); }
         when ("uptime") { ($return_state, $return_string) = get_uptime(); }
         when ("vpn") { ($return_state, $return_string) = get_vpn_state(); }
         when ("wtp") { ($return_state, $return_string) = get_wtp_state("%"); }
         when ("switch") { ($return_state, $return_string) = get_sw_state(); }
         when ("hw" ) { ($return_state, $return_string) = get_hw_state("%"); }
         when ("firmware") { ($return_state, $return_string) = get_firmware_state(); }
         when ("sdwan-hc") { ($return_state, $return_string) = get_sdwan_hc(); }
		 when ("pktloss") { ($return_state, $return_string) = get_pktloss_value(); }
		 when ("pktloss2") { ($return_state, $return_string) = get_pktloss_value2(); }
         when ("conserve-proxy") { ($return_state, $return_string) = get_conserve_mode($oid_mem_enter_proxy_thrsh,$oid_mem_leave_proxy_thrsh,"proxy"); }
         when ("conserve-kernel") { ($return_state, $return_string) = get_conserve_mode($oid_mem_enter_ker_thrsh,$oid_mem_leave_ker_thrsh,"kernel"); }
         when ("linkmonitor-hc") { ($return_state, $return_string) = get_linkmonitor_hc(); }
         when ("license") { ($return_state, $return_string) = get_license_contract(); }
         when ("license-version") { ($return_state, $return_string) = get_license_version(); }
         default { ($return_state, $return_string) = get_cluster_state(); }
      }
   }
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
  my $version = $_[3];
  my ($session, $error) = Net::SNMP->session(
                              -hostname  => $ip,
                              -community => $community,
                              -port      => $port,
                              -timeout   => 10,
                              -retries   => 2,
                              -debug     => $net_snmp_debug_level,
                              -version   => $version,
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
                              -retries      => 2,
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

sub get_disk_usage {
  my $value_usage = get_snmp_value($session, $oid_disk_usage);
  my $value_cap = get_snmp_value($session, $oid_disk_cap);
  my $value = (int (($value_usage/$value_cap)*100) );

  if ( $value >= $crit ) {
    $return_state = "CRITICAL";
    $return_string = "Disk usage is critical: " . $value . "%";
  } elsif ( $value >= $warn ) {
    $return_state = "WARNING";
    $return_string = "Disk usage is warning: " . $value . "%";
  } else {
    $return_state = "OK";
    $return_string = "Disk usage is okay: " . $value. "%";
  }

  $return_string = $return_state . ": " . $return_string . "|'disk'=" . $value . "%;" . $warn . ";" . $crit;
  return ($return_state, $return_string);
}

sub get_pktloss_value {
  my $value = get_snmp_value($session, $oid_chklink_pktloss1);
  if ( $value >= $crit ) {
    $return_state = "CRITICAL";
    $return_string = "wan1 Packet loss is critical: " . $value . "%";
  } elsif ( $value >= $warn ) {
    $return_state = "WARNING";
    $return_string = "wan1 Packet loss is warning: " . $value . "%";
  } else {
    $return_state = "OK";
    $return_string = "No packet loss for wan1: " . $value. "%";
  }

  $return_string = $return_state . ": " . $return_string . "|'pktloss'=" . $value . "%;" . $warn . ";" . $crit;
  return ($return_state, $return_string);
}
sub get_pktloss_value2 {
  my $value = get_snmp_value($session, $oid_chklink_pktloss2);
  if ( $value >= $crit ) {
    $return_state = "CRITICAL";
    $return_string = "wan1 Packet loss is critical: " . $value . "%";
  } elsif ( $value >= $warn ) {
    $return_state = "WARNING";
    $return_string = "wan1 Packet loss is warning: " . $value . "%";
  } else {
    $return_state = "OK";
    $return_string = "No packet loss for wan2: " . $value. "%";
  }

  $return_string = $return_state . ": " . $return_string . "|'pktloss'=" . $value . "%;" . $warn . ";" . $crit;
  return ($return_state, $return_string);
}

sub get_ha_mode {
  my $ha_modes = get_snmp_value($session, $oid_ha);

  my %ha_modes = (
                        1 => "Standalone",
                        2 => "Active/Active",
                        3 => "Active/Passive"
  );

  if ( (int $expected) != $ha_modes) {
    $return_state = "CRITICAL";
    $return_string = "HA mode is NOT working as expected ( mode: " . $ha_modes{$ha_modes} . ", expected: " . $ha_modes{(int $expected)} . ")";
  } else {
    $return_state = "OK";
    $return_string = "HA mode is working as expected: " . $ha_modes{$ha_modes};
  }

  $return_string = $return_state . ": " . $return_string;
  return ($return_state, $return_string);
}

sub get_ha_sync {
  my $value1 = get_snmp_value($session, $oid_ha_sync_prefix . ".1");
  my $value2 = get_snmp_value($session, $oid_ha_sync_prefix . ".2");

  if ( $value1 ne $value2 ) {
    $return_state = "CRITICAL";
    $return_string = "nodes are NOT synced - Node1 checksum: " . $value1 . " Node2 checksum: " . $value2;
  } else {
    $return_state = "OK";
    $return_string = "nodes are synced, checksum: " . $value1;
  }

  $return_string = $return_state . ": " . $return_string;
  return ($return_state, $return_string);
}

sub get_uptime {
  my $valuemin;
  my $value = (get_snmp_value($session, $oid_uptime)/100);
  my ($days_val, $rem_d_value) = (int($value / 86400), $value / 86400);
  my $hours_val = int(($rem_d_value-$days_val) * 24);
  my $minutes_val = int (((($rem_d_value-$days_val) * 24)-int(($rem_d_value-$days_val) * 24)) * 60);

 if ( $warn != 80 && $value <= $warn ) {
    $valuemin = $value / 60;
    $return_state = "WARNING";
    $return_string = "uptime is lower than " . $valuemin . " minutes. ";
  }else {
    $return_state = "OK";
    $return_string = $days_val . " day(s) " . $hours_val . " hour(s) " . $minutes_val . " minute(s)";
  }

$return_string = $return_state . ": " . $return_string;
  return ($return_state, $return_string);
}

sub get_firmware_state {
  my $value = get_snmp_value($session, $oid_firmware);

  if ( $warn != 80 && $value !~ /$warn/ ) {
    $return_state = "WARNING";
    $return_string = "current firmware version ( " . $value . " ) differs from requested version: " . $warn;
  } elsif ( $crit != 90 && $value !~ /$crit/ ) {
    $return_state = "CRITICAL";
    $return_string = "current firmware version ( " . $value . " ) differs from requested version: " . $crit;
  } else {
    $return_state = "OK";
    $return_string = "current firmware version: " . $value;
  }

  $return_string = $return_state . ": " . $return_string;
  return ($return_state, $return_string);
}

sub get_health_value {
  my $label = $_[1];
  my $UOM   = $_[2];

  if ( $slave == 1 ) {
      $oid = $_[0] . ".2";
      $label = "slave_" . $label;
  } elsif ( $curr_serial =~ /^FG100A/ ) {
      $oid = $_[0];
  } elsif ( $curr_serial =~ /^FG201/ ) {
      $oid = $_[0];
  } elsif ( $curr_serial =~ /^FG/ ) {
      $oid = $_[0] . ".1";
  } else {
      $oid = $_[0];
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
  $return_string = $return_state . ": " . $curr_device . " (Current device: " . $curr_serial .") " . $return_string . $perf;

  return ($return_state, $return_string);
} # end health value

sub get_faz_health_value {
  my $used_oid = $_[0];
  my $avail_oid = $_[1];
  my $label = $_[2];
  my $UOM   = $_[3];

  my $used_value = get_snmp_value($session, $used_oid);
  my $avail_value = get_snmp_value($session, $avail_oid);

  # strip any leading or trailing non zeros
  $used_value =~ s/\D*(\d+)\D*/$1/g;
  $avail_value =~ s/\D*(\d+)\D*/$1/g;

  $value = floor($used_value/$avail_value*100);

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
  $return_string = $return_state . ": " . $curr_device . " (Current device: " . $curr_serial .") " . $return_string . $perf;

  return ($return_state, $return_string);
} # end faz health value
sub get_fmg_health_value {
  my $used_oid = $_[0];
  my $avail_oid = $_[1];
  my $label = $_[2];
  my $UOM   = $_[3];

  my $used_value = get_snmp_value($session, $used_oid);
  my $avail_value = get_snmp_value($session, $avail_oid);

  # strip any leading or trailing non zeros
  $used_value =~ s/\D*(\d+)\D*/$1/g;
  $avail_value =~ s/\D*(\d+)\D*/$1/g;

  $value = floor($used_value/$avail_value*100);

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
  $return_string = $return_state . ": " . $curr_device . " (Current device: " . $curr_serial .") " . $return_string . $perf;

  return ($return_state, $return_string);
} # end fmg health value

sub get_cluster_state {
  my @help_serials; # helper array

  # before launch snmp requests, test write access on path directory
  if ( ! -w $path ) {
        $return_state = "CRITICAL";
        $return_string = "$return_state: Error writing on $path directory, permission denied";
        return ($return_state, $return_string);
  }

  # get all cluster member serials
  my $firmware_version = get_snmp_value($session, $oid_firmware);
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

  if ( $cluster_type != 1 ) {
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
      chomp $value; # remove "\n" if exists
      push @help_serials, $value;
    }

    # if less then 2 nodes found: critical
    if ( scalar(@help_serials) < 2  && $cluster_type != 1 ) {
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

    if ( $return_state eq "OK"  && $firmware_version !~ /.*v4\.0\..*/ && !defined($nosync) ) {
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
    $return_string = $return_state . ": " . $curr_device . "@" . $firmware_version . " (Master: " . $curr_serial . ", Slave: " . $help_serials[$#help_serials] . "): " . $return_string;
    $return_string .= $firmware_version !~ /.*v4\.0\..*/  ? ", " . $sync_string : '';
  } else {
    $return_state = "OK";
    $return_string = $return_state . ": " . $curr_device . "@" . $firmware_version . " HA: " . $cluster_types{$cluster_type};
  } # end if cluster is standalone

  return ($return_state, $return_string);
} # end cluster state

sub get_vpn_state {
  my $ipstunsdown = 0;
  my $ipstuncount = 0;
  my $ipstunsopen = 0;
  my $ActiveSSL = 0;
  my $ActiveSSLTunnel = 0;
  my $return_string_errors = "";

  use constant {
    TUNNEL_DOWN => 1,
    TUNNEL_UP   => 2,
  };
 $return_state = "OK";

  # Unless specifically requesting IPSec checks only, do an SSL connection check
  if ($vpnmode ne "ipsec"){
    my %ActiveSSL_table = %{get_snmp_table($session, $oid_ActiveSSL)};
	  my %ActiveSSLTunnel_table = %{get_snmp_table($session, $oid_ActiveSSLTunnel)};
    foreach my $k (keys(%ActiveSSL_table)) {
      $ActiveSSL += $ActiveSSL_table{$k};
    }
    foreach my $k (keys(%ActiveSSLTunnel_table)) {
      $ActiveSSLTunnel += $ActiveSSLTunnel_table{$k};
    }
  }
  # Unless specifically requesting SSL checks only, do an IPSec tunnel check
  if ($vpnmode ne "ssl") {
  # N/A as of 2015
#    # Get just the top level tunnel data
    my %tunnels_names  = %{get_snmp_table($session, $oid_ipsectuntableroot . $oidf_tunname)};
    my %tunnels_status = %{get_snmp_table($session, $oid_ipsectuntableroot . $oidf_tunstatus)};

    %tunnels_names  = map { (my $temp = $_ ) =~ s/^${oid_ipsectuntableroot}${oidf_tunname}\.//; $temp => $tunnels_names{$_}  } keys %tunnels_names;
    %tunnels_status = map { (my $temp = $_ ) =~ s/^${oid_ipsectuntableroot}${oidf_tunstatus}\.//; $temp => $tunnels_status{$_} } keys %tunnels_status;

    if (defined($whitelist) and length($whitelist))
    {
      delete $tunnels_names{$_} for grep { $tunnels_names{$_} !~ $whitelist } keys %tunnels_names;
    }
    if (defined($blacklist) and length($blacklist))
    {
      delete $tunnels_names{$_} for grep { $tunnels_names{$_} =~ $blacklist } keys %tunnels_names;
    }
    my %tunnels = map {
      $_ => {
        "name"   => $tunnels_names{$_},
        "status" => $tunnels_status{$_}
      }
    } keys %tunnels_names;
    my @tunnels_up   = map { $tunnels{$_}{"name"} } grep { $tunnels{$_}{"status"} eq TUNNEL_UP   } keys %tunnels;
    my @tunnels_down = map { $tunnels{$_}{"name"} } grep { $tunnels{$_}{"status"} eq TUNNEL_DOWN } keys %tunnels;
    $ipstuncount = scalar keys %tunnels;
    $ipstunsopen = scalar @tunnels_up;
    $ipstunsdown = scalar @tunnels_down;

    if ($ipstunsdown > 0 and $mode >= 1) {
      $return_string_errors .= sprintf("DOWN[%s]", join(", ", @tunnels_down));
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

  # Check to see if the output string contains either "unkw", "warning" or "down", and set an output state accordingly...
  if($return_string =~/uknw/i){
    $return_state = "UNKNOWN";
  }
  if($return_string =~/warning/i){
    $return_state = "WARNING";
  }
  if($return_string =~/down/i){
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
    if ($crit eq "any" && $wtpoffline > 0) {
      $return_state = "CRITICAL";
    } elsif ($warn eq "any" && $wtpoffline > 0) {
      $return_state = "WARNING";
    } elsif ( $crit ne "any" && $value >= $crit ) {
      $return_state = "CRITICAL";
    } elsif ( $warn ne "any" &&  $value >= $warn ) {
      $return_state = "WARNING";
    }

    # format - for performance data
    if ( $crit eq "any" ) {
      $crit = "0";
    }
    if ($warn eq "any") {
      $warn = "0";
    }

    $return_string = "$return_state - $wtpoffline offline WiFi access point(s) over $wtpcount found : ".(sprintf("%.2f",$value))." $UOM : ".$downwtp."|'APs'=".$wtpcount.";; 'Down APs'=".$wtpoffline.";; 'APs_Unavailable'=".$value.$UOM.";".$warn.";".$crit;
  } else  {
    $return_string = "No wtp configured.";
  }

  return ($return_state, $return_string);
} # end wtp state

sub get_sw_state {
  my $fswitchsdown = 0;
  my $fswitchscount = 0;
  my $fswitchsup = 0;
  my $return_string_errors = "";

  use constant {
    SWITCH_DOWN => 0,
    SWITCH_UP   => 1,
  };
  $return_state = "OK";

# Get just the authorised switch data
    my %switches_names  = %{get_snmp_table($session, $oid_swstatetableroot . $oid_swname)};
    my %switches_status = %{get_snmp_table($session, $oid_swstatetableroot . $oid_swstatus)};

    %switches_names  = map { (my $tempr = $_ ) =~ s/^${oid_swstatetableroot}${oid_swname}\.//; $tempr => $switches_names{$_}  } keys %switches_names;
    %switches_status = map { (my $tempr = $_ ) =~ s/^${oid_swstatetableroot}${oid_swstatus}\.//; $tempr => $switches_status{$_} } keys %switches_status;

    my %switches = map {
      $_ => {
        "name"   => $switches_names{$_},
        "status" => $switches_status{$_}
      }
    } keys %switches_names;
    my @switches_up   = map { $switches{$_}{"name"} } grep { $switches{$_}{"status"} eq SWITCH_UP   } keys %switches;
    my @switches_down = map { $switches{$_}{"name"} } grep { $switches{$_}{"status"} eq SWITCH_DOWN } keys %switches;
    $fswitchscount = scalar keys %switches;
    $fswitchsup = scalar @switches_up;
    $fswitchsdown = scalar @switches_down;

    if ($fswitchsdown > 0) {
      $return_string_errors .= sprintf("DOWN[%s]", join(", ", @switches_down));
    }

  #Set Unitstate
   if ( $fswitchsdown >= $crit ) {
      $return_state = "CRITICAL";
    } elsif ( $fswitchsdown >= $warn ) {
      $return_state = "WARNING";
    }


  # Write an output string...
  $return_string = $return_state . ": " . $curr_device . " (Master: " . $curr_serial .")" . ", Switches  Online/Configured: " . $fswitchsup . "/" . $fswitchscount . ", Switches  Offline: " . $fswitchsdown . " " . $return_string_errors;

  # Create performance data
  $perf="|'Online Switches'=".$fswitchsup." 'Offline Switches'=".$fswitchsdown;
  $return_string .= $perf;

  # Check to see if the output string contains either "unkw", "warning" or "down", and set an output state accordingly...
  if($return_string =~/uknw/i){
    $return_state = "UNKNOWN";
  }
  if($return_string =~/warning/i){
    $return_state = "WARNING";
  }
  if($return_string =~/critical/i){
    $return_state = "CRITICAL";
  }
  return ($return_state, $return_string);
} # end switch state

sub get_hw_state{
   my $k;
   my $sensor_cnt = get_snmp_value($session, $oid_hwsensor_cnt);
   if ( $sensor_cnt > 0 ) {
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
            given ( $hw_name ) {
              when ( /Fan\s/) {
                $unit = "RPM";
              }
              when ( /^DTS\sCPU[0-9]?|Temp|LM75|^ADT74(90|62)\s.+/) {
                $unit = "C";
              }
              when ( /^VCCP|^P[13]V[138]_.+|^AD[_\+].+|^\+(12|5|3\.3|1\.5|1\.25|
                       1\.1)V|^PS[0-9]\s(VIN|VOUT|12V\sOutput)|^AD[_\+].+|
                       ^INA219\sPS[0-9]\sV(sht|bus)/) {
                $unit = "V";
              }
              default { $unit = "?"; }
            }
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
   } else {
      $return_string = "UNKNOWN: device has no sensors available";
      $return_state = "UNKNOWN";
   }

   return ($return_state, $return_string);
} # end hw state

# Get SD-WAN Health Check list and check its status (Alive/Dead)
sub get_sdwan_hc {
   my $k;
   my $sdwan_hc_cnt = get_snmp_value($session, $oid_sdwan_healthcheck_count);
   if ( $sdwan_hc_cnt > 0 ) {
      my %sdwan_hc_name_table = %{get_snmp_table($session, $oid_sdwan_healthcheck_name_table)};
      my %sdwan_hc_iname_table = %{get_snmp_table($session, $oid_sdwan_healthcheck_iname_table)};
      my %sdwan_hc_state_table = %{get_snmp_table($session, $oid_sdwan_healthcheck_state_table)};

      my @sdwan_hc_failed;

      $return_state = "OK";
      $return_string = "All SDWAN health checks are in appropriate state";

      $k = 1;
      while ($k <= $sdwan_hc_cnt) {
         my $sdwan_hc_name = $sdwan_hc_name_table{$oid_sdwan_healthcheck_name_table.'.'.$k};
         my $sdwan_hc_iname = $sdwan_hc_iname_table{$oid_sdwan_healthcheck_iname_table.'.'.$k};
         my $sdwan_hc_state = $sdwan_hc_state_table{$oid_sdwan_healthcheck_state_table.'.'.$k};
         if ($sdwan_hc_state eq '1') {
            push (@sdwan_hc_failed, ($sdwan_hc_name.'/'.$sdwan_hc_iname));
         }
         $k++;
      }

      if ($#sdwan_hc_failed > 0) {
         $return_string = 'SDWAN HC Failed: '.join(';', @sdwan_hc_failed);
         $return_state = 'CRITICAL';
      }

   } else {
      $return_string = "UNKNOWN: device has no SDWAN health checks available";
      $return_state = "UNKNOWN";
   }

   return ($return_state, $return_string);
} # end sdwan_hc
# Get Link Monitor Health Check list and check its status (Alive/Dead)
sub get_linkmonitor_hc {
   my $k;
   my $linkmonitor_hc_cnt = get_snmp_value($session, $oid_linkmonitor_healthcheck_count);
   if ( $linkmonitor_hc_cnt > 0 ) {
      my %linkmonitor_hc_name_table = %{get_snmp_table($session, $oid_linkmonitor_healthcheck_name_table)};
      my %linkmonitor_hc_state_table = %{get_snmp_table($session, $oid_linkmonitor_healthcheck_state_table)};

      my @linkmonitor_hc_failed;

      $return_state = "OK";
      $return_string = "All Link Monitor health checks are in appropriate state";

      $k = 1;
      while ($k <= $linkmonitor_hc_cnt) {
         my $linkmonitor_hc_name = $linkmonitor_hc_name_table{$oid_linkmonitor_healthcheck_name_table.'.'.$k};
         my $linkmonitor_hc_state = $linkmonitor_hc_state_table{$oid_linkmonitor_healthcheck_state_table.'.'.$k};
         if ($linkmonitor_hc_state eq '1') {
            push (@linkmonitor_hc_failed, ($linkmonitor_hc_name));
         }
         $k++;
      }

      if (@linkmonitor_hc_failed) {
         $return_string = 'Link Monitor HC Failed: '.join(';', @linkmonitor_hc_failed);
         $return_state = 'CRITICAL';
      }
   } else {
      $return_string = "UNKNOWN: device has no Link Monitor healt checks available";
      $return_state = "UNKNOWN";
   }
   return ($return_state, $return_string);
} # end get_linkmonitor_hc
# Get License contract Information and checks if its expiring soon
sub get_license_contract {
   my $k;
   my $lic_contract_cnt = get_snmp_value($session, $oid_license_contract_count );
   if ( $lic_contract_cnt > 0 ) {
      my %license_contract_descpriction_table = %{get_snmp_table($session, $oid_license_contract_description_table)};
      my %license_contract_expiry_table = %{get_snmp_table($session, $oid_license_contract_expiry_table)};
      my @license_expiry_warn_table;
      my @license_expiry_crit_table;
      $return_state = "OK";
      #$return_string = "All licenses are in appropriate state";
      $k = 1;
      my $license_actualdate = time();
      my $license_warning = $warn * 86400;
      my $license_critcal = $crit * 86400;
      my $return_string_errors = "";
      while ($k <= $lic_contract_cnt) {
         my $license_contract_descpriction = $license_contract_descpriction_table{$oid_license_contract_description_table.'.'.$k};
         my $license_contract_expiry = $license_contract_expiry_table{$oid_license_contract_expiry_table.'.'.$k};
         my $license_remaining = str2time($license_contract_expiry) - $license_actualdate;
         my $license_remaining_days = $license_remaining / 86400;
        if($license_remaining >= 0 )
        {
          if (($license_remaining <= $license_warning) && ($license_remaining <= $license_critcal) ) {
                push (@license_expiry_warn_table, ($license_contract_descpriction.'/'.$license_contract_expiry));
              }
          if ($license_remaining <= $license_critcal) {
                push (@license_expiry_crit_table, ($license_contract_descpriction.'/'.$license_contract_expiry));
              }
        }else{
	       if ($mode == 1) {
                push (@license_expiry_crit_table, ($license_contract_descpriction.'/'.$license_contract_expiry));
              }
        }
         $k++;
      }
      if (@license_expiry_warn_table) {
          $return_string_errors .= sprintf(" WARNING[%s]", join(", ", @license_expiry_warn_table));
          $return_state = 'WARNING';
      }
      if (@license_expiry_crit_table){
          $return_string_errors .= sprintf(" CRITICAL[%s]", join(", ", @license_expiry_crit_table));
          $return_state = 'CRITICAL';
      }
      $return_string = $return_state . ": " . $curr_device . "  ";
      $return_string .=  $return_string_errors;
   } else {
      $return_string = "UNKNOWN: device has no license checks available";
      $return_state = "UNKNOWN";
   }
   return ($return_state, $return_string);
} # end license_contract

sub get_license_version {
   my $k;
   my $lic_version_cnt = get_snmp_value($session, $oid_license_version_count );
   if ( $lic_version_cnt > 0 ) {
      my %license_version_descpriction_table = %{get_snmp_table($session, $oid_license_version_description_table)};
      #last real update
      my %license_version_upd_time_table = %{get_snmp_table($session, $oid_license_version_upd_time_table)};
      my %license_version_upd_method_table = %{get_snmp_table($session, $oid_license_version_upd_method_table)};
      #last try
      my %license_version_try_time_table = %{get_snmp_table($session, $oid_license_version_try_time_table)};
      my %license_version_try_result_table = %{get_snmp_table($session, $oid_license_version_try_result_table)};
      #update method: "scheduled" , manual @tryresultOK = ("Updates Installed", "No Updates");
      my @tryresultfailure = ("Connectivity failure", "No Updates", "Unauthorized");
      my @license_failed_table;
      my @license_version_table;
      $k = 1;
      my ($lic_version_scheduled_cnt, $lic_version_manual_cnt) = 0;
      my $return_string_errors = "";
      while ($k <= $lic_version_cnt) {
        my $license_version_descpriction = $license_version_descpriction_table{$oid_license_version_description_table.'.'.$k};
        my $license_version_upd_time = $license_version_upd_time_table{$oid_license_version_upd_time_table.'.'.$k};
        my $license_version_upd_method = $license_version_upd_method_table{$oid_license_version_upd_method_table.'.'.$k};
        my $license_version_try_time = $license_version_try_time_table{$oid_license_version_try_time_table.'.'.$k};
        my $license_version_try_result = $license_version_try_result_table{$oid_license_version_try_result_table.'.'.$k};
        if($license_version_upd_method eq "scheduled")
        {
          # only check scheduled
          if ( grep { $_ eq $license_version_upd_method } @license_failed_table ){
            push (@license_failed_table, ($license_version_descpriction.'/ last try time: '.$license_version_try_time.' last error: '.$license_version_try_result));
          }
          $lic_version_scheduled_cnt++;
        }elsif($license_version_upd_method eq "manual"){
          $lic_version_manual_cnt++;
        }
         $k++;
      }
      if (@license_failed_table) {
          $return_string_errors .= sprintf(" $lic_version_scheduled_cnt / $lic_version_cnt scheduled updates with error [%s]", join(", ", @license_failed_table));
          $return_state = 'CRITICAL';
      }else{
          $return_state = "OK";
          $return_string_errors .= sprintf("All scheduled licenses are in appropriate state.");
      }
      $return_string = $return_state . ": " . $curr_device . " scheduled:" . $lic_version_scheduled_cnt . "  manual:" . $lic_version_manual_cnt;
      $return_string .=  $return_string_errors;
   } else {
      $return_string = "UNKNOWN: device has no license checks available";
      $return_state = "UNKNOWN";
   }
   return ($return_state, $return_string);
} # end license_version
# Get FortiManger Device State list and check its connect state (up/down) (critical) and all without sync (warning)
sub get_fmg_device_state {
   my $k;
   my $fmg_device_cnt = get_snmp_value($session, $oid_fmg_device_count);
   if ( $fmg_device_cnt > 0 ) {
      my %fmg_device_name_table = %{get_snmp_table($session, $oid_fmg_device_name_table)};
      my %fmg_device_adom_table = %{get_snmp_table($session, $oid_fmg_device_adom_table)};
      my %fmg_device_con_state_table = %{get_snmp_table($session, $oid_fmg_device_con_state_table)};
      my %fmg_device_config_state_table = %{get_snmp_table($session, $oid_fmg_device_config_state_table)};
      my $return_string_errors = "";
      my @fmg_device_down; # List all devices that are down
      my @fmg_device_config; # List all devices that are out of sync

      $return_state = "OK";
      $return_string = "All Devices are in appropriate state";

      $k = 1;
      while ($k <= $fmg_device_cnt) {
         my $fmg_device_name = $fmg_device_name_table{$oid_fmg_device_name_table.'.'.$k};
         my $fmg_device_adom = $fmg_device_adom_table{$oid_fmg_device_adom_table.'.'.$k};
         my $fmg_device_con_state = $fmg_device_con_state_table{$oid_fmg_device_con_state_table.'.'.$k};
         my $fmg_device_config_state = $fmg_device_config_state_table{$oid_fmg_device_config_state_table.'.'.$k};
         if ($fmg_device_con_state eq '2') {
            push (@fmg_device_down, ($fmg_device_name.'/'.$fmg_device_adom));
         }
         if ($fmg_device_config_state eq '2') {
            push (@fmg_device_config, ($fmg_device_name.'/'.$fmg_device_adom));
         }
         $k++;
      }
      if (@fmg_device_config) {
         $return_state = 'WARNING';
         $return_string_errors .= sprintf(" Config Out-Of-Sync[%s]", join(", ", @fmg_device_config));
      }
      if (@fmg_device_down ) {
         $return_string_errors .= sprintf(" DOWN[%s]", join(", ", @fmg_device_down));
         $return_state = 'CRITICAL';
      }
      # Write an output string...
      $return_string = $return_state . ": " . $curr_device . "  ";
      $return_string .=  $return_string_errors;

   } else {
      $return_string = "UNKNOWN: device has no connected devices available";
      $return_state = "UNKNOWN";
   }

   return ($return_state, $return_string);
} # end get_fmg_device_state

sub get_conserve_mode {
  my $oid_enter_trsh = $_[0];
  my $oid_leave_trsh = $_[1];
  my $label = $_[2];
  my $lowmem_capacity = get_snmp_value($session, $oid_lowmem_capacity);
  my $mem_enter_thrsh = get_snmp_value($session, $oid_enter_trsh);
  my $mem_leave_thrsh = get_snmp_value($session, $oid_leave_trsh);

  if ( $lowmem_capacity <= $mem_enter_thrsh ) {
    $return_state = "CRITICAL";
    $return_string = $label . " conserve mode entered !" ;
  } elsif ( $lowmem_capacity <= $mem_leave_thrsh ) {
    $return_state = "WARNING";
    $return_string = $label . " conserve mode may entered ";
  } else {
    $return_state = "OK";
    $return_string = "No " . $label . " conserve mode active";
  }

  $perf = "|'" . "low_mem_cap" . "'=" . $lowmem_capacity . ";" . $mem_enter_thrsh . ";" . $mem_leave_thrsh;
  $return_string = $return_state . ": " . $return_string . "  " . $curr_device . " (Current device: " . $curr_serial .") " . $perf;

  return ($return_state, $return_string);
} # end get_conserve_mode

sub close_snmp_session{
  my $session = $_[0];

  $session->close();
} # end close snmp session

sub get_snmp_value{
  my $session = $_[0];
  my $oid = $_[1];

  my (%result) = %{get_snmp_request($session, $oid) || die ("SNMP service is not available on ".$ip) };

  if ( ! %result ||  $result{$oid} =~ /noSuch(Instance|Object)/ ) {
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
  my $snmp_version       = "2";      # snmp version
  my $community     = "public"; # only for v1/v2c
  my $user_name     = "public"; # v3
  my $auth_password = "";       # v3
  my $auth_prot     = "sha";    # v3 auth algo
  my $priv_password = "";       # v3
  my $priv_prot     = "aes";    # v3 priv algo
  my $pri_serial    = "";       # primary fortinet serial no
  my $credentials_file = "";    # file with credentials
  my $reset_file    = "";
  my $type          = "status";
  my $warn          = 80;
  my $crit          = 90;
  my $expected      = "";
  my $slave         = 0;
  my $vpnmode       = "both";
  my $mode          = 2;
  my $blacklist     = undef;
  my $whitelist     = undef;
  my $nosync        = undef;
  my $path          = "/usr/local/nagios/var/spool/FortiSerial";
  my $help          = 0;
  my $version       = 0;

  pod2usage(-message => "UNKNOWN: No Arguments given", -exitval => 3,  -sections => 'SYNOPSIS' ) if ( !@ARGV );

  GetOptions(
          'host|H=s'         => \$ip,
          'port|P=i'         => \$port,
          'snmp_version|v:s'      => \$snmp_version,
          'community|C:s'    => \$community,
          'username|U:s'     => \$user_name,
          'authpassword|A:s' => \$auth_password,
          'authprotocol|a:s' => \$auth_prot,
          'privpassword|X:s' => \$priv_password,
          'privprotocol|x:s' => \$priv_prot,
          'credentials_file|F:s' => \$credentials_file,
          'type|T=s'         => \$type,
          'serial|S:s'       => \$pri_serial,
          'vpnmode|V:s'      => \$vpnmode,
          'mode|M:s'         => \$mode,
          'blacklist|B:s'    => \$blacklist,
          'whitelist|W:s'    => \$whitelist,
          'warning|w:s'      => \$warn,
          'critical|c:s'     => \$crit,
          'expected|e:s'     => \$expected,
          'slave|s:1'        => \$slave,
          'reset|R:1'        => \$reset_file,
          'path|p:s'         => \$path,
          'help|h!'          => \$help,
          'version!'          => \$version,
  ) or pod2usage(-exitval => 3, -sections => 'OPTIONS' );

  if( $version )
  {
    print "$script version: $script_version. no check performed.\n";
    exit($status{'OK'});
  }
  pod2usage(-exitval => 3, -verbose => 3) if $help;

  # removing any non digits
  if ( $type ne "firmware" and $type ne "wtp" ) {
    $warn =~ s/\D*(\d+)\D*/$1/g;
    $crit =~ s/\D*(\d+)\D*/$1/g;
  }

  # allow "any" for WTP critical
  if ( $type eq "wtp" && $crit ne "any") {
    $crit =~ s/\D*(\d+)\D*/$1/g;
  }

  # allow "any" for WTP warning
  if ( $type eq "wtp" && $warn ne "any") {
    $warn =~ s/\D*(\d+)\D*/$1/g;
  }

  # read credentials from file, if specified
  if ($credentials_file ne '') {
    if( ! -e $credentials_file ) {
      print "Credentials file parameter specified, but file does not exist!\n";
      exit(1);
    }

    # open credentials file
    if (!open(CFD, '<'.$credentials_file)) {
      print "Could not open credentials file: $!\n";
      exit(1);
    }

    # read credentials file and overwrite parameters
    while (my $cfd_line = <CFD>) {
      chomp($cfd_line);
      if($cfd_line =~ /^authpassword:(.+)$/) {
        $auth_password = $1;
      } elsif($cfd_line =~ /^privpassword:(.+)$/) {
        $priv_password = $1;
      } elsif($cfd_line =~ /^community:(.+)$/) {
        $community = $1;
      } # else - skip
    }
    close(CFD);
  }

  return (
    $ip, $port, $community, $type, $warn, $crit, $expected, $slave, $pri_serial, $reset_file, $mode, $vpnmode,
    $blacklist, $whitelist, $nosync, $snmp_version, $user_name, $auth_password, $auth_prot, $priv_password, $priv_prot, $path
  );
}

=head1 NAME

Check Fortinet FortiGate Appliances

=head1 SYNOPSIS

=over 1

=item B<check_fortigate.pl -H -C -T [-w|-c|-S|-s|-R|-M|-V|-U|-A|-a|-X|-x|-h|-F|-?]>

=back

=head1 OPTIONS

=over 4

=item B<-H|--host>

STRING or IPADDRESS - Check interface on the indicated host

=item B<-P|--port>

INTEGER - SNMP Port on the indicated host, defaults to 161

=item B<-v|--snmp_version>

INTEGER - SNMP Version on the indicated host, possible values 1,2,3 and defaults to 2

=back

=head2 SNMP V3

=over 1

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

=head2 SNMP v1/v2c

=over 1

=item B<-C|--community>
STRING - Community-String for SNMP, defaults to public only used with SNMP version 1 and 2

=back

=head2 SNMP v1/v2c/3 - common

=over 1

=item B<-F|--credentials_file>
STRING - File containting credentials (privpassword/authpassword/community)
as an alternative to --authpassword/--privpassword/--community

=back

    Sample file contents:
    authpassword:auth password here
    privpassword:priv password here

=head2 Other

=over

=item B<-T|--type>
STRING - CPU, MEM, cpu-sys, mem-sys, ses, VPN, net, disk, ha, hasync, uptime, Cluster, wtp, switch, hw, fazcpu, fazmem, fazdisk, sdwan-hc, pktloss, pktloss2, fmgdevice, license, license-version, linkmonitor-hc

=item B<-S|--serial>
STRING - Primary serial number.

=item B<-s|--slave>
BOOL - Get values of slave

=item B<-w|--warning>
INTEGER - Warning threshold, applies to cpu, cpu-sys, mem, mem-sys, disk, net, ses, ses-ipv4, ses-ipv6, uptime, license.

=item B<-w|--warning>
INTEGER or STRING - Warning threshold or word "any", applies to wtp

=item B<-c|--critical>
INTEGER - Critical threshold, applies to cpu, cpu-sys, mem, mem-sys, disk, net, ses, ses-ipv4, ses-ipv6, license.

=item B<-c|--critical>
INTEGER or STRING - Critical threshold or word "any", applies to wtp

=item B<-e|--expected>
INTEGER - Critical threshold, applies to ha.

=item B<-R|--reset>
BOOL - Resets ip file (cluster only)

=item B<-n|--nosync>
BOOL - Exclude cluster synchronisation check (cluster only)

=item B<--ignoreexpiredlicense>
BOOL - Exclude expired licenses

=item B<-M|--mode>
STRING - vpn tunnel: Output-Mode: 0 => just print, 1 => print and show failed tunnel, 2 => critical
STRING - license 1 => show expired license, 2 => dont show expired license

=item B<-V|--vpnmode>
STRING - VPN-Mode: both => IPSec & SSL/OpenVPN, ipsec => IPSec only, ssl => SSL/OpenVPN only

=item B<-W|--whitelist>
STRING - Include only entries matching a regular expression (applies before --blacklist).
Currently only applies to IPSec tunnel names.

=item B<-B|--blacklist>
STRING - Exclude entries matching a regular expression (applies after --whitelist).
Currently only applies to IPSec tunnel names

=item B<-p|--path>
STRING - Path to store serial filenames

=item B<--version>
display script version; no check is performed.


=back

=head1 DESCRIPTION

This plugin checks Fortinet FortiGate devices via SNMP

=head2 From Web

=over 4

=item 1.
Select Network -> Interface -> Local interface

=item 2.
Administrative Access: Enable SNMP

=item 3.
Select Config -> SNMP

=item 4.
Enable SNMP, fill your details

=item 5.
SNMP v1/v2c: Create new

=item 6.
Configure for your needs, Traps are not required for this plugin!

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

