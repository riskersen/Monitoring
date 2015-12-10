#!/bin/bash
function report_state {
        if [ $REPORT_NAGIOS -gt 0 ] ; then
                # nsca stuff
                echo -e "$NAGIOS_HOSTNAME\t$3\t$1\t$2\n" | $NSCA_BIN -H $NSCA_HOST -c $NSCA_CFG
        else
                echo $2
        fi
}

# sql binaries
SQLITE=$(which sqlite3)

DBFILE=$1
# db name (default to main)
db=$2

# options
LOGFILE=/tmp/sqlite_backup.log
BACKUP_DIR=/mnt/sql-backup

# Nagios stuff
# report to nsca 
REPORT_NAGIOS=${3:-0} # expects value 1 or 0

NSCA_HOST=192.168.1.1
NSCA_CFG=/etc/send_nsca.cfg
NSCA_BIN=/usr/lib/nagios/plugins/send_nsca
NAGIOS_HOSTNAME=`hostname -s`

# helper
date=$(date +%F)
hostname=$(hostname -s)
EXIT_CODE=0
retCode=0

# redirect output
exec > $LOGFILE 2>&1

# backup folder must be in fstab
# backup folder must be in fstab
[[ ! -d $BACKUP_DIR ]] && mkdir -p $BACKUP_DIR


if [ $BACKUP_IS_MOUNT = true ] ; then
        $MOUNTPOINT -q $BACKUP_DIR
        if [ $? -gt 0 ] ; then
                mount $BACKUP_DIR
                $MOUNTPOINT -q $BACKUP_DIR
                if [ $? -gt 0 ] ; then
                        report_state 2 "CRITICAL: $date mount failed: MySQL Backup dir $BACKUP_DIR|'runtime'=0s" "MySQL-Backup database $db"
                        exit 1
                fi
        fi
fi



[[ ! -d $BACKUP_DIR/${hostname^^} ]] && mkdir -p $BACKUP_DIR/${hostname^^}
cp $DBFILE $BACKUP_DIR/${hostname^^}/${db}_sqlite.db
	
starttime=`date +%s`
$SQLITE $DBFILE .dump | gzip > $BACKUP_DIR/${hostname^^}/${db}_${date}.sql.gz
retCode=$?
duration=$((`date +%s`-$starttime))
if [ $retCode -gt 0 ] ; then
        EXIT_CODE=2
        report_state 2 "CRITICAL: $date SQLite Backup '$db' Fehler aufgetreten, bitte Log pruefen, Laufzeit: $duration seconds|'runtime'=${duration}s" "SQLite-Backup database $db"
else
        report_state 0 "OK: $date SQLite Backup '$db' erfolgreich, Laufzeit $duration seconds|'runtime'=${duration}s" "SQLite-Backup database $db"
fi

umount $BACKUP_DIR

exit $EXIT_CODE
