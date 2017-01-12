SSH Firewall
==========

This script protects SSH remote command execution, often used by Monitoring system, like Nagios or Icinga.

The protection is been done by checking for the path of the to be called command, so all commands need to be called by their full path

Per default "/usr/local/bin" is allowed, but can be changed by adjusting value of $allowed_path

Such user can be created by:
$ adduser nagiosclient
$ mkdir -p /home/nagiosclient/.ssh
$ chown -R nagiosclient:nagiosclient /home/nagiosclient/
$ chmod 700 /home/nagiosclient/.ssh
$ touch /home/nagiosclient/.ssh/authorized_keys
$ chmod 600 /home/nagiosclient/.ssh/authorized_keys

## Configuration
###SSH
add command="path/ssh_firewall.pl" to authorized_keys file:
command="/usr/local/bin/ssh_firewall.pl" ssh-rsa foobar4223dieoffenbarung

###Local shell
adjust shell of user and set it to "path/ssh_firewall.pl"
