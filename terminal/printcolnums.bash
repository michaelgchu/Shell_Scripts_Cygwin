#!/usr/bin/env bash
SCRIPTNAME='Print Column Indicators'
LAST_UPDATED='2017-11-22'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details
#
# Updates
# =======
# 20171122 - add ANSI colouring (via colour_codes.bash) for kicks; remove the useless 'dev mode'
# 20161013 - first version

# -------------------------------
# "Constants", Globals
# -------------------------------

# Listing of all required tools.  The script will abort if any cannot be found
requiredTools='seq cut sed tr'

# -----------------------------------------------------------------
# General Functions
# -----------------------------------------------------------------

Usage()
{
	if type CCecho >/dev/null ; then
		CCechoNR 'cyan underline overline' "$SCRIPTNAME ($LAST_UPDATED)"
		echo -n "Usage: "
		CCecho 'green' "${0##*/} "
		CCechoNR 'italic' '[options] [width to set]'
	else
		printTitle
		echo "Usage: ${0##*/} [options] [width to set]"
	fi
	cat << EOM

Prints a line of column numbers/indicators before the input.

If a width is not provided, it prints across the entire terminal.

OPTIONS
-------
   -h    Show this message
   -n    Use numbers instead of the mainframe-style indicator
         Only the one's place will be displayed.
   -C    Do not apply any colouring (via colour_codes.bash)

EOM
}

printTitle()
{
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}

# -------------------------------
# Auto-load colour_codes.bash, if found and not loaded
# -------------------------------

if ! type CCecho &>/dev/null ; then
	if hash colour_codes.bash 2>/dev/null ; then
		source colour_codes.bash
	fi
fi

# -------------------------------
# Main Line
# -------------------------------

# Process script args/settings
Mainframe_Style=true
while getopts ":hnC" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		n) Mainframe_Style=false ;;
		C) # Force colouring to fail by overriding the vars used for that
			ccCyan='' ; ccWhite=''
			;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

if [ -z "$1" ] ; then
	# Enable Bash to provide window size in the COLUMNS and LINES variables and run a command to initialize them
	shopt -s checkwinsize && ls > /dev/null
	toShow=$COLUMNS
else
	toShow=$1
fi

# -------------------------------
# Display the columns
# Dev note: had previously used 'seq' with variations, but this is much faster
# -------------------------------

#test $Mainframe_Style = true && seppy='----+----' || seppy='123456789'
if $Mainframe_Style ; then
#	seppy="----+----"
	seppy="----${ccCyan}+${ccWhite}----"
else
	seppy='123456789'
fi

sets=$(( toShow / 10 ))
remainder=$(( toShow - 10 * sets ))
for (( i = 1; i <= $sets; i++ ))
{
#	echo -en $seppy$(( i % 10 ))
	echo -en $seppy${ccCyan}$(( i % 10 ))${ccWhite}
}
echo ${seppy:0:remainder}

# -------------------------------
# And now output whatever was piped in
# -------------------------------

cat

#EOF
