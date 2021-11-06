#!/usr/bin/env bash
SCRIPTNAME='Side-by-side diff with colour'
LAST_UPDATED='2021-11-06'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
#
# Updates
# =======
# 20211104
# - For normal diff, manually inject colouring if there is no colordiff tool
# 20200614
# - Allow use of <(...) instead of passing just files
# - Make use of cmp optional
# - Bug fix for HTML output without word highlighting: grab the ANSI codes used by colordiff so the search & replace works properly
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

# This associative array will store the ANSI colour sequences that colordiff
# uses to represent: removed; same; changed; added
# They are used for word highlighting mode
# We hardcode the values now, and replace later only if required.
declare -A cc
cc['removed']="\x1B[1;31m"	# red
cc['same']="\x1B[0;0m"		# black
cc['changed']="\x1B[1;35m"	# magenta
cc['added']="\x1B[1;34m"	# green/blue

# This associative array has the same contents as <cc>, except the "["
# character is escaped. This allows for using in regular expressions
# They are used for a simple conversion to HTML
declare -A cc_ree
for kind in removed same changed added
do
	cc_ree[$kind]=$(perl -p -e 's/\[/\\[/g' <<< "${cc[$kind]}")
done

# Listing of all required tools.  The script will abort if any cannot be found
requiredTools='diff file mktemp wc cmp'
extraToolsForWordHighlighting='awk sed cut wdiff'

# -------------------------------
# Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/} [options] file1/pipe1 file2/pipe2

Performs a side-by-side 'diff' of the provided files.  Colourizes, if possible.

The  --ignore-space-change  diff option is used to eliminate whitespace diffs. 
Note that wide lines will get trimmed, i.e. no line wrapping.

It runs the output through the 'less' pager, if required.

To save the results to Word, use a terminal width of 132.  Paste results into
Word, use landscape orientation and set margins to narrow.

Since it allows for process substitution, you could run a command like this:
$0 <(cut -c18-65 file1.txt | sort | dos2unix)  <(cut -c18-65 file2.txt | sort | dos2unix)


OPTIONS
=======
   -h    Show this message
   -o diff_option
         Add your own diff options to use, e.g. --minimal or --ignore-all-space
         Stackable.
   -w    Perform word highlighting for modified lines.
         Note 1: only visible sections of the line are highlighted 
         Note 2: this process is slow and a tad buggy. Take with grain of salt
   -l    Output as HTML
         Note 1: your terminal still drives the viewing area of the HTML page
         Note 2: the source files should not contain HTML code
   -b    Run basic 'cmp' first to ensure there are differences to display
   -C    Do not colourize the output using colordiff (or internal function)
   -N    Do not print line numbers for the diff output
   -P    Do not use the 'less' pager
   -q    Be Quiet: do not show notices, filenames
   -D    DEV/DEBUG mode on

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
		<style type="text/css">
			.removed { color: red }
			.same { color: black }
			.changed { color: magenta }
			.added { color: green }
		</style>
	</head>
	<body>
		<pre>
EOD_HTML_Start

	awk '{
	# Replace < with &lt; and > with &gt;
	gsub(/</, "\\&lt;");
	gsub(/>/, "\\&gt;");
	# Ignore/remove the same/"black" ANSI colour code at the start of the line == we did not add that
	sub(/'^${cc_ree['same']}'/, "");
	# All other occurrences of same/"black" should be replaced with </SPAN> closing tags
	gsub(/'${cc_ree['same']}'/, "</span>");
	# Replace all colour codes we injected with the appropriate coloured "span" tags
	gsub(/'${cc_ree['removed']}'/, "<span class=\"removed\">");
	gsub(/'${cc_ree['added']}'/, "<span class=\"added\">");
	gsub(/'${cc_ree['changed']}'/, "<span class=\"changed\">");
	print;
}'

	cat << EOD_HTML_End
		</pre>
	</body>
</html>
EOD_HTML_End
}


