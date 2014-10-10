#!/usr/bin/perl -w
#
# Nagios overnight/daily/weekly/monthly reporter
#
# Fetches Nagios report from web, processes HTML/CSS and emails to someone
# Written by Rob Moss, 2005-07-26, coding@mossko.com
# Modified by Oliver Skibbe, 2014-10-10, oliskibbe@gmail.com
#
# Use at your own risk, knoweledge of perl required.
#
# TODO
#   - reduce subs 
#
# Version 1.4 - Oliver Skibbe
#   - refactored code (according to perlcritics)
#   - moved from Date::Manip to more common DateTime module (libdatetime-perl at ubuntu/debian)
#   - added locale support and german textsa
#   - added command line switch for locale
# Version 1.3.1
#   - Overnight, Daily, Weekly, Monthly reports
#

use strict;
use warnings;

use Getopt::Long;
use Net::SMTP;
use LWP::UserAgent;
use DateTime;
use Encode qw/encode decode/; 


my $mailhost    = '';                    # Fill these in!
my $maildomain  = '';                     # Fill these in!
my $mailfrom    = 'nagios@' . $maildomain;         # Fill these in!
my $mailto      = '@' . $maildomain;    # Fill these in!
my $timeout     = 30;
my $mailsubject = '';
my $mailbody    = '';

my $locale      = 'de_DE';

my $logfile     = '/var/log/nagios3/nagios_reporter.log';  #  Where would you like your logfile to live?
my $debug       = 0;                         #  Set the debug level to 1 or higher for information

my $decode_utf8 = 1;

my $type        = '';
my $reporturl;

my $nagssbody;
my $nag_css_summary;

my $sendmail_return;

my $webuser     = 'readonly';            # Set this to a read-only nagios user (not nagiosadmin!)
my $webpass     = 'readonly';        # Set this to a read-only nagios user (not nagiosadmin!)
my $webbase     = 'http://nagios/nagios';  # Set this to the base of Nagios web page
my $webcssembed = 1;

# Donnerstag, Dezember usw
DateTime->DefaultLocale($locale);

my $date        = DateTime->today( );                # this will be manipulated

my $today_date  = DateTime->today( );                # today date
my $day_name    = $today_date->day_name();           # Dayname in German
my $repehour    = 0;                                 # Default ending hour
my $repeday     = $today_date->day();                # Ending Day
my $repemonth   = $today_date->month();              # Ending Month
my $repeyear    = $today_date->year();               # Ending Year

GetOptions (
  "debug=s"  =>  \$debug,
  "locale=s" =>  \$locale,
  "help"     =>  \&help,
  "type=s"   =>  \$type,
  "email=s"  =>  \$mailto,
  "embedcss" =>  \$webcssembed,
);

# better to use a dispatch table instead of nested ifelse chain
my %type_table = (
  'overnight' => \&report_overnight,
  'daily'     => \&report_daily,
  'weekly'    => \&report_weekly,
  'monthly'   => \&report_monthly,
  'help'      => \&help,
);

# call command
($type_table{$type} ||sub { help(); exit(1); })->();

debug(1,"reporturl: [$reporturl]");

$mailbody = http_request($reporturl);

if ($webcssembed) {
  # Stupid hacks for dodgy notes
  $nagssbody = http_request("$webbase/stylesheets/summary.css");
  $nag_css_summary = "<style type=\"text\/css\">\n";
  foreach ( split(/\n/,$nagssbody) ) {
    chomp;
    if (not defined $_ or $_ eq "" ) {
      next;
    }
    $nag_css_summary .= "<!-- $_ -->\n";
  }

  $nag_css_summary .= "</style>\n";
  $nag_css_summary .= "<base href=\"$webbase/cgi-bin/\">\n";

  $mailbody =~ s@<LINK REL=\'stylesheet\' TYPE=\'text/css\' HREF=\'/nagios/stylesheets/common.css\'>@@;
  $mailbody =~ s@<LINK REL=\'stylesheet\' TYPE=\'text/css\' HREF=\'/nagios/stylesheets/summary.css\'>@$nag_css_summary@;
}

open(FILE, ">", "/tmp/nagios-report-htmlout.html") or warn "can't open file /tmp/nagios-report-htmlout.html: $!\n";
print FILE $mailbody;
close FILE;

$sendmail_return = sendmail();

if ( $sendmail_return ne "OK" ) {
  print "ERROR: SMTP MESSAGE: " . $sendmail_return;
  exit(1);
} else {
  debug(1,"Sending mail: OK");
  exit(0);
} 

