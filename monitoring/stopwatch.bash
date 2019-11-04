#!/usr/bin/env bash
SCRIPTNAME='Stopwatch'
LAST_UPDATED='2019-11-04'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
#
# Updates
# =======
# 20191104
# - Added break
# 20191021
# - First version
#

catch_sigint() {
	getout=true
}

trap catch_sigint SIGINT 

echo Press CTRL-C to end
echo Stopwatch begins at:
date

getout=false
counter=0
while [ $getout = false ]; do
	min=$((counter / 60))
	sec=$((counter - min*60))
	printf '\r%02d:%02d' $min $sec
	counter=$((counter + 1))
	sleep 1
done

echo
echo Stopwatch ends at:
date

#EOF
