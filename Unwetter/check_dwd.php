#!/usr/bin/php -q
<?php
/* 
This plugin checks the DWD Web Output for a given Region 

 Author: Oliver Skibbe (oliskibbe (at) gmail.com)
 Web: http://oskibbe.blogspot.com / https://github.com/riskersen
 Date: 2018-06-07

 Changelog:
 Release 1.0 (2015-03-31)
 - initial release

 Release 1.1 (2015-04-01)
 - modified REGEX to support CRIT and WARN (UNWETTERWARNUNG > WARNUNG)
 - code clean up

 Release 1.2 (2015-04-21)
 - added ignore warning support

 Release 1.5 (2015-04-24)
 - added proxy support
 
 Release 1.6 (2018-06-07)
 - follow redirects (up to 30)
 - adjusted regex to reflect website changes
 - added possibility to choose between BASIC and NTLM proxy authentication method

*/

function stripos_array( $needle, $haystack ) {
	if ( !is_array( $haystack ) ) {
		if ( stripos( $needle, $haystack ) ) {
			return $element;
		}
	} else {
		foreach ( $haystack as $element ) {
			if ( stripos( $needle, $element ) ) {
				return $element;
			}
		}
	}

	return false;
}

if ( $argc <= 1 ) {
	help();
}


// Proxy Settings 
$proxy_url = "";
$proxy_user = "";
$proxy_pass = "";
// can be also CURLAUTH_NTLM
$proxy_method = "CURLAUTH_BASIC";


// curl timeout settings
$connect_timeout = 5;
$timeout = 15;


// warnings which should be ignored
$ignore_warnung = Array( "WINDBÖEN", "NEBEL");

$region_name = $argv[1];

$url = "http://www.dwd.de/DE/wetter/warnungen/warntabelle_node.html";

$region_regex = "@<h2 id=.*{$region_name}.*>.*<table>(?<output>.*)</table>@isUm";

$crit_regex = "@.*<td>Amtliche UNWETTERWARNUNG.*(?<warnung>.*)</td><td>(?<von_datum>.*)</td><td>(?<bis_datum>.*)</td>.*@isUm";
$warn_regex = "@.*<td>Amtliche (?<warnung>.*)</td><td>(?<von_datum>.*)</td><td>(?<bis_datum>.*)</td>.*@isUm";

$ok_string = "Es sind keine Warnungen";


$nagios_return = Array( 
			0 => "OK",
			1 => "WARNING",
			2 => "CRITICAL",
			3 => "UNKNOWN",
);

// create curl resource 
$ch = curl_init(); 

// set url 
curl_setopt($ch, CURLOPT_URL, $url); 

//return the transfer as a string 
curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1); 

// follow redirect
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);
curl_setopt($ch, CURLOPT_MAXREDIRS , 30);

// curl connect timeout
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, $connect_timeout);
curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);

// curl proxy settings
if ( $proxy_url != "" ) { 
	curl_setopt($ch, CURLOPT_PROXYAUTH, $proxy_method);
	curl_setopt($ch, CURLOPT_PROXY, $proxy_url);    
}

if ( $proxy_user != "" ) {
	curl_setopt($ch, CURLOPT_PROXYUSERPWD, $proxy_user . ":" . $proxy_pass);
}

// set UA
curl_setopt($ch,CURLOPT_USERAGENT,'Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.8.1.13) Gecko/20080311 Firefox/2.0.0.13');

// $dwd_output contains the output string 
$dwd_output = curl_exec($ch); 
$curl_errno = curl_errno($ch);

if ( $curl_errno != 0 || curl_error($ch) ) {
	$output = "CURL failed: Error no: " . $curl_errno . " error: " . curl_error($ch);
	$perf = "";
	$out_state = 3;

} else {
	// helper
	$matches = Array();

	// first check for region and get all the output to a helper string
	if ( preg_match($region_regex, $dwd_output, $region)) {

		// convert html chars to human-readable chars
		$region['output'] = html_entity_decode($region['output'], ENT_COMPAT, "UTF-8");

		// crit regex
		if ( preg_match($crit_regex, $region['output'], $matches) ) {
			$out_state = 2;
		// warn regex
		} else if ( preg_match($warn_regex, $region['output'], $matches) ) {
			$out_state = 1;
		// ok string check stristr should be more performant
		} else if ( stristr($region['output'], $ok_string ) ) {
			$out_state = 0;
		// this should not never happen
		} else {
			$out_state = 3;
		}


		// ignore return
		$out_state = ( ! stripos_array( $matches['warnung'] , $ignore_warnung ) ) ? $out_state : 0;
	
		if ( $out_state > 2 ) {
			$output = "Kein gültiges Ergebnis gefunden. Bitte überprüfen Sie die URL " . $url . " und melden sich beim Autor des Plugins";
	
		} else if ( $out_state > 0 ) {
			// XXX currently no real check for count of warnings
			$matches['warnung_count'] = 1;
			$output = "1 Warnung(en) für " . $region_name . " gefunden, " . $matches['warnung'] . " von: " . $matches['von_datum'] . " bis: " . $matches['bis_datum'];
		} 
	} else {
		$out_state = 0;
		$output = "keine Warnungen für " . $region_name .  " auf " . $url . " gefunden";
	}
	
	$perf = sprintf("'aktive_warnungen'=%s", ( array_key_exists('warnung_count', $matches) && $matches['warnung_count'] !== '' ) ? $matches['warnung_count'] : 0 );
}

// close curl resource to free up system resources 
curl_close($ch);

echo $nagios_return[$out_state] . ": " . $output . PHP_EOL . "URL: " . $url . "|" . $perf;
exit($out_state);

function help() {
	global $argv;

        echo basename($argv[0]) . " region_name
\targ1\tRegion name e.g. Hannover
";

        exit(3);
}

// EOF
