#!/usr/bin/env bash
SCRIPTNAME='Side-by-side diff with colour'
LAST_UPDATED='2017-04-27'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
#
# Updates
# =======
# 20170427
# - Bug fix: for word highlighting, fix alignment issue when LHS is just whitespace
# - Bug fix: for word highlighting, make use of the extra  diff  options provided by caller
# - Code improvement:  instead of using Process Substitution for the two wdiff calls, use normal temporary files.  Resulted in an avg 5 sec speed improvement for the sample files tested
# - General cleanup
# 20170426
# - Bug fix: for word highlighting, LHS was interpreting escape sequences like \n
# 20161109
# - Prevent temp file deletion when in DEV_MODE
# 20160914
# - add option to output to basic HTML (prevents normal output)
# 20160913
# - add new "word highlighting" mode, which marks individual blocks of changes per line
# 20160907
# - add script option to allow user to specify additional diff options, e.g. --minimal
# - add script option to prevent colourization, just in case user wants that
# 20160808
# - change diff whitespace option from  --ignore-trailing-space  to  --ignore-space-change, as it is less strict on whitespace changes (but still requires them)
# 20160727
# - add a call to 'cmp' first, to confirm there are differences before running the diff
# 20160315
# - clarify that line numbers are for the output, and not necessarily the numbering of the input files
# 20160314
# - First working version
#
# References:
# Regarding how to treat whitespace between the two files, see this:
#	https://www.gnu.org/software/diffutils/manual/html_node/White-Space.html

# -------------------------------
# "Constants", Globals
# -------------------------------

DEV_MODE=false

# Define the 4 standard diff colours here, to be used for word highlighting mode
# These can be used in echo and printf statements by Bash and Awk and Perl.
# NOTE: only use ccBlack to turn OFF the other colours
ccBlack="\x1B[0;0m"
ccRed="\x1B[1;31m"
ccBlue="\x1B[1;34m"
ccMagenta="\x1B[1;35m"

# Define again with regex metachars escaped, for use when preparing HTML output
ccAwkPatBlack="\x1B\[0;0m"
ccAwkPatRed="\x1B\[1;31m"
ccAwkPatBlue="\x1B\[1;34m"
ccAwkPatMagenta="\x1B\[1;35m"

# Listing of all required tools.  The script will abort if any cannot be found
requiredTools='diff file mktemp dos2unix wc cmp'
extraToolsForWordHighlighting='bc awk sed cut wdiff'

# -------------------------------
# Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/} [options] file1 file2

Performs a side-by-side 'diff' of the provided files.  Colourizes, if possible.
Runs 'cmp' first to ensure there are differences to display.

The  --ignore-space-change  diff option is used to eliminate whitespace diffs. 
Note that wide lines will get trimmed, i.e. no line wrapping.

It runs the output through the 'less' pager, if required.

To save the results to Word, use a terminal width of 132.  Paste results into
Word, use landscape orientation and set margins to narrow.

OPTIONS
=======
   -h    Show this message
   -o diff_option
         Add your own diff options to use, e.g. --minimal or --ignore-all-space
         Stackable.
   -w    Perform word highlighting for modified lines.
         Note 1: only visible sections of the line are highlighted 
         Note 2: this process is slow and a tad buggy. Take with grain of salt
   -l    Output as HTML.
         Note 1: your terminal still drives the viewing area of the HTML page
         Note 2: the source files should not contain HTML code
   -C    Do not colourize the output using colordiff
   -N    Do not print line numbers for the diff output
   -P    Do not use the 'less' pager
   -q    Be Quiet: do not show notices, filenames
   -D    DEV/DEBUG mode on
         Use twice to run 'set -x'

EOM
}


# Poor man's ANSI-to-HTML convertor.  There are proper tools for this, but don't want to rely on any more
ansi2html()
{
	cat << EOD_HTML_Start
<!DOCTYPE html>
<html>
	<head>
		<title> Comparison of "$file1" to "$file2" </title>
		<meta name="description" content="$(date '+%Y-%m-%d') Execution command line: ${0##*/} $originalCmdLine" />
	</head>
	<body>
		<pre>
EOD_HTML_Start

	awk '{
	# Ignore/remove the "black" ANSI colour code at the start of the line == we did not add that
	sub(/'^$ccAwkPatBlack'/, "");
	gsub(/'$ccAwkPatBlack'/, "</span>");
	# Replace all colour codes we injected with the appropriate coloured "span" tags
	gsub(/'$ccAwkPatRed'/, "<span style=\"color:red\">");
	gsub(/'$ccAwkPatBlue'/, "<span style=\"color:blue\">");
	gsub(/'$ccAwkPatMagenta'/, "<span style=\"color:magenta\">");
	print;
}'

	cat << EOD_HTML_End
		</pre>
	</body>
