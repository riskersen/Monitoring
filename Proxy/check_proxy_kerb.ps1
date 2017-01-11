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
#			Auth possible and website returns 200 - OK (0)
#			Auth impossible or website returned something strange - CRITICAL (2)
#			Script errors - UNKNOWN (3)
#
# CHANGELOG:
# 0.8 2016-07-26 - initial version
# 0.9 2016-11-16
# 			     - fixed web timeout
# 			     - fixed output and return state in case of code matches but 
#                  content not and vice versa
#                - Output for GPO 'Prevent running First Run Wizard' needs to be enabled
#                  this is needed when using a service account which never logs in and
#                  uses IE
# 1.0 2017-01-10
#                - SSL/TLS configuration applied
#                - added new option for displaying received content
#                - added generic error message output
#
##############################################################################

[CmdletBinding()]

Param(
    [string]$proxy_server,
	[Int]$proxy_port,
    [string]$target_url,
    [Int]$expected_code,
    [string]$expected_content,
    [Int]$warn_response_time = 20,
    [Int]$crit_response_time = 30,
    [Int]$display_content = 0
)

# nagios return stuff
$returnStates = @{0 = 'OK'; 1 = 'WARNING'; 2 = 'CRITICAL'; 3 = 'UNKNOWN' }
# defaults
$returnState = 3
$returnString = ""

# Allow all SSL/TLS protocols to be used
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

$timeTaken = Measure-Command -Expression {
    Try {
    
            # try to fetch web page via requested proxy
            $proxyResult = ( Invoke-WebRequest -Proxy http://${proxy_server}:${proxy_port} -ProxyUseDefaultCredentials -Uri ${target_url} -TimeoutSec $crit_response_time )
    } Catch {
        # this is needed for any other statuscode than 200
        $proxyResult = $_.Exception.Response
        $errorMessage = $_.Exception.Message

        If ( $errorMessage -Like "*first-launch configuration is not complete.*" ) {
            Write-Host "UNKNOWN: GPO 'Prevent running First Run Wizard' needs to be enabled"
            exit 3
        } ElseIf ( $errorMessage -Like "*The operation has timed out*" ) {
            Write-Host "UNKNOWN: Webrequest timed out"
            exit 3
        # plain web request exception if nothing matches in prior
        } ElseIf ( $errorMessage -is [string] ) {
            Write-Host "UNKNOWN: $errorMessage"
            exit 3
        } else {
            # get content of webpage
            $reader = New-Object System.IO.StreamReader($proxyResult.GetResponseStream())
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $content = $reader.ReadToEnd();
        }
    }
}
# Finally {

        # response time
        $seconds = $timeTaken.TotalSeconds
        $seconds = [Math]::Round($seconds, 2)
        $perf = "'response_time'=" + $seconds + "s;" + $warn_response_time + ";" + $crit_response_time

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

        }

        # ------
        # Comparison of content
        # raise level to CRIT if content doesn't match
        # ------
        if ( $expected_content -is [string] -And $expected_content.Length -gt 0 -And $content -NotLike "*$expected_content*" ) {

            if ( $returnString.Length -gt 0 -And $returnState -eq 0 ) {
                $returnString = $returnString + " but"
            } Else {
                $returnString = $returnString + " and"
            }

            $returnString = $returnString + " content didn't match filter: '" + $expected_content + "'"

            $returnState = 2

        } elseif ( $expected_content -is [string] -And $expected_content.Length -gt 0 -And $content -Like "*$expected_content*" ) {

            if ( $returnString.Length -gt 0 -And $returnState -eq 2) {
                $returnString = $returnString + " but"
            } Else {
                $returnString = $returnString + " and"
            }
            $returnString = $returnString + " content matches " + $expected_content

            # if response didn't match, we won't lower the return code
            If ( $returnState -eq 0 ) {
                $returnState = 0
            }
        } 
        $returnString = $returnStates[$returnState] + ": " + $returnString + "|" + $perf

        If ( $display_content -eq 1 ) {
            $returnString = $returnString + "`n" + "Fetched Content:" + $content
        }

    Write-Host $returnString
    exit $returnState
#}