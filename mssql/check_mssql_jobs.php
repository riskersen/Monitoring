#!/usr/bin/php -q
<?php
/*
 COPYRIGHT:

 This software is Copyright (c) 2015 Oliver Skibbe
                                <oliskibbe@gmail.com>
      (Except where explicitly superseded by other copyright notices)

 LICENSE:

 This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    Dieses Programm ist Freie Software: Sie können es unter den Bedingungen
    der GNU General Public License, wie von der Free Software Foundation,
    Version 3 der Lizenz oder (nach Ihrer Wahl) jeder neueren
    veröffentlichten Version, weiterverbreiten und/oder modifizieren.

    Dieses Programm wird in der Hoffnung, dass es nützlich sein wird, aber
    OHNE JEDE GEWÄHRLEISTUNG, bereitgestellt; sogar ohne die implizite
    Gewährleistung der MARKTFÄHIGKEIT oder EIGNUNG FÜR EINEN BESTIMMTEN ZWECK.
    Siehe die GNU General Public License für weitere Details.

    Sie sollten eine Kopie der GNU General Public License zusammen mit diesem
    Programm erhalten haben. Wenn nicht, siehe <http://www.gnu.org/licenses/>.



        Author: Oliver Skibbe (oliskibbe@gmail.com)
        URL: https://github.com/riskersen/Monitoring / http://oskibbe.blogspot.com
        Date: 2015-07-28
        Version: 1.0

        Changelog
                - 2015-07-20 (Oliver Skibbe): initial release
                - 2015-07-28 (Oliver Skibbe):
                        - performance improvements
                        - added expiry date check
                                - options x,y control warn/crit
                                - option d date output format
*/

if (!extension_loaded('pdo_dblib')) {
    if (!dl('pdo_dblib.so')) {
        echo "CRITICAL: extension pdo_dblib is not available, please install (using ubuntu/debian: php5-sybase, rhel-based [enable EPEL first]: php-mssql)" . PHP_EOL;
        exit(2);
    }
}


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

$return_stateArray = Array(
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN'
);


try {
	// create db object and connect to db server
	$dbh = new PDO("dblib:host=" . $server, $username, $password);

	$dbh->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

} catch (PDOException $e ) {
        echo "UNKNOWN: Failed to get DB handle: " . $e->getMessage() . "\n";
	exit(3);
}

$dbh->exec("SET ANSI_NULLS ON");
$dbh->exec("SET ANSI_WARNINGS ON");

try {
	// execute stored procedure MonitorJobs
	$query = $dbh->query("EXEC sp_MonitorJobs");
} catch (PDOException $e ) {
        echo "UNKNOWN: Failed to exec sp_MonitorJobs: " . $e->getMessage() . "\n";
	exit(3);
}

$resultSet = $query->fetchAll();

if (count($resultSet)) {
	/* Job Array
	(
	    [ServerName] => DBSERVER
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

	foreach ( $resultSet as $job ) {
		// proceed if job is not excluded
        	if ( strposa(trim($job['job_name']), $excludeList) === false ) {
			if ( $job['last_run_status'] != 'Succeeded' ) {
				$failed_jobArray[] = $job; 
			} else {
				$succeeded_jobArray[] = $job;
			}
		}
	}


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

// close stmt handler
$query = null;
// close dbhandler
$dbh = null;

echo $return_stateArray[$return_code] . ": " . $return_msg . "|'failed_jobs'=" . $failed_jobs . " 'succeeded_jobs'=". $succeeded_jobs . PHP_EOL;
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