</html>
EOD_HTML_End
}


# This function will be called on script exit, if required.
finish() {
	if $DEV_MODE ; then
		cat <<- EOM  >/dev/stderr


			[NOT removing temporary files:
			fileA   : $fileA
			fileB   : $fileB
			lhs     : $fileLHS
			rhs     : $fileRHS
			outDiff : $outDiff ]
		EOM
	else
		rm -f "$fileA" "$fileB" "$fileLHS" "$fileRHS" "$outDiff"
	fi
}
fileA=''
fileB=''
fileLHS=''
fileRHS=''
outDiff=''


debugsay()
{
	test $DEV_MODE = true && echo "$*" > /dev/stderr
}

debugpause()
{
	test $DEV_MODE = true && { debugsay "[Press ENTER to continue]"; read; }
}


say()
{
# Output the provided message only if Be_Quiet = 'no', i.e. if script not called with -q option
# The first argument can be a flag for echo, e.g. -e to do escape sequences, -n to not echo a newline
	if $Be_Quiet ; then return ; fi
	c1=$(echo "$*" | cut -c1)
	if [ "$c1" = '-' ] ; then
		flag=$1
		shift
	else
		flag=''
	fi
	echo $flag "$*"
}


printTitle()
{
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}

# -------------------------------
# Main Line
# -------------------------------

originalCmdLine="$*"

# Process script args/settings
Be_Quiet=false	# Whether to suppress standard script messages
inputFile=''
outputFile=''
extraOpts=''
AvoidPager=false
Colourize=true
ShowLineNo=true
WordHighlighting=false
OutputAsHTML=false
while getopts ":ho:wlCNPqD" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		o) extraOpts="$extraOpts $OPTARG" ;;
		w) WordHighlighting=true ;;
		l) OutputAsHTML=true ;;
		C) Colourize=false ;;
		N) ShowLineNo=false ;;
		P) AvoidPager=true ;;
		q) Be_Quiet=true ;;
		D) 
			if $DEV_MODE ; then
				set -x
			else
				DEV_MODE=true
			fi
			;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

if $DEV_MODE ; then
	cat <<- EODM
		[**DEBUG MODE enabled**]
		[Requested flags (current state):
		Diff opts  = $extraOpts
		Colourize  = $Colourize
		ShowLineNo = $ShowLineNo
		AvoidPager = $AvoidPager
		Word Highlighting = $WordHighlighting
		Output as HTML    = $OutputAsHTML
		Be_Quiet   = $Be_Quiet ]
	EODM
fi

# Test for all required tools/resources
debugsay "[Testing for required command(s): $requiredTools]"
flagCmdsOK='yes'
if $WordHighlighting ; then
	toolset="$requiredTools $extraToolsForWordHighlighting"
else
	toolset=$requiredTools
