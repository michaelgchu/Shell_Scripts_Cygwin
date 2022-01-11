#!/usr/bin/env bash
# "typescript cleaner"
# Last updated: 2022-01-10
# Author: Michael Chu, https://github.com/michaelgchu
# See Usage() for purpose and call details
#
# NOTES:
# - Tested in Cygwin64 and Linux
# - Bash's TAB auto-completion does not generate any control sequences, whether
#   it was an immediate completion or the shell brings up a list of options
# - The Control Sequence Introducer (CSI) is 2 bytes: ESC + '['
# - The ESC character can be represented as one of:   \x1b  \e  \033
#-------------------------------------------------------------------------------
Usage() {
	cat << EOM
Usage: ${0##*/} [filename]

Removes the control sequences from a typescript file, so you can more easily
work with it in a text editor. Also handles the BACKSPACE key.

If you do not provide the name of a file to read on the command line, then it
will read from standard in.

Sample call:  ${0##*/} typescript > cleaned.txt
EOM
}

test "$1" = '-h' -o "$1" = '--help' && { Usage; exit 0; }

# Switch input from STDIN to a file, if provided (assume 1st & only arg is a file)
if [ $# -eq 1 ] ; then
        test -f "$1" -a -r "$1" || { echo "'$1' not a valid input file"; exit 1; }
        # change FD0/STDIN to the input file
        exec 4<&0 0< "$1"
        # ... and Restore STDIN on script exit
        trap 'exec 0<&4' EXIT
fi

sed --regexp-extended "
# Handle the BACKSPACE key (^H): remove this key, the control sequence, and the character that got deleted.
# This has to be looped, to handle repeated backspace presses.
# Output will be ruined if the user pressed BACKSPACE more times than necessary.
:repeat_backspace
s/.\x08\x1b\[K//
t repeat_backspace

# Remove linefeeds (^M)
s/\x0d//g

# Remove that odd line that appears just before the prompt output
s/^\x1b.*\]0;.*\x07$//

# Remove colour-changing control sequences: CSI <list of semicolon-delimited numbers> m
s/\x1b\[([0-9]+;?)+m//g

# Replace the left & right single quote seen when using 'cp -v':  e2 80 98/99
s/\xe2\x80(\x98\|\x99)/'/g

# Remove codes for Bracketed Paste Mode
# https://en.wikipedia.org/wiki/ANSI_escape_code
# https://cirw.in/blog/bracketed-paste
# Bracketed Paste Mode: CSI ? 2004 h turns on, CSI ? 2004 l turns off
s/\x1b\[\?2004[hl]//g
"

#EOF
