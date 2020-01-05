#!/bin/bash
SCRIPTNAME='Media DateTime-Filename Checker'
LAST_UPDATED='2020-01-04'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details
#
# ffprobe is for videos only.  It can provide some info for image files, but not the Exif data where creation date is stored
# Neat:  the 'file' command can pull out datetime=....
#
# The commands used are basically:
#	find . -regextype posix-extended -iregex '.*[0-9]{4}(.)[0-9]{2}\1[0-9]{2}.[0-9]{2}(.)[0-9]{2}\2[0-9]{2}.*'
# For images:
#	Basic 'file' will provide creation datetime for JPEG
#	exiftool using arg -CreateDate for HEIF images
# For videos:
#	ffprobe -v quiet -print_format json -show_format -i INPUT | sed -nr '/md/ { s/^.*"([0-9]{4}-[0-9]{2}.*)".*$/\1/; p }'
#
# Updates (noteworthy)
# ====================
# 20200104
# - New feature: renaming of HEIF image formats (.HEIC)
# - Bug fix: correct how datetime metadata is pulled from iPhone videos
# - Code cleanup & Remove dev mode - to see all steps, run: bash -x <scriptname>
# 20170221
# - Change behaviour: prefer to pull datetime from filename; never rename based on file's modification date
# 20161016
# - Huge overhaul of script
# Started:  July 2012

set -u

# Make the =~ bash operator case insensitive
shopt -s nocasematch

# -------------------------------
# "Constants", Globals / Defaults
# -------------------------------

mylog="runlog-mediarenamer-$(date +%Y%m%d_%H%M%S).log"

# Listing of all required non-standard tools.  The script will abort if any cannot be found
requiredTools='exiftool ffprobe'

# -------------------------------
# General Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/}  [options]  [file(s) to process]

Rename all the image (JPEG/HEIF) & video (MP4/MOV) files in the current directory
tree to begin with their date/time stamp in the format:
	YYYY-MM-DD_HH-mm-ss
e.g.
	2012-02-19_19-32-22.jpg
It skips over files that are already named in this fashion.

Alternately, you can supply filenames to process on the command line.

If the media file already has a date & time as part of its filename, then this
is used to set the new filename, e.g. VID_20170102_194410.mp4
Otherwise, the date/time info is pulled from the file's metadata.

When called in 'Check mode' using option  -C, then it looks for files named
using this convention and ensures the date/time filename matches their
metadata.

A log file is created, i.e. "$mylog"

OPTIONS
=======
   -h    Show this message
   -c    Only process files in current folder, not any subfolders
   -C    Run in 'Check mode'
   -n    Do not prompt before continuing
   -t    Test only - show what will be done but do not actually rename

EOM
}


# This function will be called on script exit, if required.
finish() {
	# Removing temporary files
	rm -f "$buffer"
	test ! -s "$faillog" && rm "$faillog"
	test "$DontKillTheLog" = false && rm "$mylog"
}
buffer=''
faillog=''
DontKillTheLog=false


minFileDate()
{
# Given a file, return either the Creation or Modification date from stat, whichever is earliest
	timeBirth=$(stat -c '%W' "$1")
	timeMod=$(stat -c '%Y' "$1")
	test $timeBirth -lt $timeMod && lesser=$timeBirth || lesser=$timeMod
	date --date="@${lesser}" +'%Y-%m-%d_%H-%M-%S'
}


diffSeconds()
{
# Provide the difference between earlier date/time $1 and second date/time $2 in seconds
	s_starttime=$(date --date="$1" +%s)
	s_endtime=$(date --date="$2" +%s)
	echo $((s_endtime - s_starttime))
}

secondsToHHMMSS()
{
# Given a time in seconds, output as HH:MM:SS
	date --date="1970-01-01 + $1 seconds" +%H:%M:%S
}


log()
{
# Writes the given message to the log file
        echo -e "$*" >> "$mylog"
}

logecho()
{
        echo -e "$*" | tee -a "$mylog"
}

printTitle()
{
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}

