#!/usr/bin/env bash
SCRIPTNAME='Video re-encoder to x265 using FFmpeg'
LAST_UPDATED='2017-07-24'
SCRIPT_AUTHOR="Michael G Chu, https://github.com/michaelgchu/"
# See Usage() function for purpose and calling details
#
# The command that gets used is basically (plus or minus a few):
# ffmpeg -y -v error  -r <FPS> -i <inputFile> -c:v $encoder -preset $videoPreset -crf $videoCRF -r <FPS> -c:a copy -map_metadata 0 <OUTFILE>
#
# Updates
# =======
# 20170724
# - add option to set FPS
# 20161106
# - change output filename generation to allow for any extension, not just mp4/mov
# 20161021
# - Add test mode
# 20161016
# - make script more robust, provide more options
# 20160529
# - First version

set -u

# -------------------------------
# "Constants", Globals / Defaults
# -------------------------------

# What to add to the filename of the created file.  The script will ignore these as potential input files when scanning the folders
outputSuffix='-x265'

# Preset: 
# Testing (see script reencode_test.bash) shows that "veryfast" is always
# faster than "medium" and "veryslow", but additionally tends to have the
# smaller file size too.  From a visual quality perspective /overall size, the
# CRF setting has far more impact.
# Note that Handbrake (which seems to have its own take on ffmpeg) uses "veryfast"
videoPreset='veryfast'

# CRF, aka Constant Rate Factor:
# 28 is the default for HEVC/x265, and various testing shows that it is decent for (my) home videos.
# 23 is the default for x264.
videoCRF='28'

# FPS (Frames Per Second):
# Use the reported value from ffprobe
FPSDefault='same as input [avg_frame_rate as reported by ffprobe]'


DEV_MODE=false

# Listing of all required tools.  The script will abort if any cannot be found
requiredTools='ffmpeg ffprobe jq grep tr sed find'

# -------------------------------
# Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/}  [options]  [file(s) to process]

This script will re-encode video files using the HEVC/x265 encoder, which
should result in significant disk space savings.

You can supply the specific files to process on the command line.  Otherwise
the script will search the current folder tree for files that:
- have extension .mp4 or .mov
- file name portion does not end in '$outputSuffix'
- are not already encoded using x265

No files will be overwritten.

OPTIONS
=======
   -h    Show this message
   -c    Only process files in current folder, not any subfolders
   -n    Do not prompt before continuing
   -p preset
         Specify the preset. FFmpeg supports:
         veryfast, faster, fast, medium, slow, slower, veryslow
	 (Script default: $videoPreset)
   -q CRF
         Specify the Constant Rate Factor value. FFmpeg defaults to 28 for libx265
	 (Script default: $videoCRF)
   -r FPS
         Specify the FPS for the output video
	 (Script default: $FPSDefault)
   -t    Test only - show what the FFmpeg calls but don't execute them
   -Q    Make FFmpeg be Quiet, reporting only errors. (Note: it prints to stderr)
   -D    DEV/DEBUG mode on

EOM
}


# This function will be called on script exit, if required.
finish() {
	debugsay "Removing temporary files"
	rm -f "$buffer"
}
buffer=''



debugsay() {
	test $DEV_MODE = true && echo "[ $* ]" >/dev/stderr
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
DoPause=true
RestrictSearch=false
findOptions=''
PutASockInIt=false
ffmpegOptions='-hide_banner'
fpsToSet="$FPSDefault"
TestMode=false		# false == do call ffmpeg
while getopts ":hcnp:q:r:tQD" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		c)
			RestrictSearch=true
			findOptions='-maxdepth 1'
			;;
		n) DoPause=false ;;
		p) videoPreset="$OPTARG" ;;
		q) videoCRF="$OPTARG" ;;
		r) fpsToSet="$OPTARG" ;;
		t) TestMode=true ;;
		Q)
			PutASockInIt=true
			ffmpegOptions='-v error'
			;;
		D) test $DEV_MODE = true && set -x || DEV_MODE=true ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

debugsay "**DEBUG MODE enabled**"

printTitle
date

