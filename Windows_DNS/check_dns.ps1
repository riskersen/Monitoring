##############################################################################
#
# NAME: 	check_dns_lookup.ps1
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
# 1.0 2015-01-21 - initial version
#
##############################################################################

[CmdletBinding()]

Param(
    [string]$dns_server,
    [string]$host_name
    )

Function Resolve-Dns($hostname,$dnsserver){
    Function Get-Matches($Pattern,$groupNumber = 0) {begin { $regex = New-Object Regex($pattern) };process { foreach ($match in ($regex.Matches($_))) { ([Object[]]$match.Groups)[$groupNumber].Value }}}
	
	# launch nslookup proc
    $proc = New-Object System.Diagnostics.Process
    $procStartInfo = New-Object System.Diagnostics.ProcessStartInfo("nslookup"," -type=A $hostname $dnsserver")
    $procStartInfo.UseShellExecute = $false
    $procStartInfo.RedirectStandardOutput = $true
	$procStartInfo.RedirectStandardError = $true;
    $proc.StartInfo = $procStartInfo
    $proc.Start() | out-null
    $proc.WaitForExit()
	
    $sOutput = $proc.StandardOutput.ReadToEnd()
    $eOutput = "Error: " + $proc.StandardError.ReadToEnd()
	
	# grep for ips
    $ips = $sOutput | Get-Matches "(?s)Name:.*Address(es)?:(.*)" 2 | Get-Matches "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" 0
	#Write-Host $ips
	# return
    if ($ips.Length -gt 0) {
		$ips
	} else {
		$eOutput
	}
}
	
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
#$dnsResult = (Resolve-DnsName -DnsOnly -Server "$ext_dns_server" -Type "$dns_type" | Select-Object LastWriteTime, Name)
$dnsResult = (Resolve-Dns "$host_name" "$dns_server")


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
