##############################################################################
#
# NAME: 	check_proxy_kerberos.ps1
#
# AUTHOR: 	Oliver Skibbe
# EMAIL: 	oliskibbe (at) gmail.com
#
# COMMENT:  Script to check proxy with kerberos authentication, 
#			should be called via NRPE/NSClient++
#
#			Return Values for NRPE:
#			OK (0)        - Expected content and status code matches and response time is okay
#           WARNING (1)   - response time reached warn level
#			CRITICAL (2)  - Auth impossible or website returned something strange or crit response time reached
#			Script errors - UNKNOWN (3)
#
# CHANGELOG:
# 1.0 2016-07-26 - initial version
#
##############################################################################

[CmdletBinding()]

Param(
    [string]$proxy_server,
	[Int]$proxy_port,
    [string]$target_url,
    [Int]$expected_code,
    [string]$expected_content,
    [Int]$warn_response_time = 15,
    [Int]$crit_response_time = 30
)

# nagios return stuff
$returnStates = @{0 = 'OK'; 1 = 'WARNING'; 2 = 'CRITICAL'; 3 = 'UNKNOWN' }

# defaults
$returnState = 3
$returnString = ""

# we want to measure how long it will take to get the result
$timeTaken = Measure-Command -Expression {
    Try {
    
            # try to fetch web page via requested proxy
            $proxyResult = ( Invoke-WebRequest -Proxy http://${proxy_server}:${proxy_port} -ProxyUseDefaultCredentials -Uri ${target_url} )

    } Catch {
        # this is needed for any other statuscode than 200
        $proxyResult = $_.Exception.Response

        # get content of webpage
        $reader = New-Object System.IO.StreamReader($proxyResult.GetResponseStream())
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $content = $reader.ReadToEnd();
    } # endCatch

} # end timeTaken


# response time
$response_time = $timeTaken.TotalSeconds
$response_time = [Math]::Round($response_time, 2)
$perf = "'response_time'=" + $response_time + "s;" + $warn_response_time + ";" + $crit_response_time

# needs to be declared as Int, otherwise it would trigger enum (403 results in forbidden) on status code != 200
$statusCode = [Int]$proxyResult.StatusCode

# if not coming from exception, use generic Content property
if ( $content -isnot [string] ) {
    $content = $proxyResult.Content
}
    
# ------
# Comparison of http status code
# raise level to CRIT if code doesn't match
# ------
if ( $expected_code -is [Int] -And $statusCode -ne $expected_code ) {

    $returnString = $returnString + "Code '" + $expected_code + "' didn't match:'" + $statusCode + "'"
    $returnState = 2

} elseif ( $expected_code -is [Int] -And $statusCode -eq $expected_code ) {

    $returnState = 0
    $returnString = $returnString + "Code matches '" + $expected_code + "'"

} #endExpectedCode

# ------
# Comparison of content
# raise level to CRIT if content doesn't match
# ------
if ( $expected_content -is [string] -And $content -NotLike "*$expected_content*" ) {

    if ( $returnString.Length -gt 0 ) {
        $returnString = $returnString + " and"
    }
    $returnString = $returnString + " content didn't match filter: '" + $expected_content + "'"

    $returnState = 2
} elseif ( $expected_content -is [string] -And $content -Like "*$expected_content*" ) {

    if ( $returnString.Length -gt 0 ) {
        $returnString = $returnString + " and"
    }
    $returnString = $returnString + " content matches filter: '" + $expected_content + "'"

    $returnState = 0
} # endExpectedContent


if ( $response_time -gt $crit_response_time ) {

    $returnState = 2
    $returnString = $returnString + " response time '" + $response_time + "s' above '" + $crit_response_time + "s'"

} elseif ( $response_time -gt $warn_response_time ) {

    if ( $returnState -le 2 ) {
        $returnState = 1
    }
    $returnString = $returnString + " response time '" + $response_time + "s' above '" + $warn_response_time + "s'"

} #endResponseTime


$returnString = $returnStates[$returnState] + ": " + $returnString + "|" + $perf

Write-Host $returnString
exit $returnState