###############################################################################
sub help {
print <<'_END_';

Nagios web->email reporter program.

$0 <args>

--help
  This screen

--email=<email>
  Send to this address instead of the default address
  "$mailto"

--type=overnight  
  Overnight report, from 17h last working day to Today (9am)
--type=daily
  Daily report, 09:00 last working day to Today (9am)
--type=weekly
  Weekly report, 9am 7 days ago, until 9am today (run at 9am friday!)
--type=monthly
  Monthly report, 1st of prev month at 9am to last day of month, 9am

--embedcss
  Downloads the CSS file and embeds it into the main HTML to enable 
  Lotus Notes to work (yet another reason to hate Notes)

_END_

exit 1;

}

###############################################################################
sub report_monthly {
  # This should be run on next month e.g. 1st 
  $date->subtract( months => 1);
  $date->truncate( to => 'month');
  debug(1,"repdateprev = $date");


  my ($repsday, $repsmonth, $repsyear, $repshour ) = 0;
  my $month_name = $date->month_name();
  $repsday = $date->day();
  $repsmonth = $date->month();
  $repsyear = $date->year();
  $repshour = 0;
  
  $repeday  = $today_date->truncate( to => 'month')->day(); 
  $repehour = 0;

  $reporturl  =  "$webbase/cgi-bin/summary.cgi?report=1&displaytype=1&timeperiod=custom" .
            "&smon=$repsmonth&sday=$repsday&syear=$repsyear&shour=$repshour&smin=0&ssec=0" .
            "&emon=$repemonth&eday=$repeday&eyear=$repeyear&ehour=$repehour&emin=0&esec=0" .
            '&hostgroup=all&servicegroup=all&host=all&alerttypes=3&statetypes=2&hoststates=3&servicestates=56&limit=500';
  if ( $locale eq "de_DE" ) {
    $mailsubject = "Nagios Alarme für Monat $month_name ($repsmonth.$repsyear)";
  } else {
    $mailsubject = "Nagios alerts for month $month_name ($repsmonth/$repsyear)";
  }
  return 0;
}

###############################################################################
sub report_weekly {
  # This should be run on Friday, 5pm
  $date->truncate( to => 'week');
  debug(1,"repdateprev = $date");

  my ($repsday, $repsmonth, $repsyear, $repshour ) = 0;
  my $week_number = $date->week_number();
  $repsday = $date->day();
  $repsmonth = $date->month();
  $repsyear = $date->year();
  $repshour = 6;

  # ending hour
  $repehour = 17;

  $reporturl  =  "$webbase/cgi-bin/summary.cgi?report=1&displaytype=1&timeperiod=custom" .
            "&smon=$repsmonth&sday=$repsday&syear=$repsyear&shour=$repshour&smin=0&ssec=0" .
            "&emon=$repemonth&eday=$repeday&eyear=$repeyear&ehour=$repehour&emin=0&esec=0" .
            '&hostgroup=all&servicegroup=all&host=all&alerttypes=3&statetypes=2&hoststates=3&servicestates=56&limit=500';
  if ( $locale eq "de_DE" ) {
    $mailsubject = "Nagios Alarme für KW${week_number} ($repsday.$repsmonth.$repsyear ${repshour}:00 Uhr bis $repeday.$repemonth.$repeyear ${repehour}:00 Uhr)";
  } else {
    $mailsubject = "Nagios alerts for CW${week_number} ($repsday/$repsmonth/$repsyear ${repshour}:00h to $repeday.$repemonth.$repeyear ${repehour}:00h)";
  }

  return 0;
}

###############################################################################
sub report_daily {
  $date->subtract( days => 1 );
  debug(1,"repdateprev = $date");
  my ($repsday, $repsmonth, $repsyear, $repshour ) = 0;

  my $prev_day_name = $date->day_name();
  $repsday = $date->day();
  $repsmonth = $date->month();
  $repsyear = $date->year();
  $repshour = 6;
  # end hour
  $repehour = 6;

  $reporturl  =  "$webbase/cgi-bin/summary.cgi?report=1&displaytype=1&timeperiod=custom" .
            "&smon=$repsmonth&sday=$repsday&syear=$repsyear&shour=$repshour&smin=0&ssec=0" .
            "&emon=$repemonth&eday=$repeday&eyear=$repeyear&ehour=$repehour&emin=0&esec=0" .
            '&hostgroup=all&servicegroup=all&host=all&alerttypes=3&statetypes=2&hoststates=3&servicestates=56&limit=500';
  if ( $locale eq "de_DE" ) {
    $mailsubject = "Nagios Alarme für $prev_day_name ($repsday.$repsmonth.$repsyear) ${repshour}:00 Uhr bis $day_name ${repehour}:00 Uhr";
  } else {
    $mailsubject = "Nagios alerts of $prev_day_name ($repsday/$repsmonth/$repsyear) ${repshour}:00h to $day_name ${repehour}:00h";
  }
  return 0;
}


