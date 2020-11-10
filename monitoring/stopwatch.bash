#!/usr/bin/env bash
SCRIPTNAME='Stopwatch'
LAST_UPDATED='2020-11-10'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
#
# Updates
# =======
# 20201110
# - Add ability to pause
# 20191104
# - Added break
# 20191021
# - First version
#

catch_sigint() {
	getout=true
}

trap catch_sigint SIGINT 

echo Press any key to pause/resume
echo Press CTRL-C to end
echo Stopwatch begins at:
date

getout=false
paused=false ; pstatus=''
counter=0 ; times=0
while [ $getout = false ]; do
	min=$((counter / 60))
	sec=$((counter - min*60))
	printf '\r%02d:%02d  %s      \r' $min $sec $pstatus
	if ! $paused ; then
		counter=$((counter + 1))
	fi
	if read -t 1 -N 1 char ; then
		if [ $paused = true ] ; then
			paused=false
			pstatus=''
		else
			paused=true
			pstatus='paused'
		fi
		times=$((times + 1))
	fi
done

echo
echo Stopwatch ends at:
date
echo Paused $((times/2)) times.

#EOF