fi
for cmd in $toolset
do
	hash $cmd &>/dev/null || { echo "Error: command '$cmd' not present"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || exit 1

debugsay '[Checking for file1 & file2]'
test -z "$2" && { echo 'Must supply 2 input filenames to compare. Run with  -h  to see options'; exit 1; }
test -f "$1" -a -r "$1" || { echo "Error: '$1' is not readable, or is not a file"; exit 1; }
test -f "$2" -a -r "$2" || { echo "Error: '$2' is not readable, or is not a file"; exit 1; }

# Store these filenames for potential later use
file1="$1"
file2="$2"

# -------------------------------
# Test that the files are different
# -------------------------------

debugsay '[Checking that files are different]'
if  cmp --silent "$1" "$2" ; then
	echo 'Files are identical.'
	exit 0
fi

# -------------------------------
# Determine the commands to run
# -------------------------------

# Enable Bash to provide window size in the COLUMNS and LINES variables ...
debugsay '[Enabling terminal size variables]'
shopt -s checkwinsize
# ... and run a command to initialize them
ls > /dev/null

if $OutputAsHTML ; then
	diffWidth=$COLUMNS
	AvoidPager=true
	ShowLineNo=false
	finalCmd=ansi2html
	fOpts=''
else
	# Normal terminal output - possibly with line numbers and using a pager

	# Test if a pager is even necessary - to simplify the conditional expressions, just
	# directly modify the AvoidPager var
	# A pager is needed if LINES-x is not greater than the line count of both files,
	# where  x  is 3, 4 or 5:
	# - 3 = the default extra 3 lines that get displayed by the shell after the
	#       diff command has finished running (a blank line, the path, then the prompt)
	# - 4 = the 3 above, plus 1 for the notice about the line numbering (if using numbering)
	# - 5 = the 4 above, plus 1 for the filenames
	if $Be_Quiet ; then
		x=3
	else 
		if $ShowLineNo ; then
			x=5
		else
			x=4
		fi
	fi
	if [ $((LINES-x)) -gt $(wc -l < "$1")  -a  $((LINES-x)) -gt $(wc -l < "$2") ] ; then
		debugsay "[Pager not required]"
		AvoidPager=true
	fi

	# Set the final command to pipe through as either basic cat (i.e. no paging) or less
	# Check to see whether the user wants line numbers displayed or not - this impacts the width argument we pass to diff
	# Luckily, 'cat' and 'less' both default to 8 characters usage for line numbers. So we can simply reduce the diff width by 8 if showing numbers
	if $AvoidPager ; then
		finalCmd='cat'
		if $ShowLineNo ; then
			fOpts='-n'
			diffWidth=$((COLUMNS - 8))
		else
			fOpts=''
			diffWidth=$COLUMNS
		fi
	else
		finalCmd='less'
		if $ShowLineNo ; then
			# -R allows for colour control sequences; -N displays line numbers
			fOpts='-R -N'
			diffWidth=$((COLUMNS - 8))
		else
			fOpts='-R'
			diffWidth=$COLUMNS
		fi
	fi
fi # if $OutputAsHTML

# -------------------------------
# Build up the files to compare.
# Convert input DOS files to UNIX, if required
# -------------------------------

debugsay '[Creating temporary files]'
trap finish EXIT
fileA=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
fileB=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
fileLHS=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
fileRHS=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }


if ! $Be_Quiet ; then
	debugsay '[Temporary files will start with the filenames]'
	echo "INPUT: $1" > $fileA
	echo "INPUT: $2" > $fileB
fi

if  file "$1" | grep CRLF >/dev/null ; then
	debugsay "[Must convert file '$1']"
	dos2unix < "$1" >> $fileA || { echo "Error processing '$1'"; exit 1; }
else
	debugsay "[Using file '$1' as-is]"
	cat < "$1" >> $fileA || { echo "Error copying '$1'"; exit 1; }
fi
if  file "$2" | grep CRLF >/dev/null ; then
	debugsay "[Must convert file '$2']"
	dos2unix < "$2" >> $fileB || { echo "Error processing '$2'"; exit 1; }
else
	debugsay "[Using file '$2' as-is]"
	cat < "$2" >> $fileB || { echo "Error copying '$2'"; exit 1; }
fi

# -------------------------------
# Execute the diff code
# Here we branch off significantly:  the "regular" diff process is quite straightforward. 
# The "word highlighting" method takes far more effort
# -------------------------------

