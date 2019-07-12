#!/usr/bin/php -q
<?php

###############################  CHANGEHISTORY ###############################
# ------- check_curl.php written by Vit Safar (CZ), v1.0, 20.10.2006 ---------
# ----------------- modified by Donald Fellow (US), v1.1, 08.06.2007 ---------
# ------------------- modified by Ryan Snyder (US), v1.2, 14.04.2011 ---------
#
# Date / Who / Version / What
#
# 06. June 2012 / Bengt Hilf (DE) / v1.0 / 
#    added proxy support, reworked old code, renamed to check_curl_http.php, 
#    reset version number
# 12. June 2012 / Bengt Hilf (DE) / v1.1 / 
#    added http status code comparison. You may now define, which http status 
#    code is OK for your website. Default is of course still 200
# 12. July 2019 / Oliver SKIBBE / v1.2
#    added curl timings ( https://curl.haxx.se/libcurl/c/curl_easy_getinfo.html )
#    as additional perf data
##############################################################################

// Changeable variables
$Debug=0;
$Timeout=45;
// --------------------

$Continue=1;
$Agent="Mozilla/5.0 (X11; U; Linux i686; cs; rv:1.8.0.7) Gecko/20060909 Firefox/1.5.0.7";
$Status=0;
$InludePerf=1;
$Msg='';
$ShowPage=0;
$HttpStatusCode=200;

