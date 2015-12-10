#!/bin/bash
function report_state {
        if [ $REPORT_NAGIOS -gt 0 ] ; then
                # nsca stuff
                echo -e "$NAGIOS_HOSTNAME\t$3\t$1\t$2\n" | $NSCA_BIN -H $NSCA_HOST -c $NSCA_CFG
        else
                echo $2
        fi
}


# mysql options
MYSQL_USER=""
MYSQL_PASS=""
MYSQL_OPTS="--skip-pager --skip-column-names --raw"
MYSQLDUMP_OPTS="--routines --events --add-drop-table --quote-names --complete-insert --max_allowed_packet=512M"
MYSQLCHECK_OPTS="--all-databases  --auto-repair --optimize"

# Options
LOGFILE=/tmp/mysql_backup_$hostname.log

# Mount dir
BACKUP_IS_MOUNT=true

# Nagios stuff
# report to nsca 
REPORT_NAGIOS=${3:-0} # expects value 1 or 0

NSCA_HOST=192.168.1.1
NSCA_CFG=/etc/send_nsca.cfg
NSCA_BIN=/usr/lib/nagios/plugins/send_nsca
NAGIOS_HOSTNAME=${1:nagios}

# helper
date=$(date +%F)
hostname=${2:$(hostname -s)}
EXIT_CODE=0
retCode=0

# binaries
MYSQL=$(which mysql)
MYSQLCHECK=$(which mysqlcheck)
MYSQLDUMP=$(which mysqldump)
MOUNTPOINT=$(which $MOUNTPOINT)

# redirect output to logfile
exec > $LOGFILE 2>&1

# backup folder must be in fstab
backup_dir=/mnt/sql-backup
[[ ! -d $backup_dir ]] && mkdir -p $backup_dir


if [ $BACKUP_IS_MOUNT = true ] ; then
	$MOUNTPOINT -q $backup_dir
	if [ $? -gt 0 ] ; then
		mount $backup_dir
		$MOUNTPOINT -q $backup_dir
		if [ $? -gt 0 ] ; then
			report_state 2 "CRITICAL: $date mount failed: MySQL Backup dir $backup_dir|'runtime'=0s" "MySQL-Backup database $db"
			exit 1
		fi
	fi
fi

# prepare db
$MYSQLCHECK -h$hostname -u$MYSQL_USER -p$MYSQL_PASS $MYSQLCHECK_OPTS

# get db list
db_list=$($MYSQL $MYSQL_OPTS -h$hostname -u$MYSQL_USER -p$MYSQL_PASS -e 'show databases;' | awk '{print $c}' c=${1:-1})

[[ ! -d $backup_dir/${hostname^^} ]] && mkdir -p $backup_dir/${hostname^^}
for db in ${db_list[@]} ; do
	starttime=`date +%s`
	$MYSQLDUMP -h$hostname -u$MYSQL_USER -p$MYSQL_PASS $MYSQLDUMP_OPTS $db | gzip > $backup_dir/${hostname^^}/${db}_${date}.sql.gz
	retCode=$?
	duration=$((`date +%s`-$starttime))
	if [ $retCode -gt 0 ] ; then
	        EXIT_CODE=2
	        report_state 2 "CRITICAL: $date MySQL Backup '$db' Fehler aufgetreten, bitte Log pruefen, Laufzeit: $duration seconds|'runtime'=${duration}s" "MySQL-Backup database $db"
	else
	        report_state 0 "OK: $date MySQL Backup '$db' erfolgreich, Laufzeit $duration seconds|'runtime'=${duration}s" "MySQL-Backup database $db"
	fi
done

umount $backup_dir

exit $EXIT_CODE
