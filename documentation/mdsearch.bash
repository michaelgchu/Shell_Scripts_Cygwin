#!/usr/bin/env bash
SCRIPTNAME='Find & Display Markdown'
LAST_UPDATED='2018-04-14'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
#
# mdv  available from:
#	https://github.com/axiros/terminal_markdown_viewer
#
# Updates
# =======
# 2018-04-14
# - First posted version (initial development began Aug 2017)
#
# Learnings
# - Bash's Process Substitution <(...) can have nested process substitution   :)
# - regex: the period matches anything except newlines
#	- to allow for newlines, can add the  /s  modifier
#	- OR replace the period with something like this:  [\d\D]
# - regex: since lookarounds do not consume chars, we can use a bunch of them to
#   test for the presence of multiple keywords

# -------------------------------
# "Constants", Globals
# -------------------------------

# The directory structure to search for Markdown files
# Using  find  with the  -follow  option to follow symlinks, so you can drop
# all sorts of references in there
SearchPath="${HOME}/md/Notes_Markdown"

requiredTools='mdv'

# -------------------------------
# Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/} [options] [keywords]

Search your collection of Markdown files for the specified keywords and display
matches in the terminal using 'mdv': the Terminal Markdown Viewer.

The following directory is searched for files:
	$SearchPath
Any symlinks will be followed as it looks for text files.

OPTIONS
=======
-h    Show this message
-f    Filename-based search:  display files whose filepaths have the
      keyword(s).  [Default]
-c    Content-based search:  display files that contain the keyword(s)
-o    At least one keyword present counts as a match.  [Default]
-a    All keywords must be present for a file to be considered a match
   -L    All keywords must be present on the same line (implies  -a )
-l    List matching files only; do not display/print
-n    Do not pause between viewing Markdown files
-p <directory to search for >
-C    Case sensitive search (default is insensitive)
-P    Do not use a pager ('less')

EOM
}

printTitle() {
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}


# -------------------------------
# Main Line
# -------------------------------

# Process script args/settings
path="$SearchPath"
FilenameSearch=false
NeedAllKeywords=false
NeedOnSameLine=false
ContentSearch=false
CaseSensitive=false
PauseInBetween=true
UsePager=true
ListOnly=false
while getopts ":hafcLlnop:CP" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		a) NeedAllKeywords=true ;;
		c) ContentSearch=true ;;
		f) FilenameSearch=true ;;
		L) NeedAllKeywords=true; NeedOnSameLine=true ;;
		l) ListOnly=true ;;
		n) PauseInBetween=false ;;
		o) NeedAllKeywords=false ;;
		p) path="$OPTARG" ;;
		C) CaseSensitive=true ;;
		P) UsePager=false ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

