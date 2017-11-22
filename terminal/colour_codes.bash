#!/usr/bin/env bash
SCRIPTNAME='Colour Codes for Scripting'
LAST_UPDATED='2017-11-22'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
#
# Updates
# =======
# 20171122
# - First version
#
# References
# ==========
# ANSI Code sequences:  https://en.wikipedia.org/wiki/ANSI_escape_code#3.2F4_bit
# Checking for associative array keys:  http://wiki.bash-hackers.org/syntax/arrays


# ************************************************************
# Variables for use by the caller
# ************************************************************

_e='\x1B['	# The start of all ANSI Escape sequences

# -- The different modes/renderings
ccReset="${_e}0m"
ccBold="${_e}1m"	# aka Bright
ccItalic="${_e}3m"
ccUnderline="${_e}4m"
ccOverline="${_e}53m"
#ccBlink="${_e}5m"	# Slow blink: less than 150/min.  Not supported?

# -- The different foreground colours
ccBlack="${_e}30m"
ccRed="${_e}31m"
ccGreen="${_e}32m"
ccYellow="${_e}33m"
ccBlue="${_e}34m"
ccMagenta="${_e}35m"
ccCyan="${_e}36m"
ccWhite="${_e}37m"


# ************************************************************
# Internal Variables used by the CCecho() function
# ************************************************************

unset ccStyles ccModes ccColours
declare -A ccStyles ccModes ccColours
ccStyles=( [reset]=0 [normal]=0 [bold]=1 [bright]=1 [italic]=3 [underline]=4 [overline]=53 )
ccModes=( [standard]=30 [foreground]=30 [background]=40 )
ccColours=( [black]=0 [red]=1 [green]=2 [yellow]=3 [blue]=4 [magenta]=5 [cyan]=6 [white]=7)


# ************************************************************
# Functions for use by caller
# - CCecho()  is the most versatile one
# - CCecho*() are variations on calling  CCecho()
# - CCreset(), CCbold(), etc. are one-liner activations of codes
# - CChelp()  can give some help 
# ************************************************************


CCechoN() { CCecho "$@\n" ; }
CCechoR() { CCecho "$@" ; CCreset ; }
CCechoNR() { CCecho "$@" ; CCreset ; echo; }
CCechoRN() { CCecho "$@" ; CCreset ; echo; }

CCecho() {
# Arg 1 is the space-separated collection of all styles and mode + colour to set
# The terminal remembers what's currently in effect, so just call with new settings
# Arg 2+ is what to print to stdout
	renderOptions='' ; badOptions=''
	currMode=30 ; currColour=0
	for x in $1 ; do
		if [[ ${ccStyles[$x]} ]]; then
			renderOptions+=";${ccStyles[$x]}"
		elif [[ ${ccModes[$x]} ]] ; then
			currMode=${ccModes[$x]}
		elif [[ ${ccColours[$x]} ]] ; then
			currColour=${ccColours[$x]}
			renderOptions+=";$((currMode + currColour))"
		else
			badOptions+=" $x"
		fi
	done
	test -n "$badOptions" && echo "Warning - unrecognized render option(s): $badOptions" >/dev/stderr
	# Correct the syntax of the render options, so it looks like: \x1B[#;#;#;#m
	renderOptions=$(sed --regexp-extended 's/^;/\\x1B[/; s/$/m/' <<< "$renderOptions")
	shift
	echo -en "${renderOptions}$@"
}


# One-liner activation of the defined style codes
CCreset()	{ echo -en $ccReset ; }
CCbold()	{ echo -en $ccBold ; }
CCitalic()	{ echo -en $ccItalic ; }
CCunderline()	{ echo -en $ccUnderline ; }
CCoverline()	{ echo -en $ccOverline ; }


CChelp() {
	CCechoRN 'reset bold underline overline blue' "$SCRIPTNAME"
	echo "Last updated on $LAST_UPDATED"

	CCunderline
	echo -e "\nVariables you can 'echo' to set style or colour:"
	CCreset
	while read var
	do
		if [ "$var" = 'ccBlack' ] ; then
			echo -e '\tccBlack'
		else
			# Use ${!...} indirect referencing to activate the code
			echo -e "\t${!var}${var}${ccReset}"
		fi
	done <<- EOD
		$(set | grep --perl-regexp '^cc[A-Z][a-z]+=' | grep -v '\]' | cut -f1 -d=)
	EOD

	echo -e "\n${ccGreen}${ccUnderline}Functions you can call:${ccReset}"
	set | grep --perl-regexp '^CC[a-z]+ \(\)' | sed --regexp-extended 's/^/\t/'

	echo
	echo -n "Tip 1: run '"
	CCechoR 'foreground red background yellow' 'type CChelp'
	echo "' to see the commands used to make this colourful output."
	CCechoRN 'italic' 'Tip 2: the same can be used in a script to test if these vars/functions are loaded'
}


# ************************************************************
# Export everything so they can be used by scripts etc
# ************************************************************
export ccReset ccBold ccItalic ccUnderline ccOverline ccBlack ccRed ccGreen ccYellow ccBlue ccMagenta ccCyan ccWhite ccStyles ccModes ccColours
export -f CCechoN CCechoR CCechoNR CCechoRN CCecho CCreset CCbold CCitalic CCunderline CCoverline CChelp

#EOF
