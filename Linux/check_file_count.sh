#!/bin/bash
# Author: oliver.skibbe (at) mdkn.de
# Date: 2013-10-30
# Purpose: return warning or critical if file count of specified path is higher then limits
# Also checks if a path is a mounted path

PROGNAME=`basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
. $PROGPATH/utils.sh

#path=$1
#warning=$2
#critical=$3

function usage () {
	echo "`basename $0`: checks given path for file count
Usage: `basename $0` -p path -w warning -c critical -m 1
-m => flag if path is a mounted path
	"
	exit 1
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

while getopts ":m:p:w:c:" opt; do
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
	mount $path
	mountpoint -q $path
	if [ $? -gt 0 ] ; then
		echo "Path $path is not mounted correctly"
		usage
	fi
fi

if [ $warning -gt $critical ] ; then
	echo "Warning is greater then critical"
	usage
fi
# sample which files should not be counted
exclude="ok.bat|Thumbs.db|dies ist der richtige Pfad.txt|new  24.txt"

filecount=`find $path -maxdepth 1 -type f | grep -E -i -v "$exclude" | wc -l`
oldestFile=`find $path -maxdepth 1 -type f -printf '%T@ %p\n' | grep -E -i -v "$exclude" |sort -k 1n | head -n 1`
oldestFileDate=`echo $oldestFile | awk '{print $1}'`
currentDate=`date +%s`
oldestFile=`echo $oldestFile | awk '{print $2}'`
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
echo "$returnString: file count is $filecount, oldest file \"`basename $oldestFile`\" is $oldestFileTime old|filecount=$filecount;$warning;$critical"
exit $returnState

