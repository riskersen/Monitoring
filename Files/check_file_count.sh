#!/bin/bash
# Author: oliskibbe (at) gmail.com
# Date: 2015-11-26
# Purpose: return warning or critical if file count of specified path is higher then limits
# Also checks if a path is a mounted path
# Changelog:
#		2016-08-31 - arigaud.prosodie.cap (at) free.fr
#		- added file age check
#		- check if mountpoint command exists before execute
#		- added set -au option
#		2015-11-26
#		- fixed check for count if alert should be for 1 file
#		- prettified output of timestamps, more human readable
#		- Multiline Output in CSV style
#		Older:
#		- reformated code
# 
# 		- improved code
#		- now supports include/exclude
#		- updated usage
#		- multiline output for found files (limited to 150)
set -au

PROGNAME=$(basename $0)
PROGPATH=$(echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,')
. $PROGPATH/utils.sh

function usage () {
	echo -e "$PROGNAME: checks given path for file count
Usage: $PROGNAME -p path -w warning -c critical -d max-depth -f filelist [-e|-m 1]
-w\twarning count
-c\tcritical count
-p\tpath to monitor
-m\tflag if path is a mounted path
-f\tpipe separated list of files includes or excludes
-e\texclude/include list of files flag
-d\tmax-depth, how deep to dive into folders
-a\tmax-age, max file age
	"
	exit 3
}

function convertTime () {
	num=$1
	min=0
	hour=0
	day=0
	if((num > 59)) ; then
		((sec=num%60))
        	((num=num/60))
	        if((num > 59)); then
        	    ((min=num%60))
	            ((num=num/60))
        	    if((num > 23));then
	                ((hour=num%24))
                	((day=num/24))
		    else
                	((hour=num))
        	    fi
	        else
            		((min=num))
        	fi
	else
        	((sec=num))
	fi
	oldestFileTime="{$day}d {$hour}h {$min}m {$sec}s"
}

# set variables to avoid unbound message
mountedpath=""
warning=""
critical=""
maxfileage=0
grepOpt=""
filelist=""

while getopts ":m:p:w:c:d:f:e:a:" opt; do
	case $opt in
	p)
		path=$OPTARG
		;;
	w)
		warning=$OPTARG
		;;
	c)
		critical=$OPTARG
		;;
	m)
		mountedpath=true
		;;
	e)
		grepOpt="-v"
		;;
	d)
		maxdepth=$OPTARG
		;;
	f)
		filelist=$OPTARG
		;;
	a)
		maxfileage=$OPTARG
		;;
	\?)
		echo "Option -$OPTARG is invalid!"
		usage
		;;
	:)
		echo "Option -$OPTARG requires an argument"
		usage
	esac
done

if [ ! -d "$path" ] ; then
	echo "Path $path does not exist!"
	usage
fi

if [ $mountedpath ] ; then
	mountpoint=`which mountpoint 2>&1`
	if [ $? -eq 0 ] ; then
		# filter mount point
		basepath=$(df "$path" | tail -1 | awk '{ print $6 }')
		$mountpoint -q "$basepath"
		if [ $? -gt 0 ] ; then
			echo "Path $basepath is not mounted correctly"
			usage
		fi
	else
		echo "$mountpoint"
		usage
	fi
fi

if [ -z "$warning" -o -z "$critical" ] ; then
        echo "Warning or Critical value is empty"
        usage
fi

if [ $warning -gt $critical ] ; then
	echo "Warning is greater then critical"
	usage
fi

# find all files
oldestFiles=$(find "$path" -maxdepth $maxdepth -type f -mmin +$maxfileage -printf '%TY-%Tm-%Td %TH:%TM;%p\n' | grep -E -i $grepOpt "$filelist" | sort -k 1n)

# get file count
filecount=$(echo "$oldestFiles" | grep -v '^$' | wc -l)

if [ $filecount -ge 1 ] ; then
	# get oldest file
	oldestFile=$(echo "$oldestFiles" | head -n 1 | awk -F';' '{print $2}')

	# double awk because newer bashs append micro seconds 
	oldestFileDate=$(find "$oldestFile" -type f -printf '%T@' | awk -F "." '{print $1}')

	# calculate time (unix timestamps)
	oldestFileTime=$(($(date +%s) - $oldestFileDate))

	# unix timestamps to human readable
	convertTime $oldestFileTime
	returnString=", oldest file \"$(basename $oldestFile)\" is $oldestFileTime old\n$oldestFiles"
else
	returnString=""
fi


if [ $filecount -ge $critical ] ; then
	stateString="CRITICAL"
	returnState=$STATE_CRITICAL
elif [ $filecount -ge $warning ] ; then
	stateString="WARNING"
	returnState=$STATE_WARNING
else
	stateString="OK"
	returnState=$STATE_OK
fi
perfString="filecount=$filecount;$warning;$critical"

echo -e "$stateString: file count is ${filecount}${returnString}|$perfString"
exit $returnState