# ************************************************************
# Reading script args & basic tests
# ************************************************************

args="$*"

# Process script args/settings
RestrictSearch=false	# false == search entire folder tree
CheckMode=false		# false == normal mode
DoPause=true		# true == prompt before starting
TestMode=false		# false == do rename files
while getopts ":hcCnt" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		c) RestrictSearch=true ;;
		C) CheckMode=true ;;
		n) DoPause=false ;;
		t) TestMode=true ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

if $RestrictSearch ; then
	findOptions='-maxdepth 1'
else
	findOptions=''
fi

printTitle
date

# Test for all required tools/resources
flagCmdsOK='yes'
for cmd in $requiredTools
do
	hash $cmd &>/dev/null || { echo "Error: command '$cmd' not present"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || exit 1

# It's a trap! ... to help with cleanup
trap finish EXIT

# Ensure we can write to the script's basic log file
touch "$mylog" || { echo "Error: cannot write to log file '$mylog'. Aborting"; exit 1; }

buffer=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
faillog=$(mktemp) || { echo "Error creating temporary file"; exit 1; }

# See if user has provided specific files to process
if [ $# -gt 0 ] ; then
	providedFiles=0
	while [ $# -gt 0 ]
	do
		if [ -e "$1" ] ; then
			if [ -f "$1" ] ; then
				if [ -r "$1" ] ; then
					echo "$1" >> "$buffer"
					providedFiles=$((providedFiles + 1))
				else
					echo "Note: '$1' is not readable; ignoring"
				fi
			else
				echo "Note: '$1' is not a file; ignoring"
			fi
		else
			echo "Note: '$1' does not exist; ignoring"
		fi
		shift
	done
	test $providedFiles -gt 0 || { echo "Error - none of the supplied command line arguments are files. Aborting"; exit 1; }
	SearchingForFiles=false
else
	SearchingForFiles=true
fi


printTitle > "$mylog"
echo "Log for run on:  $(date)" >> "$mylog"

cat << EOL | tee -a "$mylog"

Call Summary
------------
Executed in dir  : $(pwd)
Arguments        : $args
Files to process : $(
	if $SearchingForFiles ; then
		test $RestrictSearch = true && echo 'searching current folder' || echo 'searching current folder & subfolders'
	else
		cat "$buffer"
	fi
)

Check Mode       : $CheckMode $(
	if $CheckMode ; then
		echo ' - test files matching @@ YYYY-MM-DD_HH-mm-ss'
	fi
)
Test Mode        : $TestMode $(
	if $TestMode ; then
		echo " - files will not be renamed"
	fi
)

EOL

if $DoPause ; then
	echo "Press ENTER to continue, or CTRL-C to cancel"
	read
fi
DontKillTheLog=true


# ************************************************************
# Main Line
# Define a few functions and then get going
# ************************************************************

tallyOK=0
tallyError=0
tallySkip=0

startDT="$(date)"
logecho "Processing begins at: $startDT"


Set_Dir_Name_Ext()
{
	# Sets these values from the provided filepath
	dir=${1%/*}
	name=${1##*/}
	ext=${1##*.}
}


Analyze_File()
{
	# Identify the provided file's type, and then extract out its creation date/time metadata
	# Sets the following variables:
	#	fileType  category  method  md  dt
	# Returns 0/OK if we were able to pull out the 19-char date-time metadata (into  'md' )

	dt='N/A'

	# Use 'file' to determine if image or video (and therefore how to proceed)
	fileType=$(file --brief "$1")

	# Extract creation date/time from metadata based on file type.
	if [[ "$fileType" =~ HEIF.Image ]] ; then
		# The (new) HEIF image type. 'file' cannot extract its metadata
		category='image'
		method='exiftool'
		# Extract metadata key 'CreateDate' from the output of 'exiftool'
		# Metadata looks like this (the datetime stamp is identical to JPEG):
		#Create Date                     : 2019:12:26 19:17:48
		md=$(exiftool -CreateDate "$1" | sed --regexp-extended 's/^Create Date\s*:\s([0-9: ]{19}).*$/\1/')
	elif [[ "$fileType" =~ JPEG.image ]] ; then
		# JPEG Image type.  The 'file' output should already have the datetime stamp
		category='image'
		method='file'
		# Extract metadata key 'datetime' from the output of 'file'
		# Metadata looks like this:  datetime=2016:01:02 20:07:41
		md=$(sed --regexp-extended 's/^.*datetime=([0-9: ]{19}).*$/\1/' <<< "$fileType")
	elif [[ "$fileType" =~ movie|MP4 ]] ; then
		category='video'
		method='ffprobe'
		# Extract metadata key "com.apple.quicktime.creationdate" from the file, if available.
		# If not, fall back on 'creation_date', which exists in iPhone & Android videos.
		# 1) Use 'ffprobe' to pull out details of this input video.  JSON format is a bit cleaner
		# 2) Use sed to grab just the value.
		# The 'metadata' (md) element is in the format:  'YYYY-MM-DD HH:MM:SS'
		metadata=$(ffprobe -v quiet -print_format json -show_format -i "$1")
		srch_p='^.*"([0-9]{4})([:-])([0-9]{2})(\2)([0-9]{2}).([0-9.:-]{8}).*".*$'
		repl_p='\1\2\3\4\5 \6'
		md=$(sed --quiet --regexp-extended "/com.apple.quicktime.creationdate/ { s/$srch_p/$repl_p/; p }" <<< $metadata )
		if [ -z "$md" ] ; then
			md=$(sed --quiet --regexp-extended "/creation_time/ { s/$srch_p/$repl_p/; p }" <<< $metadata )
		fi
	else
		# Not recognized media file
		method='N/A'
		md='N/A'
		return 1
	fi
	if [ ${#md} -ne 19 ] ; then
		# Could not extract metadata; do retain the category detected
		return 1
	fi
	# Set var <dt>, which we use for naming the file
	dt="${md:0:4}-${md:5:2}-${md:8:2}_${md:11:2}-${md:14:2}-${md:17:2}"
	return 0
}


Build_Filepath()
{
	# Build out the full filepath for naming
	echo "${1}/${2}.${3}"
}



if $CheckMode ; then

	while read filepath
	do
		test -z "$filepath" && continue
		echo -en "\nInspecting file '$filepath' "
		Set_Dir_Name_Ext "$filepath"

		# Try to grab datetime metadata from file
		if Analyze_File "$filepath" ; then
			echo "$category "
			newName=$(Build_Filepath "$dir" "$dt" "$ext")
		else
			if [ "$method" = "N/A" ] ; then
				echo "-Unknown type. Skipping"
				log "$filepath : SKIP.  Reason: Unknown 'file' type"
				tallySkip=$((tallySkip+1))
			else
				echo "-metadata could not be extracted. Record as error"
				log "$filepath : ERROR.  Reason: Metadata could not be extracted"
				tallyError=$((tallyError+1))
			fi
			continue
		fi

		# Check the filename against the metadata, and correct if necessary
		# Build the pattern to check against.  Luckily, it's roughly the same coming out of file & ffprobe
		# Creation time = '2016-03-13 16:30:11'
		lookFor='/'$(tr ' :-' '.' <<< "$md")'[^/]+$'
		if [[ "$filepath" =~ $lookFor ]] ; then
			echo 'Check OK'
			log "$filepath : OK.  Reason: filename matches metadata creation date"
			tallyOK=$((tallyOK+1))
		else
			echo 'Not named properly'
			log "$filepath : Error.  Reason: filename does not match metadata creation time"
			if $TestMode ; then
				# Since this is test mode, just tally as error
				logecho "mv --no-clobber --verbose \"$filepath\" \"$newName\""
				tallyError=$((tallyError+1))
			else
				echo "Renaming"
				if [ -e "$newName" ] ; then
					echo "$filepath: SKIP.  Reason: file '$newName' already exists"
					tallySkip=$((tallySkip+1))
				else
					mv --no-clobber --verbose "$filepath" "$newName" 2>&1 | tee -a "$mylog"
					test ${PIPESTATUS[0]} -eq 0 && tallyOK=$((tallyOK+1)) || tallyError=$((tallyError+1))
				fi
			fi
		fi

	done <<- FILE_LISTING
	$(	# Supply filenames to the loop, one per line. Either via the 'find' command, or from the prepared text file
		if $SearchingForFiles ; then
			# Find files that are named like 'YYYY-MM-DD_HH-MM-SS[optional extra stuff].ext'
			find . $findOptions -regextype posix-extended \
				-iregex '^.*/[0-9]{4}(.)[0-9]{2}\1[0-9]{2}.[0-9]{2}(.)[0-9]{2}\2[0-9]{2}[^/]*$'
		else
			cat "$buffer"
		fi
	)
	FILE_LISTING


else	# Normal non-Check Mode


	while read filepath
	do
		test -z "$filepath" && continue
		echo -en "\nInspecting file '$filepath' "
		Set_Dir_Name_Ext "$filepath"

		# Extract the date+time out of the filename, if we can identify that
		dtFromName=$(sed --regexp-extended 's/^.*\/[^/]*([0-9]{4}).?([01][0-9]).?([0-3][0-9]).?([0-2][0-9]).?([0-5][0-9]).?([0-5][0-9]).*$/\1-\2-\3_\4-\5-\6/' <<< "$filepath")
		if [ "$dtFromName" != "$filepath" ] ; then
			echo "datetime found in name = $dtFromName"
			newName=$(Build_Filepath "$dir" "$dtFromName" "$ext")
		else
			# Couldn't.  Now try to grab datetime metadata from file
			if Analyze_File "$filepath" ; then
				echo "$category "
				newName=$(Build_Filepath "$dir" "$dt" "$ext")
			else
				if [ "$method" = "N/A" ] ; then
					echo "-Unknown type. Skipping"
					log "$filepath : SKIP.  Reason: Unknown 'file' type"
					tallySkip=$((tallySkip+1))
				else
					echo "-metadata could not be extracted. Record as error"
					log "$filepath : ERROR.  Reason: Metadata could not be extracted"
					tallyError=$((tallyError+1))
				fi
				continue
			fi

		fi

		if $TestMode ; then
			logecho "mv --no-clobber --verbose \"$filepath\"\t\"$newName\""
		else
			if [ -e "$newName" ] ; then
				logecho "$filepath: SKIP.  Reason: file '$newName' already exists"
				tallySkip=$((tallySkip+1))
			else
				mv --no-clobber --verbose "$filepath" "$newName" 2>&1 | tee -a "$mylog"
				test ${PIPESTATUS[0]} -eq 0 && tallyOK=$((tallyOK+1)) || tallyError=$((tallyError+1))
			fi
		fi

	done <<- FILE_LISTING
	$(	# Supply filenames to the loop, one per line. Either via the 'find' command, or from the prepared text file
		if $SearchingForFiles ; then
			# Assign a regex to find JPEG and MP4/MOV files that are NOT named like 'YYYY-MM-DD_HH-MM-SS[optional extra stuff].ext'
			find . $findOptions -regextype posix-extended \
				-iregex '.*(jpe?g|heic|mp4|mov)$' -and ! -iname '????-??-??_??-??-??*'
		else
			cat "$buffer"
		fi
	)
	FILE_LISTING

fi	# end branch between Check and non-Check Mode


endDT="$(date)"

cat << END_SUMMARY | tee -a "$mylog"

Processing ends at:   $endDT
Execution duration:   $(secondsToHHMMSS `diffSeconds "$startDT" "$endDT"` )

Run summary:
- OK:    $tallyOK
- Error: $tallyError
- Skip:  $tallySkip

Log file generated: $mylog
END_SUMMARY

if [ $tallyError -ne 0 -o $tallySkip -ne 0 ] ; then
	exit 1
else
	exit 0
fi

#EOF
