#!/usr/bin/php -q
<?php
/* 
This plugin checks the DWD Web Output for a given Region 

 Author: Oliver Skibbe (oliskibbe (at) gmail.com)
 Date: 2015-03-31

 Changelog:
 Release 1.0 (2015-03-31)
 - initial release

*/

if ( $argc <= 2 ) {
	help();
}

$region = ( empty($argv[1]) ) ? "HAN" : strtoupper($argv[1]);
$region_name = ( empty($argv[2]) ) ? "Hannover" : $argv[2];

$url = "http://www.dwd.de/dyn/app/ws/html/reports/" . $region . "_warning_de.html";

$regex = "@.*Es (sind|ist) (?<warnung_count>\d+) Warnung.*Amtliche UNWETTERWARNUNG (?<warnung>.*) </p>.*von: (?<von_datum>\w+, \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} Uhr) </p>.*bis: (?<bis_datum>\w+, \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} Uhr) </p>.*@isUm";

$output = "OK: keine Warnungen für " . $region_name .  " auf " . $url . " gefunden|'aktive_warnungen'=0";
$out_state = 0;

// create curl resource 
$ch = curl_init(); 

// set url 
curl_setopt($ch, CURLOPT_URL, $url); 

//return the transfer as a string 
curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1); 

// $output contains the output string 
$dwd_output = curl_exec($ch); 

if ( curl_errno($ch) || curl_error($ch) ) {
	$output = "UNKNOWN: CURL failed: Error no: " . curl_errno($ch) . " output: " . curl_error($ch);
	$out_state = 3;

} else {

	$preg_return = preg_match($regex, $dwd_output, $matches);
	if ( $preg_return ) {

		$output = "CRITICAL: " . $matches['warnung_count'] . " Warnung(en) für " . $region_name . " gefunden, " . $matches['warnung'] . " von: " . $matches['von_datum'] . " bis: " . $matches['bis_datum'] . PHP_EOL . "URL: " . $url;
		$perf = "'aktive_warnungen'=" . $matches['warnung_count'];
		$out_state = 2;
	} else {
		$output = "UNKNOWN: output does not match given regex";
		$out_state = 3;
	}
}

// close curl resource to free up system resources 
curl_close($ch);

echo $output . "|" . $perf;
exit($out_state);

function help() {
	global $argv;

        echo basename($argv[0]) . " region region_name 
\targ1\tDWD Region e.g. HAN
\targ2\tRegion name, for better looking output e.g. Hannover
";

        exit(3);
}

// EOF