###############################################################################
sub report_overnight {

  # get previous day
  $date->subtract( days => 1 );
  debug(1,"repdateprev = $date");
  my ($repsday, $repsmonth, $repsyear, $repshour ) = 0;
  my $prev_day_name = $date->day_name();
  $repsday = $date->day();
  $repsmonth = $date->month();
  $repsyear = $date->year();
  $repshour = 17;

  $repehour = 6;

  $reporturl  =  "$webbase/cgi-bin/summary.cgi?report=1&displaytype=1&timeperiod=custom" .
            "&smon=$repsmonth&sday=$repsday&syear=$repsyear&shour=$repshour&smin=0&ssec=0" .
            "&emon=$repemonth&eday=$repeday&eyear=$repeyear&ehour=$repehour&emin=0&esec=0" .
            '&hostgroup=all&servicegroup=all&host=all&alerttypes=3&statetypes=2&hoststates=3&servicestates=56&limit=500';
  if ( $locale eq "de_DE" ) {
    $mailsubject = "Nagios 'über Nacht' Alarme von $prev_day_name ($repsday.$repsmonth.$repsyear) ${repshour}:00 Uhr bis $day_name ${repehour}:00 Uhr";
  } else {
    $mailsubject = "Nagios overnight alerts of $prev_day_name ($repsday/$repsmonth/$repsyear) ${repshour}:00h to $day_name ${repehour}:00h";
  }

  return 0;
}

###############################################################################
sub http_request {
  my $ua;
  my $req;
  my $res;

  my $geturl = shift;
  if (not defined $geturl or $geturl eq "") {
    warn "No URL defined for http_request\n";
    return 0;
  }
  $ua = LWP::UserAgent->new;
  $ua->agent("Nagios Report Generator " . $ua->agent);
  $req = HTTP::Request->new(GET => $geturl);
  $req->authorization_basic($webuser, $webpass);
  $req->header(  'Accept'    =>  'text/html',
      'Content_Base'    =>  $webbase,
        );

  # send request
  $res = $ua->request($req);

  # check the outcome
  if ($res->is_success) {
    debug(1,"Retreived URL successfully");
    return $res->decoded_content;
  }
  else {
    print "Error: " . $res->status_line . "\n";
    return 0;
  }
}

###############################################################################
sub debug {
  my ($lvl,$msg) = @_;
  if ( defined $debug and $lvl <= $debug ) {
    chomp($msg);
    print localtime(time) .": $msg\n";
  }
  return 1;
}

#########################################################
sub sendmail {
  my $message = "OK";
  my $smtp = Net::SMTP->new(
      $mailhost,
      Hello => $maildomain,
      Timeout => $timeout,
      Debug   => $debug,
    );

  if ( $decode_utf8 ) {
    utf8::decode($mailsubject);
    utf8::decode($mailbody);
  }

  $smtp->mail($mailfrom);
  $smtp->to($mailto);

  $smtp->data();

  ## encode mime header to support umlaut etc
  $smtp->datasend("To: " . $mailto . "\n");
  $smtp->datasend("From: " . $mailfrom . "\n");
  $smtp->datasend(encode("MIME-Header", "Subject: " . $mailsubject) . "\n");
  $smtp->datasend("MIME-Version: 1.0\n");
  $smtp->datasend("Content-type: multipart/mixed; boundary=\"boundary\"\n");
  $smtp->datasend("\n");
  $smtp->datasend("This is a multi-part message in MIME format.\n");
  $smtp->datasend("--boundary\n");
  $smtp->datasend("Content-type: text/html\n");
  $smtp->datasend("Content-Disposition: inline\n");
  $smtp->datasend("Content-Description: Nagios report\n");
  $smtp->datasend("$mailbody\n");
  $smtp->datasend("--boundary\n");
  $smtp->datasend("Content-type: text/plain\n");
  $smtp->datasend("Please read the attatchment\n");
  $smtp->datasend("--boundary--\n");
  # data end 
  $smtp->dataend();

  if ( ! $smtp->ok() ) {
    $message = $smtp->message(); 
  }
  $smtp->quit;

  return $message;
}