capture_colour_from_colordiff() {
	# Run colordiff between 2 hardcoded files in order to extract the ANSI
	# codes it uses for: removed; same; changed; added
	# Stores these ANSI codes in an associative array that msut be
	# declared in the main line:  cc
	# Also stores these codes with the [ escaped so they can be referenced
	# using regular expressions:  cc_ree
	output=$(colordiff --width=30 --side-by-side \
		<(cat <<- EODLEFT
			<in A only>
			L2 no diff
			L3 has diff
		EODLEFT
		) \
		<(cat <<- EODRIGHT
			L2 no diff
			L3 got diff
			<in B only>
		EODRIGHT
		) )
	for kind in removed same changed added
	do
		read line
		# Each line starts with an ANSI code; return just that bit
		# e.g.  Red == \x1B[1;31m
		ansicode=$(perl -p -e 's/(?<=m).*//' <<< "$line")
		# The [ is a regex metacharacter; escape it
		ansi_re_escaped=$(perl -p -e 's/\[/\\[/g' <<< "$ansicode")
		cc[$kind]="$ansicode"
		cc_ree[$kind]="$ansi_re_escaped"
	done <<< "$output"
}


# Execute this function if the user wants colouring but colordiff isn't available
manualColouring()
{
	# Determine the split point between LHS & RHS
	# (This is the same split as with word highlighting)
	split=$( awk '{ half=$1 / 2; print half==int(half) ? half : int(half) + 1 }' <<< $diffWidth )
	# Reduce value by 1, for use in regex
	char=$((split - 1))
	# Now, use regular expressions to apply colour coding:
	# 1. Consume the X characters leading up to the split point,
	#    then one of the diff indicators, | or < or >, then the rest.
	# 2. Apply the corresponding colour sequence for any matches and reset.
	sed -r  -e "s/^(.{$char}\|.*)/${cc['changed']}\1${cc['same']}/" \
		-e "s/^(.{$char}<.*)/${cc['removed']}\1${cc['same']}/" \
		-e "s/^(.{$char}>.*)/${cc['added']}\1${cc['same']}/"
}


# This function will be called on script exit, if required.
clean_exit() {
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
UseCMP=false
while getopts ":ho:wlCNPqbD" OPTION
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
		b) UseCMP=true ;;
		D) DEV_MODE=true ;;
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
		Be_Quiet   = $Be_Quiet
		Use cmp    = $UseCMP
		]
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
test -z "$2" && { echo 'Must supply 2 input filenames/pipes to compare. Run with  -h  to see options'; exit 1; }
test -r "$1" || { echo "Error: '$1' is not readable"; exit 1; }
test -r "$2" || { echo "Error: '$2' is not readable"; exit 1; }
test -f "$1" -o -p "$1" || { echo "Error: '$1' is neither a file nor a pipe"; exit 1; }
test -f "$2" -o -p "$2" || { echo "Error: '$2' is neither a file nor a pipe"; exit 1; }

# Store these filenames for later use
file1="$1"
file2="$2"

# -------------------------------
# Test that the files are different - if requested and we are dealing with files
# -------------------------------

if [ $UseCMP = true -a -f "$1" -a -f "$2" ] ; then
	debugsay '[Checking that files are different]'
	if  cmp --silent "$1" "$2" ; then
		echo 'Files are identical.'
		exit 0
	fi
fi

# -------------------------------
# Build up the files to compare.
# Convert input DOS files to UNIX, if required
# -------------------------------

debugsay '[Creating temporary files]'
trap clean_exit EXIT
fileA=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
fileB=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
fileLHS=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
fileRHS=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }


if ! $Be_Quiet ; then
	debugsay '[Temporary files will start with the filenames]'
	echo "INPUT: $1" > $fileA
	echo "INPUT: $2" > $fileB
fi

if [ -f "$1" ] ; then
	if  file "$1" | grep CRLF >/dev/null ; then
		debugsay "[Must convert file '$1']"
		dos2unix < "$1" >> $fileA || { echo "Error processing '$1'"; exit 1; }
	else
		debugsay "[Using file '$1' as-is]"
		cat < "$1" >> $fileA || { echo "Error copying '$1'"; exit 1; }
	fi
