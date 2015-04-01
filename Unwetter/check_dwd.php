#!/usr/bin/php -q
<?php
/* 
This plugin checks the DWD Web Output for a given Region 

 Author: Oliver Skibbe (oliskibbe (at) gmail.com)
 Date: 2015-03-31

 Changelog:
 Release 1.0 (2015-03-31)
 - initial release

 Release 1.1 (2015-04-01)
 - modified REGEX to support CRIT and WARN (UNWETTERWARNUNG > WARNUNG)
 - code clean up

*/

if ( $argc <= 2 ) {
	help();
}

$region = strtoupper($argv[1]);
$region_name = $argv[2];

$url = "http://www.dwd.de/dyn/app/ws/html/reports/" . $region . "_warning_de.html";

$crit_regex = "@.*Es (sind|ist) (?<warnung_count>\d+) Warnung.*Amtliche UNWETTERWARNUNG (?<warnung>.*) </p>.*von: (?<von_datum>\w+, \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} Uhr) </p>.*bis: (?<bis_datum>\w+, \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} Uhr) </p>.*@isUm";
$warn_regex = "@.*Es (sind|ist) (?<warnung_count>\d+) Warnung.*Amtliche (?<warnung>.*) </p>.*von: (?<von_datum>\w+, \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} Uhr) </p>.*bis: (?<bis_datum>\w+, \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} Uhr) </p>.*@isUm";


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

// $output contains the output string 
$dwd_output = curl_exec($ch); 

if ( curl_errno($ch) || curl_error($ch) ) {
	$output = "UNKNOWN: CURL failed: Error no: " . curl_errno($ch) . " output: " . curl_error($ch);
	$out_state = 3;

} else {
	// crit regex
	if ( preg_match($crit_regex, $dwd_output, $matches) ) {
		$out_state = 2;
	// warn regex
	} else if ( preg_match($warn_regex, $dwd_output, $matches) ) {
		$out_state = 1;
	} else {
		$out_state = 0;
	}

	if ( $out_state > 0 ) {
		$output = $matches['warnung_count'] . " Warnung(en) für " . $region_name . " gefunden, " . $matches['warnung'] . " von: " . $matches['von_datum'] . " bis: " . $matches['bis_datum'];
	} else {
		$output = "keine Warnungen für " . $region_name .  " auf " . $url . " gefunden";
	}
	
	$perf = sprintf("'aktive_warnungen'=%s", ( $matches['warnung_count'] !== '' ) ? $matches['warnung_count'] : 0 );
}

// close curl resource to free up system resources 
curl_close($ch);

echo $nagios_return[$out_state] . ": " . $output . PHP_EOL . "URL: " . $url . "|" . $perf;
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
