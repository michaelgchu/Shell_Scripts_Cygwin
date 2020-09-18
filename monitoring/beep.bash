#!/usr/bin/env bash
SCRIPTNAME="Beep & Speak Notification (Cygwin or Linux)"
LAST_UPDATED="2020-09-17"
SCRIPT_AUTHOR="Michael G Chu, michaelgchu@gmail.com"
# See Usage() function for purpose and calling details
#
# Reference:
# Linux:
# https://unix.stackexchange.com/questions/144924/how-can-i-create-a-message-box-from-the-command-line
# Cygwin:
# http://www.visualbasicscript.com/Can-VBScript-beep-make-a-sound-m719.aspx
# - For MsgBox, values known to generate sound: vbCritical; vbExclamation
#
# Updates
# =======
# 2020-09-17: add Linux coding
# 2016-05-19: last Cygwin-only version

set -u

# -------------------------------
# Usage Description
# -------------------------------

Usage()
{
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	cat << EOM

Usage: ${0##*/} [options] "message to say / display"

Speak and/or display a message on your system.
Example uses:
- at the end of a lengthy action to notify you when the job is done
- to set a timed message, e.g.
	sleep 180; $0 'Tea is steeped - go drink :)'

Within Cygwin, it uses the Windows SAPI.SPVoice functionality to speak;
the entire process is run via wscript.
Within Linux, speech is handled with festival or espeak, and message boxes
are displayed using zenity or xmessage.

OPTIONS
=======
   -h    Show this message
   -b    Display only - do not speak
   -s    Speak only - do not display

EOM
}

# ************************************************************
# Check inputs and such
# ************************************************************

# Process script args/settings
bBeep=true  ; beep_cmd=
bSpeak=true ; speak_cmd=
while getopts ":hbs" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		b) bSpeak=false ;;
		s) bBeep=false ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

# Ensure there's a message to output
test -n "$1" || { echo "Must supply a message. Run with -h for details"; exit 1; }

# ************************************************************
# Main Line - Cygwin.  Exit once done
# ************************************************************
if [ $OSTYPE = 'cygwin' ] ; then
	# Build up a  .vbs  script file to run the command(s)
	buffer=$(mktemp --suffix='.vbs') || { echo "Error creating temporary .vbs file"; exit 1; }
	trap 'rm --force $buffer' EXIT
	if $bSpeak ; then
		cat >> "$buffer" <<-EOM
			Dim sapi 
			Set sapi=CreateObject("sapi.spvoice") 
			sapi.Speak "$*"
		EOM
	fi
	if $bBeep ; then
		cat >> "$buffer" <<-EOM
			MsgBox "$*", vbOkOnly + vbExclamation, "$SCRIPTNAME"
		EOM
	fi
	# Execute the  .vbs  script
	wscript "$(cygpath --absolute --windows "$buffer")"
	# Exit now, so we don't need an ELSE structure
	exit $?
fi

# ************************************************************
# Main Line - Linux
# ************************************************************
# For each requested action, test that we have the required tool. Abort if not present
if $bBeep ; then
	for cmd in zenity xmessage
	do
		hash $cmd &>/dev/null && { beep_cmd=$cmd ; break; }
	done
	test -n "$beep_cmd" || { echo "To 'beep' you must have one of: zenity; xmessage"; exit 1; }
fi
if $bSpeak ; then
	for cmd in festival espeak
	do
		hash $cmd &>/dev/null && { speak_cmd=$cmd ; break; }
	done
	test -n "$speak_cmd" || { echo "To 'speak' you must have one of: festival; espeak"; exit 1; }
	if [ "$speak_cmd" = 'espeak' ] ; then
		hash aplay 2>/dev/null || { echo "To 'speak' using espeak, you must have aplay"; exit 1; }
	fi
fi

# Now do everything
if $bSpeak ; then
	case $speak_cmd in
		festival) festival --tts <<< "$*" ;;
		espeak) # This doesn't work on Raspberry Pi: espeak "$*"
			aplay <( espeak --stdout "$*" ) 2>/dev/null ;;
	esac
fi
if $bBeep ; then
	case $beep_cmd in
		zenity)   zenity --info --text="$*" ;;
		xmessage) xmessage -center "$*" 2>/dev/null ;;
	esac
fi

#EOF