if $WordHighlighting ; then
	# *********************************************
	# Word Highlighting Mode
	# *********************************************

	outDiff=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }

	# Determine where diff will place the flag column.  From testing:
	#	--> when even, then the flag column is exactly half
	#	--> when odd, then the flag column is half rounded up
	split=$( bc <<< "a=$diffWidth; if ( a%2) a/2+1 else a/2" )
	# Used to cut out the LHS of the side-by-side output:
	lhsCutAt=$((split-2))
	# Diff only displays at most the below amount of chars per side
	# For LHS, it always leaves 1 space gap.
	# For RHS, it starts after 1 space, and can go up to the last available column
	# This var is more for informational purposes - we are not testing the length of either side against it
	sideWidth=$((split - 2))

	debugsay "[COLUMNS is $COLUMNS; diffWidth = $diffWidth; split point is $split; max width per side is $sideWidth]"
	debugpause

	# Perform the basic side-by-side diff:
	# Control exact width of this output using  --width
	# Use --expand-tabs, otherwise diff uses tabs to separate LHS from RHS
	diff --width=$diffWidth --ignore-space-change --expand-tabs --side-by-side $extraOpts "$fileA" "$fileB" > "$outDiff"

	cat "$outDiff" | while IFS='' read -r line
	do
		if $DEV_MODE ; then
			echo LINE:
			printf "%s\n" "$line"
		fi

		# Pull out the character that indicates what diff reports for this line:
		# Note: it is -1 because Bash uses 0-based character indices for vars
		flag=${line:split-1:1}

		if [ "$flag" != "|" ] ; then
			# Not the 'modified' flag.  We treat these all similarly and simply:
			if [ "$flag" = " " ] ; then
				# No change
				colourCode=''
			elif [ "$flag" = "<" ] ; then
				# Line was removed
				colourCode=$ccRed
			elif [ "$flag" = ">" ] ; then
				# Line was added
				colourCode=$ccBlue
			fi
			# Print with colour codes, and move on to next line
			printf "${colourCode}%s${ccBlack}\n"  "$line"
			continue
		fi

		# All remaining code deals with the "modified" lines ********************

		# Separate left from right sides, to prepare for the word-level differencing
		# We also need the length of the LHS for calculating field spacing
		lhsPlain=$(sed -r "s/^(.{$lhsCutAt}).*$/\1/; s/ +$//" <<< "$line")
		# For RHS, no need to remove trailing spaces (wdiff ignores them)
		rhsPlain=$(cut -c$((split+2))- <<< "$line")

		# And now generate the colour-coded word-differenced Left & Right hand sides using 'wdiff' and elbow grease
		# Instead of using 'colordiff', we provide our own ANSI colour codes to mark changed regions
		# Escape any backslashes that are not for colour codes (e.g. "\n" )
		# (Note: writing to regular files instead of using  <(..)  Process Substitution - it gives a speed boost)
		echo -n "$lhsPlain" > "$fileLHS"
		echo -n "$rhsPlain" > "$fileRHS"
		lhsCoded=$(wdiff --no-inserted --start-delete="$ccMagenta" --end-delete="$ccBlack" "$fileLHS" "$fileRHS" |  sed -r 's/\\[^x]/\\&/g')
		rhsCoded=$(wdiff --no-deleted  --start-insert="$ccMagenta" --end-insert="$ccBlack" "$fileLHS" "$fileRHS" |  sed -r 's/\\[^x]/\\&/g')

		# Determine the field spacing to assign for the LHS string
		if [ ${#lhsPlain} -eq 0 ] ; then
			# If the LHS is just whitespace, then these strings will be empty and it throws printf off
			lhsPlain=' '
			lhsCoded=' '
		fi
		# We pass the LHS coded string to printf so that the ANSI codes get interpreted.  Otherwise, the positioning is off.
		printf -v forCharCount "%b" "$lhsCoded"
		# Calculate the LHS field space as the actual field space ('split') plus the difference in characters between the plain and ANSI-coded LHS strings
		lhsSpace=$(( split -1 + ${#forCharCount} - ${#lhsPlain} ))

		if $DEV_MODE ; then
			cat <<- EOD
LHS Plain (${#lhsPlain} chars) = $lhsPlain
RHS Plain (${#rhsPlain} chars) = $rhsPlain
LHS wdiff (${#lhsCoded} chars) = $lhsCoded
RHS wdiff (${#rhsCoded} chars) = $rhsCoded
Char # delta = $(( ${#lhsCoded} - ${#lhsPlain} ))
Spacing = $lhsSpace = $split - 1 + ${#lhsCoded} - ${#lhsPlain}
RESULT =
			EOD
		fi

		printf "%-${lhsSpace}b${ccMagenta}|${ccBlack} %b\n" "$lhsCoded" "$rhsCoded"
	done |
	$finalCmd $fOpts

else
	# *********************************************
	# This is the "regular" diff process:  perform the [color]diff, potentially passing to a pager
	# *********************************************

	# Use colordiff if available, and allowed
	diffCmd='diff'
	if $Colourize ; then
		hash colordiff 2>/dev/null && diffCmd='colordiff'
	fi

	debugsay "[Commands to use:  $diffCmd, $finalCmd $fOpts]"
	debugpause

	if $ShowLineNo ; then
		say "Note: line numbers are for diff output only (and likely not the actual line numbers of the input files)"
	fi

	# Control exact width of this output using  --width
	$diffCmd --width=$diffWidth --ignore-space-change --side-by-side $extraOpts "$fileA" "$fileB" |
	$finalCmd $fOpts

fi # word / regular full-line highlighting

exit $?

#EOF
