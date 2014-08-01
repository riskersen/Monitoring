#!/usr/bin/php -q
<?php

function strposa($haystack, $needles=array(), $offset=0) {
	$chr = array();
	foreach($needles as $needle) {
#		echo "Haystack: " . $haystack . " Needle: " . $needle . PHP_EOL;
		$res = strpos($haystack, $needle, $offset);
                if ($res !== false) $chr[$needle] = $res;
        }
        if(empty($chr)) return false;
        return min($chr);
}

// option parsing
$options = getopt("s:u:p:e:h");
$debug = false;

if ( isset($options['h']) ) {
        help();
}

$excludeList = ( !empty($options['e']) ? explode(",",$options['e']) : Array());

// connection
$server = $options['s'];
$username = $options['u'];
$password = $options['p'];

// init var
$failed_jobs = 0;
$succeeded_jobs = 0;

// mssql connect
$link = mssql_connect($server,$username,$password);

if ( ! $link ) {
	echo "CRITICAL Connection failed: " . mssql_get_last_message();
	exit(2);
}

// options for mssql
mssql_query("SET ANSI_NULLS ON", $link);
mssql_query("SET ANSI_WARNINGS ON", $link);

// check sql server version
$version_query = mssql_query("SELECT @@VERSION");
$version = mssql_fetch_row($version_query);
$sqlserver_2000 = strpos($version[0], "8.00.") ? true : false;

if ( $debug ) {	
	if ( $sqlserver_2000) { echo "SQL Server 2000 gefunden";} else {echo "SQL Server neuer als 2000 gefunden"; }
}

// execute stored procedure MonitorJobs
$sql = "EXEC sp_MonitorJobs";
$query = mssql_query($sql, $link);

if (mssql_num_rows($query)) {
	/* Job Array
	(
	    [ServerName] => HYDMEDIA
	    [job_name] => Verteilungscleanup: distribution
	    [job_status] => Enabled
	    [last_run_status] => Succeeded
	    [last_run_date] => May  7 2014 02:25:00:000PM
	    [run_duration] => 00:00:00
	    [next_scheduled_run_date] => May  7 2014 02:34:59:997PM
	    [step_description] => Der Auftrag war erfolgreich.  Der Auftrag wurde von Zeitplan 105 (Plan für den Replikations-Agent.) aufgerufen.  Als Letztes wurde Schritt 1 (Führt den Agent aus.) ausgeführt.
	)
	*/
	// init array
	$succeeded_jobArray = Array();
	$failed_jobArray = Array();

	while ($job = mssql_fetch_array($query, MSSQL_ASSOC)) {
		// proceed if job is not excluded
        	if ( strposa(trim($job['job_name']), $excludeList) === false ) {
			if ( $job['last_run_status'] != 'Succeeded' ) {
				$failed_jobArray[] = $job; 
			} else {
				$succeeded_jobArray[] = $job;
			}
		}
	}

#	$count_failed_jobs = count($failed_jobArray);
	$succeeded_jobs = ( ! empty($succeeded_jobArray)) ? ( max(array_keys($succeeded_jobArray)) + 1) : 0;
	$failed_jobs = ( ! empty($failed_jobArray)) ? ( max(array_keys($failed_jobArray)) + 1) : 0;

	if ($failed_jobs > 0) {
		$return_code = 2;
		$return_msg = $failed_jobs . " fehlerhafte jobs gefunden, $succeeded_jobs erfolgreiche Jobs gefunden\n";
		foreach ( $failed_jobArray as $failed_job ) {
			$return_msg = $return_msg . "Job-Name: " . $failed_job['job_name'] . "\tJob-Status: " . $failed_job['last_run_status'] . "\tBeschreibung: " . $failed_job['step_description'] . "\tLetzter Lauf: " . $failed_job['last_run_date'] . "\n";
		}
	} else {
		$return_msg = "Keine fehlerhaften Jobs gefunden, $succeeded_jobs erfolgreiche Jobs gefunden";
		$return_code = 0;
	}
} else {
	$return_msg = "Keine Jobs gefunden";
	$return_code = 0;
}

switch($return_code) {
        case 1:
                $return_state = "WARNING: "; break;
        case 2:
                $return_state = "CRITICAL: "; break;
        case 3:
                $return_state = "UNKNOWN: "; break;
        default:
                $return_state = "OK: ";
}

echo $return_state . $return_msg . "|'failed_jobs'=" . $failed_jobs . " 'succeeded_jobs'=". $succeeded_jobs . PHP_EOL;
exit($return_code);

function help() {
        echo "checks configured sql server for failed jobs (needs stored procedure 'sp_MonitorJobs'
\t-s\tserver e.g. 'sql06'
\t-u\tusername e.g. 'domain\dbsnmp'
\t-p\tpassword e.g. '123foobar'
\t-e\texclude e.g. 'jobname'
\t-h\tprints this text
";

        exit(3);
}
// EOF