# Any leftover arguments are used as keywords
if [ $# -eq 0 ]; then
	echo 'You must supply at least 1 keyword to search for. Run with -h for help'
	exit 1
fi

# Ensure inputs are good
test -n "$path" -a -d "$path" -a -r "$path" || { echo "ERROR: '$path' is not a readable dir"; exit 1; }

# Test for mdv
hash mdv &>/dev/null || { echo "Error: command 'mdv' not present. Refer to: https://github.com/axiros/terminal_markdown_viewer"; exit 1; }

# Set all the flags/switches for our tools based on script call

if ! $ContentSearch ; then
	# If the grep content search wasn't explicitly requested, we default to filepath
	FilenameSearch=true
fi

if $CaseSensitive ; then
	caseFlag='' 
	findRegex='-regex'
	grepOpt=''
else
	caseFlag='i'
	findRegex='-iregex'
	grepOpt='--ignore-case'
fi

if $UsePager ; then
	finalCmd='less'
	finalCmdArgs='-R'
else
	finalCmd='cat'
	finalCmdArgs=''
fi


# -------------------------------
# Prepare the regex pattern to use for keywords
# -------------------------------
if $NeedAllKeywords ; then
	# When all keywords must exist, we use positive lookaheads for each keyword.
	# e.g. given the keywords 'proxy' & 'blender', the pattern will be:
	#	(?=[\d\D]*proxy)(?=[\d\D]*blender)
	# Supposedly, anchoring with '^' improves peformance. We add that on execution.
	# Explanation of the  sed  command:
	# 1. Trim whitespace from front and back, if any
	# 2. Capture each keyword and wrap it with positive lookahead syntax
	if $NeedOnSameLine ; then wildcard='.'; else wildcard='[\\d\\D]'; fi
	pattern="$( sed --regexp-extended '
		s/^ +| +$//g;
		s/([^ ]+)( +|$)/(?='"$wildcard"'*\1)/g;' <<< "$@" )"
else
	# When we can take any keyword, the regex is much simpler:  alternation.
	# e.g. given the keywords 'proxy' & 'blender', the pattern will be:
	#	(proxy|blender)
	# Explanation of the  sed  command:
	# 1. Trim whitespace from front and back, if any
	# 2. Replace every set of spaces with a single pipe
	# 3. Enclose everything in parentheses
	pattern="$( sed --regexp-extended '
		s/^ +| +$//g;
		s/ +/|/g; s/^/(/; s/$/)/' <<< "$@" )"
fi

# -------------------------------
# Summary of call to stderr
# -------------------------------

cat > /dev/stderr <<- EOM
	Path     : $path
	Keywords : $@
	[regex   : $pattern ]
	Require all keywords : $NeedAllKeywords
	... on same line     : $NeedOnSameLine
	Filepath search      : $ContentSearch
	Content search       : $ContentSearch
	Case sensitive       : $CaseSensitive
	List only            : $ListOnly

EOM

# -------------------------------
# Search for the files
# Use process substitution to feed the results of a 'find' command to
# 'readarray', which will place it all into a single array.
# When the more advanced patterns are used, we pass the intial output to Perl
# since 'find' cannot handle it.
# -------------------------------

if ! $ContentSearch ; then
	echo -n 'Searching for Markdown files to display by filename ... ' > /dev/stderr
	if $NeedAllKeywords ; then
		readarray -d $'\0' hits < <(
			find "$path" -follow -regextype 'posix-extended' -type f -iregex ".*\.(markdown|md)$" -print0 | perl -n -0 -e "print if (/^${pattern}/${caseFlag});"
		)
	else
		readarray -d $'\0' hits < <(
			find "$path" -follow -regextype 'posix-extended' -type f $findRegex ".*${pattern}.*\.(markdown|md)$" -print0
		)
	fi
else
	# If any keyword will do, we can simply pass the 'find' results to 'grep'.
	# Otherwise, we build up a Perl script to execute that will open every file
	# to check for the keywords.
	# (The '$/' is to read all contents into a single var.)
	echo -n 'Searching for Markdown files with the specified keywords ... ' > /dev/stderr
	if $NeedAllKeywords ; then
		readarray -d $'\0' hits < <(
			find "$path" -follow -regextype 'posix-extended' -type f -iregex '.*\.(markdown|md)' -print0 |
			xargs -0 perl <( cat <<- EndPerl
				foreach my \$filename (@ARGV)
				{
					open(FILE, "\$filename");
					local \$/ = undef;
					\$lines = <FILE>;
					close(FILE);
					print "\$filename\0" if (\$lines =~ /${pattern}/${caseFlag});
				}
				EndPerl
			)
		)
	else
		readarray -d $'\0' hits < <(
			find "$path" -follow -regextype 'posix-extended' -type f -iregex '.*\.(markdown|md)' -print0 |
			xargs -0 grep --null --files-with-matches --perl-regexp $grepOpt "$pattern"
		)
	fi
fi

# -------------------------------
# Handle the files found
# -------------------------------

echo "Found ${#hits[@]} files" > /dev/stderr
for (( i=0; i < ${#hits[@]}; i++ ))
do
	if $ListOnly ; then
		# write to stdout, as user may want to capture this
		echo "${hits[i]}"
	else
		if [ $PauseInBetween = true -a $i -gt 0 ] ; then
			echo "Next file: ${hits[i]}" > /dev/stderr
			echo "Press ENTER to continue or CTRL-C to cancel" > /dev/stderr
			read
		fi
		echo "Opening match $((i+1)): ${hits[i]}" > /dev/stderr
		mdv "${hits[i]}" | $finalCmd $finalCmdArgs
	fi
done


#EOF
