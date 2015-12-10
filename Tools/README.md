Nagios Email Reporter
==========

Example:
0 6 * * 0-6 /usr/local/bin/nagios-reporter.pl --email=foobar@example.org --type=overnight >/dev/null 2>&1

MySQL Backup
==========
Example:
0 21 * * * /usr/local/bin/mysql_backup.sh $NAGIOS_HOSTNAME$ $dnsname$ 1

SQLite Backup
==========
Example:
0 20 * * * /usr/local/bin/sqlite_backup.sh /var/lib/application/sqlite.db dbfilename 1