$ch = curl_init();  
$Pocet=count($argv);
if ($Pocet>1){
  for ($i=1;$i<$Pocet;$i++){
    switch ($argv[$i]){
      case '-U':    
        if ($Pocet>$i+1){
          curl_setopt($ch, CURLOPT_URL, $argv[++$i]);
          if ($Debug)echo "\nDEBUG: -U ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -U: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-A':    
        if ($Pocet>$i+1){
          $Agent=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -A ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -A: missing value";
          Manual();
          exit(2);
        }
        break;
      case '-a':
      	if ($Pocet>$i+1){
          $authPhrase = $argv[++$i];
          if ($Debug)echo "\nDEBUG: -a ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -a: missing value\n";
          Manual();
          exit(2);
        }
        break;
      case '-T':    
        if ($Pocet>$i+1){
          $Timeout=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -T ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -T: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-G':    
        if ($Pocet>$i+1){
          $Grep[]=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -G ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -G: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-L':    
        $ShowPage=1;
        if ($Debug)echo "\nDEBUG: -L";
        break;

      case '-F':    
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, 1);
        if ($Debug)echo "\nDEBUG: -F";
        break;

      case '-X':    
        $InludePerf=0;
        if ($Debug)echo "\nDEBUG: -X";
        break;

      case '-I':    
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST,  0);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER,  0);
        if ($Debug)echo "\nDEBUG: -I";
        break;

      case '-Tc':    
        if ($Pocet>$i+1){
          $Tc=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -Tc ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Tc: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-Tw':    
        if ($Pocet>$i+1){
          $Tw=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -Tw ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Tw: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-Sbc':    
        if ($Pocet>$i+1){
          $Sbc=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -Sbc ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Sbc: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-Sbw':    
        if ($Pocet>$i+1){
          $Sbw=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -Sbw ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Sbw: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-Soc':    
        if ($Pocet>$i+1){
          $Soc=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -Soc ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Soc: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-Sow':    
        if ($Pocet>$i+1){
          $Sow=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -Sow ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Sow: missing value";
          Manual();
          exit(2);
        }
        break;

      case '-S':    
        if ($Pocet>$i+2){
          $String1=$argv[++$i];
          $String2=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -S ".$String1.' '.$String2;
        }else{
          echo "ERROR in parsing argument -S: missing values";
          Manual();
          exit(2);
        }
        break;
      case '-v':
	$verbose = 1;
	break;		
      case '-O':    
        $UseOutput=1;
        if ($Debug)echo "\nDEBUG: -O";
        break;

      case '-P':    
        if ($Pocet>$i+1){
          $proxy = explode(":",$argv[++$i]);
          curl_setopt($ch, CURLOPT_PROXY, $proxy[0]);
          if ( isset($proxy[1]) ) {
            curl_setopt($ch, CURLOPT_PROXYPORT, $proxy[1]);
          }
          if ($Debug)echo "\nDEBUG: -P ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -P: missing value";
          Manual();
          exit(2);
        }
        break;
      case '-Pu':    
        if ($Pocet>$i+1){
          curl_setopt($ch, CURLOPT_PROXYUSERPWD, $argv[++$i]);
          if ($Debug)echo "\nDEBUG: -Pu ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Pu: missing value";
          Manual();
          exit(2);
        }
        break;
      case '-Pa':    
        if ($Pocet>$i+1){
          curl_setopt($ch, CURLOPT_PROXYAUTH, $argv[++$i]);
          if ($Debug)echo "\nDEBUG: -Pa ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Pa: missing value";
          Manual();
          exit(2);
        }
        break;
      case '-Pt':    
        if ($Pocet>$i+1){
          curl_setopt($ch, CURLOPT_PROXYTYPE, $argv[++$i]);
          if ($Debug)echo "\nDEBUG: -Pt ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -Pt: missing value";
          Manual();
          exit(2);
        }
        break;
      
      case '-C':    
        if ($Pocet>$i+1){
          $HttpStatusCode=$argv[++$i];
          if ($Debug)echo "\nDEBUG: -C ".$argv[$i];
        }else{
          echo "ERROR in parsing argument -C: missing value";
          Manual();
          exit(2);
        }
        break;

      case '--help':
      case '-h':
        Manual();
        exit(2);
        break; 

      default:
        echo "ERROR in argument parsing: ".$argv[$i];
        Manual();
        exit(2);
        break;
    }
  }
  curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
  curl_setopt($ch, CURLOPT_HEADER, 0);
  curl_setopt($ch, CURLOPT_USERAGENT, $Agent );
  curl_setopt($ch, CURLOPT_TIMEOUT, $Timeout);  
  if(isset($verbose)) {
	curl_setopt($ch, CURLOPT_VERBOSE, true);
	$verbose = fopen('php://temp', 'w+');
	curl_setopt($ch, CURLOPT_STDERR, $verbose);
  }
  if(isset($authPhrase)){
  	curl_setopt($ch, CURLOPT_USERPWD, $authPhrase);
  	curl_setopt($ch,CURLOPT_HTTPAUTH, CURLAUTH_ANY);
  }
  
  if (isset($Tc) and isset($Tw) and  ($Tw >= $Tc) ){
    echo "ERROR in arguments Tw ($Tw) >= Tc ($Tc) !!!";
    Manual();
    exit(2);
  } 
  if (isset($Sbc) and isset($Sbw) and  ($Sbw >= $Sbc) ){
    echo "ERROR in arguments Sbw ($Sbw) >= Sbc ($Sbc) !!!";
    Manual();
    exit(2);
  } 
  if (isset($Soc) and isset($Sow) and  ($Sow >= $Soc) ){
    echo "ERROR in arguments Sbw ($Sow) >= Sbc ($Soc) !!!";
    Manual();
    exit(2);
  } 

  // EXEC    
  $time_start = getmicrotime();
  $Buff=@curl_exec($ch);
  $Time = round(getmicrotime() - $time_start,3);
  $Size=strlen($Buff);
  $errnum=curl_errno($ch);
  if ( $errnum && ! strpos(curl_error($ch), "Received HTTP code 403 from proxy after CONNECT") == FALSE ) {
    if ($errnum==28){
      echo 'Timeout '.$Timeout.'sec exceeded.';
      exit(2);
    }else{
      echo "ERROR $errnum in opening page! Err:".curl_error($ch);
      exit(2);
    }
  }
  $reqInfo = curl_getinfo($ch);

  @curl_close($ch);
  
  //var_dump($reqInfo['http_code']);
  if ( $Debug) print_r($reqInfo);

  if (isset($Sbc) and ($Size > $Sbc)){
    $Status=2;
    $Msg.='Size '.$Size.'B below limit '.$Sbc.'B';
  }elseif (isset($Sbw) and ($Size > $Sbw)){
    $Status=1;
    $Msg.='Size '.$Size.'B below limit '.$Sbw.'B';
  }

  if (isset($Soc) and ($Size < $Soc)){
    $Status=2;
    $Msg.='Size '.$Size.'B over limit '.$Soc.'B';
  }elseif (isset($Sow) and ($Size < $Sow)){
    $Status=1;
    $Msg.='Size '.$Size.'B over limit '.$Sow.'B';
  }

  if (isset($Tc) and ($Time > $Tc)){
    $Status=2;
    $Msg.='Download time '.$Time.'sec exceeded time limit '.$Tc.'sec';
  }elseif (isset($Tw) and ($Time > $Tw)){
    $Status=1;
    $Msg.='Download time '.$Time.'sec exceeded time limit '.$Tw.'sec';
  }

  if($Status == 0 && $reqInfo['http_code'] != $HttpStatusCode){
  	$Status=2;
  	$Msg.="ERROR: Page returned unexpected HTTP status code ".$reqInfo['http_code'].". Expected was ".$HttpStatusCode;
  }
  
  

  if ($Status == 0 && isset($Grep)){
  	for($i=0; $i<sizeof($Grep); $i++){
		if (!strstr($Buff,$Grep[$i])){
		  $Status=2;
		  $Msg.='String '.$Grep[$i].' not found!';
		  break;
		}
	}
  }

  if (isset($String1) or isset($String2)){
    if (isset($String1) and isset($String2)){
      echo "\n".$String1."\n".$String2."\n";
      $First=strpos($Buff,$String1);
      if ($First){
        $Last=strpos($Buff,$String2,($First+strlen($String1)));
        if ($Last){
          echo $First.'-'.$Last.' - '.substr($Buff,($First+strlen($String1)),($Last-$First-strlen($String1)) );
        }else{
          echo "ERROR in arguments -S. Second string ".$String2.' not found!!!';
          Manual();
          exit(2);
        }
      }else{
        echo "ERROR in arguments -S. First string ".$String1.' not found!!!';
        Manual();
        exit(2);
      }
    }else{
      echo "ERROR in arguments -S. Must be two strings! Before and after.";
      Manual();
      exit(2);
    }
  }

  if (isset($UseOutput)){
  	$StatusHeader = "Status:";
	$StatusSeperator = "-";
	$First=strpos($Buff,$StatusHeader);
	$Last=strpos($Buff,$StatusSeperator,($First+strlen($StatusHeader)));
	$OutputStatus = trim(substr($Buff,($First+strlen($StatusHeader)),($Last-$First-strlen($StatusHeader)) ) );
    if ( strtoupper($OutputStatus) == "CRITICAL" ) {
		$Status=2;
    	$Msg.=substr($Buff,$First+8);
  	} elseif ( strtoupper($OutputStatus) == "WARNING" ){
    	$Status=1;
    	$Msg.=substr($Buff,$First+8);
		$Status=0;
    	$Msg.=substr($Buff,$First+8);
	}
  }



  if (empty($Msg))$Msg='Page OK: HTTP Status Code '.$reqInfo['http_code'].' - '.$reqInfo['size_download'].' bytes in '.$reqInfo['total_time'].' seconds';
  if ($InludePerf) {
    // appconnect_time doesn't exist prior php 5.5, so we have to calculate it manually
    $perf_ssl_offload_time = $reqInfo['pretransfer_time'] - $reqInfo['connect_time']; 
    $perf_server_process_time = $reqInfo['total_time'] - $reqInfo['starttransfer_time']; 
    $Msg.= " |time=" . round($reqInfo['total_time'],3) . "s size=" . round($reqInfo['size_download'], 3) . "B namelookup_time=" . round($reqInfo['namelookup_time'], 3) . "s";
    $Msg.= " connect_time=" . round($reqInfo['connect_time'], 3) . "s pretransfer_time=" . round($reqInfo['pretransfer_time'], 3) . "s redirect_time=" . round($reqInfo['redirect_time'], 3) . "s";
    $Msg.= " starttransfer_time=" . round($reqInfo['starttransfer_time'], 3) . "s appconnect_time=" . round($perf_ssl_offload_time, 3) . "s server_proc_time=" . round($perf_server_process_time,3 ) . "s";
  }
  echo $Msg . PHP_EOL;
  if ($ShowPage)echo "\n\n----------------------------- Page content ----------------------------\n\n".$Buff;
  if (isset($verbose)) {
    echo "Verbose: ";
    rewind($verbose);
    echo stream_get_contents($verbose);
  } 
  exit($Status);
    
}else{
  Manual();
}

function getmicrotime(){ 
  list($usec, $sec) = explode(" ",microtime()); 
  return ((float)$usec + (float)$sec); 
} 

function Manual(){
echo "
--------- check_curl_http.php v1.0, 06.06.2012 ---------
\n
 Syntax:
    -U URL
    -A Agent (default: Mozilla/5.0 ... )
    -a authentication [user]:[password]
    -G Grep page on STRING (can be set multiple times for searching different strings)
    -L Show page 
    -F Follow redirects 
    -I Ignore SSL certificate errors 
    -X Exclude performance data (default: include)
    -Tc Ccritical page return time (seconds)
    -Tw Warning page return time (seconds)
    -Sbc Critical page size below SIZE (bytes)
    -Soc Critical page size over SIZE (bytes)
    -Sbw Warning page size below SIZE (bytes)
    -Sow Warning page size over SIZE (bytes)
    -S Find string between ARG1 and ARG2, return first match (s s) (example: value=\" \" )
    -T Timeout (seconds)(default: 10sec)
    -O Output Driven Check - Page Should respond with \"Status: OK\" or otherwise
    -P HTTP proxy to tunnel request through [proxyname]:[port]
    -Pu Authentication credentials for proxy [username]:[password]
    -Pa Authentication method used for proxy connection. Either CURLAUTH_BASIC or CURLAUTH_NTLM
    -Pt Either CURLPROXY_HTTP (default) or CURLPROXY_SOCKS5
    -C Specify OK http status code. By default, this is 200
\n\n Examples:
  check_curl_http.php -U http://test.example.net
  check_curl_http.php -U https://test.example.net -P myproxy.company.com:8080 -Pu proxyuser:password -F -G somesearchstring\n\n";
}
?>