else
	debugsay "[Read pipe '$1', then check if conversion required]"
	cat < $1 >> $fileA || { echo "Error copying '$1'"; exit 1; }
	if  file "$fileA" | grep CRLF >/dev/null ; then
		debugsay "[Must convert file]"
		dos2unix $fileA || { echo "Error processing '$1'"; exit 1; }
	fi
fi

if [ -f "$2" ] ; then
	if  file "$2" | grep CRLF >/dev/null ; then
		debugsay "[Must convert file '$2']"
		dos2unix < "$2" >> $fileB || { echo "Error processing '$2'"; exit 1; }
	else
		debugsay "[Using file '$2' as-is]"
		cat < "$2" >> $fileB || { echo "Error copying '$2'"; exit 1; }
	fi
else
	debugsay "[Read pipe '$2', then check if conversion required]"
	cat < $2 >> $fileB || { echo "Error copying '$2'"; exit 1; }
	if  file "$fileB" | grep CRLF >/dev/null ; then
		debugsay "[Must convert file]"
		dos2unix $fileB || { echo "Error processing '$2'"; exit 1; }
	fi
fi

# -------------------------------
# Test that the files are different - if requested and we had a pipe
# -------------------------------

if [ $UseCMP = true ] ; then
	if [ -p "$1" -o -p "$2" ] ; then
		debugsay '[Checking that inputs are different, now that we have them settled]'
		if  cmp --silent "$fileA" "$fileB" ; then
			echo 'Files are identical.'
			exit 0
		fi
	fi
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
	if [ $((LINES-x)) -gt $(wc -l < "$fileA")  -a  $((LINES-x)) -gt $(wc -l < "$fileB") ] ; then
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
	split=$( awk '{ half=$1 / 2; print half==int(half) ? half : int(half) + 1 }' <<< $diffWidth )
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
				colourCode=${cc['removed']}
			elif [ "$flag" = ">" ] ; then
				# Line was added
				colourCode=${cc['added']}
			fi
			# Print with colour codes, and move on to next line
			printf "${colourCode}%s${cc['same']}\n"  "$line"
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
		lhsCoded=$(wdiff --no-inserted --start-delete="${cc['changed']}" --end-delete="${cc['same']}" "$fileLHS" "$fileRHS" |  sed -r 's/\\[^x]/\\&/g')
		rhsCoded=$(wdiff --no-deleted  --start-insert="${cc['changed']}" --end-insert="${cc['same']}" "$fileLHS" "$fileRHS" |  sed -r 's/\\[^x]/\\&/g')

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

		printf "%-${lhsSpace}b${cc['changed']}|${cc['same']} %b\n" "$lhsCoded" "$rhsCoded"
	done |
	$finalCmd $fOpts

	exit $?
fi # word highlighting


# *********************************************
# This is the "regular" diff process:  perform the [color]diff, potentially passing to a pager
# *********************************************

# Use colordiff if available and allowed. If colordiff isn't available, use our custom function
diffCmd='diff'
penultimateCmd='cat'
if $Colourize ; then
	hash colordiff 2>/dev/null && diffCmd='colordiff'
	# Not sure how well these 2 will play together ...
	test $? -eq 0 || penultimateCmd=manualColouring
	if [ $OutputAsHTML = true -a $diffCmd = 'colordiff' ] ; then
		capture_colour_from_colordiff
	fi
fi

debugsay "[Commands to use:  $diffCmd, $finalCmd $fOpts, $penultimateCmd]"
debugpause

if $ShowLineNo ; then
	say "Note: line numbers are for diff output only (and likely not the actual line numbers of the input files)"
fi

# Control exact width of this output using  --width
$diffCmd --width=$diffWidth --ignore-space-change --expand-tabs --side-by-side $extraOpts "$fileA" "$fileB" |
$penultimateCmd |
$finalCmd $fOpts

exit $?

#EOF