# Test for all required tools/resources
debugsay "Testing for required command(s): $requiredTools"
flagCmdsOK='yes'
for cmd in $requiredTools
do
	hash $cmd &>/dev/null || { echo "Error: command '$cmd' not present"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || {
	echo 'FFmpeg is available at:  https://www.ffmpeg.org/';
	echo 'jq is available at:      https://stedolan.github.io/jq/';
	exit 1;
}


if [ $# -gt 0 ] ; then
	debugsay 'Checking remaining arguments for input files to re-encode'
	trap finish EXIT
	buffer=$(mktemp) || { echo 'Error: could not create buffer file'; exit 1; }
	providedFiles=0
	while [ $# -gt 0 ]
	do
		if [ -e "$1" ] ; then
			if [ -f "$1" ] ; then
				echo "$1" >> "$buffer"
				providedFiles=$((providedFiles + 1))
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


cat << EOL

Call Summary
Arguments        : $args
Suffix to attach : $outputSuffix
Files to process : $(
	if $SearchingForFiles ; then
		test $RestrictSearch = true && echo 'searching current folder' || echo 'searching current folder & subfolders'
	else
		cat "$buffer"
	fi
)
--
Configuration for FFmpeg:
video library: libx265
video preset:  $videoPreset
CRF:           $videoCRF
FPS:           $fpsToSet
Audio:         copy stream
Test Mode:     $TestMode
Be Quiet:      $PutASockInIt

EOL

if $DoPause ; then
	echo "Press ENTER to continue, or CTRL-C to cancel"
	read
fi


# ************************************************************
# Main Line
# ************************************************************

tallyOK=0
tallyError=0
tallySkip=0

echo -e "\nProcessing begins at: $(date)"

while read filename
do
	echo -en "\nProcessing file '$filename' "
	outputName="$(sed --regexp-extended 's/\.[^.]+$/'$outputSuffix'.mp4/i' <<< "$filename")"
	if [ -e "$outputName" ] ; then
		echo "Note: destination file already exists.  Skipping"
		tallySkip=$((tallySkip+1))
		continue
	fi
	echo -n " --> '$outputName' "

	# Use 'ffprobe' to pull out details of this input video.  By specifying
	# JSON format, we can pick out exactly the details we are interested in
	# We use 'jq' to grab what we need - first focusing on the "streams"
	# array of data, selecting just the one with codec_type == "video", and
	# pull out 5 pieces from there
	# To allow for a Windows build of 'jq', we remove Carriage Returns
	readarray -t vidDetails <<- PROBINGO
	$(
		ffprobe -v quiet -print_format json -show_format -show_streams -i "$filename" |
		jq '.streams[] | 
			select(.codec_type == "video") |
			.codec_name, .width, .height, .nb_frames, .avg_frame_rate' |
		tr -d '\r"'
	)
	PROBINGO
	if [ ${#vidDetails} -eq 0 ] ; then
		echo "Error while getting video metadata via ffprobe - moving on"
		tallyError=$((tallyError+1))
		continue
	fi
	if [ ${vidDetails[0]} = 'h265' -o ${vidDetails[0]} = 'hevc' ] ; then
		echo 'Note: this file is already HEVC/x265 encoded. Skipping'
		tallySkip=$((tallySkip+1))
		continue
	fi
	if [ -z "${vidDetails[4]}" -a "$fpsToSet" = "$FPSDefault" ] ; then
		echo "Error - could not determine FPS .. skipping"
		tallySkip=$((tallySkip+1))
		continue
	fi
	cat <<- VDEETS

		Video details:
		- Codec      : ${vidDetails[0]}
		- Dimensions : ${vidDetails[1]} x ${vidDetails[2]}
		- Framecount : ${vidDetails[3]}
		- FPS        : ${vidDetails[4]}
	VDEETS
	if [ "$fpsToSet" = "$FPSDefault" ] ; then
		fps=${vidDetails[4]}
	else
		echo "  (using     : $fpsToSet)"
		fps="$fpsToSet"
	fi

	# Finally, execute ffmpeg to perform the re-encoding
	# Do not need to call cygpath, at least not with version of ffmpeg I am currently using
	if $TestMode ; then
		echo "Test mode - file will not be processed  Command would have been:"
		echo ffmpeg $ffmpegOptions -r $fps -i "$filename" -c:v libx265 -preset $videoPreset -crf $videoCRF -r $fps -c:a copy -map_metadata 0 "$outputName"
	else
		ffmpeg $ffmpegOptions -r $fps -i "$filename" -c:v libx265 -preset $videoPreset -crf $videoCRF -r $fps -c:a copy -map_metadata 0 "$outputName"
		test $? -eq 0 && tallyOK=$((tallyOK+1)) || tallyError=$((tallyError+1)) 
	fi
done << FILE_LISTING
$(	# Supply filenames to the loop, one per line. Either via the 'find' command, or from the prepared text file
	if $SearchingForFiles ; then
		find . $findOptions -regextype posix-extended -iregex '.*\.(mp4|mov)' -not -iregex ".*${outputSuffix}\..{3}$"
	else
		cat "$buffer"
	fi
)
FILE_LISTING


# ************************************************************
# Run Summary
# ************************************************************

endDT="$(date)"

cat << END_SUMMARY

Processing ends at:   $endDT

Run summary:
- OK:    $tallyOK
- Error: $tallyError
- Skip:  $tallySkip
END_SUMMARY

if [ $((tallyError + tallySkip)) -gt 0 ] ; then
	exit 1
else
	exit 0
fi

#EOF
