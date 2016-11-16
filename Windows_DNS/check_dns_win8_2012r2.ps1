##############################################################################
#
# NAME: 	check_dns_win8_2012r2.ps1
#
# AUTHOR: 	Oliver Skibbe
# EMAIL: 	oliskibbe (at) gmail.com
#
# COMMENT:  Script to check dns lookup, should be called via NRPE/NSClient++
#
#			Return Values for NRPE:
#			DNS answers correctly - OK (0)
#			DNS did not answer - CRITICAL (2)
#			Script errors - UNKNOWN (3)
#
# CHANGELOG:
# 1.0 2016-11-16 - initial version
#
##############################################################################

[CmdletBinding()]

Param(
    [string]$dns_server,
    [string]$host_name
    )
	
# check params
if ( ! ( $dns_server -As [IPAddress]) -As [Bool] ) {
    Write-Host "DNS-Server not a valid IP-address...exiting"
    exit 2
} 

if ( ! ( $host_name ) ) {
    Write-Host "Host-Name should not be empty..exiting"
    exit 2
} 

# nagios return stuff
$returnStateOK = 0
$returnStateWarning = 1
$returnStateCritical = 2
$returnStateUnknown = 3


# only at windows 2012r2 / windows 8.1
$dnsResult = (Resolve-DnsName -DnsOnly -Server "$ext_dns_server" -Type "$dns_type" | Select-Object LastWriteTime, Name)

if ( ( $dnsResult -like "Error:*" ) ) {
    $returnString = "CRITICAL dns server " + $dns_server + ": " + $dnsResult
    $returnState = $returnStateCritical
} else {
	$dnsResult = "$dnsResult"
    $returnString = "OK: dns returned $dnsResult"
    $returnState = $returnStateOK
}

Write-Host $returnString
exit $returnState
