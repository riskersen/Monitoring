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

$dateFormatArray = Array (
		'de' => 104,
		'us' => 110,
		'it' => 105,
		'uk' => 103,
		'fr' => 103,
		'jp' => 111
);

// args
$options = getopt("H:U:P:D:e:w:c:x:y:d:h");
if ( isset($options['h']) ) {
        help();
}

// host and pw are mandatory
if ( !isset($options['H']) || !isset($options['U']) ) {
	echo "!Username or Hostname missing!" . PHP_EOL;
	help();
}

// map options to variables
$excludeWhereList = ( isset($options['e']) ? explode(",", $options['e']) : Array("''"));
$warn 		= ( isset($options['w'])  ? $options['w'] : 85);
$crit		= ( isset($options['c'])  ? $options['c'] : 95);

$expiryWarn	= ( isset($options['x'])  ? $options['x'] : 90);
$expiryCrit	= ( isset($options['y'])  ? $options['y'] : 30);

$dateStyle	= ( isset($options['d']) ? $options['d'] : 'de');

$myServer 	= $options['H'];
$myUser   	= $options['U'];
$myPass   	= ( isset($options['P']) ? $options['P'] : '');
$myDB     	= ( isset($options['D']) ) ? $options['D'] : 'safeguard';

// helper 
$exitCode = 0;
$exitString = "OK: "; 
$outArray = Array( 
	0 => 'OK',
	1 => 'W', 
	2 => 'C', 
	3 => 'U'
);

$outString  = "";
$perfString = "|";

// Datenbankkonnektivität
try {
	// datenbankverbindung aufbauen
	$dbh = new PDO("dblib:host=$myServer;dbname=$myDB", $myUser, $myPass);

	$dbh->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e ) {
        echo "UNKNOWN: failed to get DB handle: " . $e->getMessage() . PHP_EOL;
	exit(3);
} // end db connect

// build query string
$query = "
SELECT 
	( COUNT(*) * 100) / LIC.LIC_SOFT_LIMIT AS lic_usage_percent,
	COUNT(*) 		AS lic_usage,
	IIF.IIF_FEATURE 	AS feature_name,
	LIC.LIC_FEATURE_NAME 	AS lic_feature_name,
	LIC.LIC_SOFT_LIMIT 	AS lic_soft_limit,
        ISNULL(
			DATEDIFF(day, GETDATE(), LIC.LIC_EXPIRY_DATE),
			999
		) AS lic_expiry_days,
        ISNULL(
			CONVERT(nVarChar(30), LIC.LIC_EXPIRY_DATE, " . $dateFormatArray[$dateStyle] . "),
			'never'
		) AS lic_expiry_date
FROM 
	IVT_INST_FEATURES IIF
LEFT JOIN
	LICENCES LIC
		ON LIC.LIC_FEATURE = IIF.IIF_FEATURE
WHERE
	LIC.LIC_FEATURE_NAME NOT IN ('" . implode("','", $excludeWhereList) . "')
GROUP BY 
	IIF.IIF_FEATURE, LIC.LIC_SOFT_LIMIT, LIC.LIC_FEATURE_NAME, LIC.LIC_EXPIRY_DATE
";

try {
	// prepare + execute db query
        $sth = $dbh->prepare($query);
        $sth->execute();

        $result = $sth->fetchAll();
} catch ( PDOException $e ) {
        echo "UNKNOWN: query execution failed: " . $e->getMessage() . PHP_EOL;
	exit(3);
} // end db

$resultCount = count($result);

if ( $resultCount > 0 ) {
	foreach ( $result as $line ) {


		// license usage
		if ( $line['lic_usage_percent'] >= $crit || $line['lic_expiry_days'] <= $expiryCrit) {
			// critical > all
			$exitCode = 2;
			$tempCode = 2;
		} else if ( $line['lic_usage_percent'] >= $warn || $line['lic_expiry_days'] <= $expiryWarn ) {
			// raise exit code if below warning
		       	$exitCode = ( $exitCode == 0 ) ? 1 : $exitCode;
			$tempCode = 1;
		} else {
			$tempCode = 0;
		} // end if percentage
		// calculate perfdata values, round float values
		$warn_count = round( ( $line['lic_soft_limit'] * ( 100 - $warn ) )/100, 0, PHP_ROUND_HALF_UP);
		$crit_count = round( ( $line['lic_soft_limit'] * ( 100 - $warn ) )/100, 0, PHP_ROUND_HALF_UP);
		
		// build output string
		$outString  .= " " . $outArray[$tempCode] . "->" . $line['lic_feature_name'] . ": " . $line['lic_usage_percent'] . "% (" . $line['lic_usage'] . "/" . $line['lic_soft_limit'] . " Lic, Expires: " . $line['lic_expiry_date'] . ")";
	
		// build perfdata string, percentage and plain count
		$perfString .= " '" . $line['feature_name'] . "_pct'=" . $line['lic_usage_percent'] . "%;" . $warn . ";" . $crit; 
		$perfString .= " '" . $line['feature_name'] . "'=" . $line['lic_usage'] . ";" . $warn_count . ";" . $crit_count . ";0;" . $line['lic_soft_limit']; 
	} // end foreach db result
}

// nested short if is not working at php :-(
switch ( $exitCode ) {
	case 2 : 
		$exitString = "CRITICAL:";
		break;
	case 1 : 
		$exitString = "WARNING:";
		break;
	default:
		$exitString = "OK: " . ( $resultCount > 0  ? "everythings fine:" : "no licences found" );
		break;
} // end switch exit string 

echo $exitString . $outString . $perfString . PHP_EOL;
// return values
exit($exitCode);

function help() {

	global $dateFormatArray;

        echo "checks configured safeguard enterprise sql server for license usage
\t-H\thostname of db server e.g. 'sgn1'
\t-U\tusername e.g. 'domain\dbsnmp'
\t-P\tpassword e.g. '123foobar'
\t-D\tdatabase e.g. 'safeguard' -> defaults to safeguard
\t-w\twarning (in %) e.g. 75 -> defaults to 85
\t-c\tcritical (in %) e.g. 95 -> defaults to 95
\t-y\tcritical expiry days -> defaults to 30
\t-x\twarning expiry days -> defaults to 90
\t-d\toutput date style -> defaults to de, supported: " . implode(", ", array_keys($dateFormatArray)) . "
\t-e\texclude e.g. 'Data Exchange' -> for more values, use a comma separated list ('x,y,z')
\t-h\tprints this text
";

        exit(3);
}
// EOF 
