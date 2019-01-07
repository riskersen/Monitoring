#!/usr/bin/perl -w
#
# This script protects ssh remote command exection
# Basically, it will check if desired script is in 
# allowed path
# This script shall be configured as ssh users shell
#
# Author: Oliver Skibbe (oliskibbe (at) gmail.com)
# Date: 2019-01-07
#
# Changelog:
# Release 1.0 (2017-01-11)
# - initial release
# Release 1.1 (2017-01-12)
# - moved to SSH_ORIGINAL_COMMAND
# Release 1.2 (2019-01-07)
# - added file exists check

use strict;
use File::Basename;

# check if atleast 1 arg is given
if ( ! length $ENV{SSH_ORIGINAL_COMMAND} > 0 ) {
  print "UNKNOWN: not enough args\n";
  exit(3);
}

# vars
my $allowed_path = "/usr/local/bin";

# helper
my $script_name = undef;

# prepare array of command string
my @ssh_command = split(" ", $ENV{SSH_ORIGINAL_COMMAND});

# extract script name and check if path is allowed 
# but no output of the actual allowed path because of security reason
$script_name = $ssh_command[0];
if ( dirname($script_name) ne $allowed_path ) {
  print "UNKNOWN: accessed path is protected!";
  exit(3);
}

# check if script exists
if ( ! -e $script_name ) {
  print "UNKNOWN: file does not exist!";
  exit(3);
}

# execute script
my ($exit_code, $output) = ExecCmd(join(" ", @ssh_command), 0);

# remove trailing new line
chomp($output->[0]);

print "Output: " . $output->[0] . "\n";
exit($exit_code);

### SUBS

# two parameters:
#  cmd     - a command or reference to an array of command + arguments
#  timeout - number of seconds to wait (0 = forever)

# returns:
#  cmd exit status (-1 if timed out)
#  cmd results (STDERR and STDOUT merged into an array ref)

sub ExecCmd {
  my $cmd = shift || return(0, []);
  my $timeout = shift || 0;

  # opening a pipe creates a forked process    
  my $pid = open(my $pipe, '-|');
  return(-1, "Can't fork: $!") unless defined $pid;

  if ($pid) {
    # this code is running in the parent process

    my @result = ();

    if ($timeout) {
      my $failed = 1;
      eval {
        # set a signal to die if the timeout is reached
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        @result = <$pipe>;
        alarm 0;
        $failed = 0;
      };
      return(-1, ['command timeout', @result]) if $failed;
    }
    else {
      @result = <$pipe>;
    }
    close($pipe);

    # return exit status, command output
    return ($? >> 8), \@result;
  }

  # this code is running in the forked child process

  { # skip warnings in this block
    no warnings;

    # redirect STDERR to STDOUT
    open(STDERR, '>&STDOUT');

    # exec transfers control of the process
    # to the command
    ref($cmd) eq 'ARRAY' ? exec(@$cmd) : exec($cmd);
  }

  # this code will not execute unless exec fails!
  print "Can't exec @$cmd: $!";
  exit 1;
}
