#!/usr/bin/php
<?php
/*
	Author: Oliver Skibbe
	Date: 2013-10-21
	Contact: oliskibbe(at)gmail.com
	Purpose: checks given paths for files with or without extensions
*/

function strposa($haystack, $needles=array(), $offset=0) {
      $chr = array();
      foreach($needles as $needle) {
                $res = strpos($haystack, $needle, $offset);
                if ($res !== false) $chr[$needle] = $res;
        }
        if(empty($chr)) return false;
        return min($chr);
}

// option parsing
$options = getopt("p:t:w:c:he:k:v:x:");

if ( isset($options['h']) ) {
	help();
}

// path
$path = $options['p'];
// extension with fallback to all files if no ext is given
$ext = ( !empty($options['e']) ? $options['e'] : "");

// exclude pattern
$excludeList = ( !empty($options['x']) ? explode(",",$options['x']) : Array());

// label
$labelKey = $options['k'];
$labelValue = $options['v'];

// seconds till to old
$tooOldSecondsCrit = $options['t'];
$tooMuchFilesWarn = $options['w'];
$tooMuchFilesCrit = $options['c'];

// current timestamp
$now = time();

// nagios stuff
$return_code = 0;
$return_msg = "Everything's fine";
$perf_msg = "";


// check every subfolder for .zip.aes
$fileArray = glob($path . "/*/*" . $ext);

// helper
$i = 0;
$j = 0;
$filesTooOldArray = Array();

foreach ( $fileArray as $file ) {
	
	// break if file matches exclude pattern
	if ( ! strposa($file,$excludeList) ) { 
		// get file modification time
		$fileMTime = fileatime($file);
		// calculate file age in seconds 
		if ( ($now - $fileMTime) > $tooOldSecondsCrit ) {
			// remove path
			$file = str_replace(Array($path . "/", $ext), "", $file);
			// split too gutachter and filename
			$file = explode("/", $file);
	
			// build Array
			if ( array_key_exists($file[0], $filesTooOldArray )) {
				$filesTooOldArray[$file[0]] .= ", " . $file[1];
			} else {
				$filesTooOldArray[$file[0]] = $file[1];
			}
	
			unset($file);
			$j++;
		}
		// count for max files
		$i++;
	}
}

// count files and return
if ( $i >= $tooMuchFilesWarn ) {
	$return_code = 1;
	if ( $i >= $tooMuchFilesCrit ) {
		$return_code = 2;

	}
	$return_msg = "Too much files found:" . $i;
}

if ( $j > 0 ) {
	$return_msg = "Filecount: $i, Files too old: " . $j . " -"; 
	foreach ( $filesTooOldArray as $key => $value ) {
		$return_msg .= " " . $labelKey . ": " . $key . " " . $labelValue . ": " . $value;
	}
	$return_code = 2;
}

$perf_msg = "|'filecount'=" . $i . ";" . $tooMuchFilesWarn . ";" . $tooMuchFilesCrit . " 'oldfiles'=" . $j ;

switch($return_code) {
	case 1:
		$return_state = "WARNING: "; break;
	case 2:
		$return_state = "CRITICAL: "; break;
	default:
		$return_state = "OK: ";
}

echo $return_state . $return_msg . $perf_msg . PHP_EOL;
exit($return_code);

function help() {
	echo "checks configured folder
\t-w\twarning for file count
\t-c\tcritical for file count
\t-t\ttime after which a file is considered too old
\t-p\tpath e.g. '/mnt/dmzweb/ams/sftproot/home/AMS_EXCHANGE/IMPORT'
\t-e\textension e.g. '.zip.aes'
\t-k\tlabel key e.g. Gutachter
\t-v\tlabel value e.g. Auftragsnummer
\t-h\tprints this text
";
		
	exit(3);
}
// EOF
