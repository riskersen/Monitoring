#!/bin/bash
# Author: oliver.skibbe (at) mdkn.de
# Date: 2015-03-17
# Purpose: return warning or critical if file count of specified path is higher then limits
# Also checks if a path is a mounted path
# Changelog:
# 		- improved code
#		- now supports include/exclude
#		- updated usage
#		- multiline output for found files (limited to 150)

PROGNAME=`basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
. $PROGPATH/utils.sh

#path=$1
#warning=$2
#critical=$3

function usage () {
	echo -e "`basename $0`: checks given path for file count
Usage: `basename $0` -p path -w warning -c critical -d max-depth -f filelist [-e|-m 1]
-w\twarning count
-c\tcritical count
-p\tpath to monitor
-m\tflag if path is a mounted path
-f\tpipe separated list of files includes or excludes
-e\texclude/include list of files flag
-d\tmax-depth, how deep to dive into folders
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

while getopts ":m:p:w:c:d:f:e:" opt; do
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
	\?)
		echo "Option -$OPTARG is invalid!"
		usage
		;;
	:)
		echo "Option -$OPTARG requires an argument"
		usage
	esac
done

if [ ! -d $path ] ; then
	echo "Path $path does not exist!"
	usage
fi

if [ $mountedpath ] ; then
	# filter mount point
	basepath=`df "$path" | tail -1 | awk '{ print $6 }'`
	mountpoint -q $basepath
	if [ $? -gt 0 ] ; then
		echo "Path $basepath is not mounted correctly"
		usage
	fi
fi

if [ $warning -gt $critical ] ; then
	echo "Warning is greater than critical"
	usage
fi

# find all files
oldestFiles=`find $path -maxdepth $maxdepth -type f -printf '%T@ %p\n' | grep -E -i $grepOpt "$filelist" | sort -k 1n`

# get file count, quotes are important at this time
filecount=`echo "$oldestFiles" | wc -l`

# get oldest file
oldestFile=`echo "$oldestFiles" | head -n 1`

# double awk because newer bashs append micro seconds 
oldestFileDate=`echo $oldestFile | awk '{print $1}' | awk -F "." '{print $1}'`
currentDate=`date +%s`

# calculate time
oldestFile=`echo $oldestFile | awk '{print $2}' `
oldestFileTime=$(($currentDate - $oldestFileDate))

if [ $filecount -gt $critical ] ; then
	returnString="CRITICAL"
	returnState=$STATE_CRITICAL
elif [ $filecount -gt $warning ] ; then
	returnString="WARNING"
	returnState=$STATE_WARNING
else
	returnString="OK"
	returnState=$STATE_OK
fi

convertTime $oldestFileTime
echo -e "$returnString: file count is $filecount, oldest file \"`basename $oldestFile`\" is $oldestFileTime old\n$oldestFiles|filecount=$filecount;$warning;$critical"
exit $returnState

