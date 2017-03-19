#!/usr/bin/env bash
SCRIPTNAME='Cut Video on Keyframe, Stream Copy'
LAST_UPDATED='2017-03-13'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() function for purpose and calling details
#
# Change Log
# ==========
# 2017-03-13
# - First working version

# -------------------------------
# "Constants" and globals
# -------------------------------

DEV_MODE=false

# Listing of all required tools.  The script will abort if any cannot be found
requiredTools='ffmpeg ffprobe mktemp cygpath'

# -----------------------------------------------------------------
# General Functions
# -----------------------------------------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/} [options]

Extracts the specified time range from the provided video.  The starting point
is set as the keyframe just before the provided start time, so that the video
playback looks fine right from the start.

The start & end times can be provided as straight seconds, or as  hh:mm:ss
You can specify multiple ranges by listing them out comma-delimited.  In this
case, the provided output filename becomes a base and the clip numbers and time
ranges are added to it.
e.g. Given  -o out.mp4  -r 11:30-21:45,33:00-34:59
the script will create files:
	out_01_1130-2145.mp4
	out_02_3300-3459.mp4

The 'ffprobe' tool is used to analyze the file.
The 'ffmpeg' tool is used to perform the stream copy clip extraction.

Results are decent when played in VLC, but Windows Media Player does funny
things.  Things are less impressive when you concatenate the outputs.

Syntax:
   ${0##*/} [options]

OPTIONS
=======
   -h    Show this message
*  -i 'input_video_file'
*  -o 'output_video_file.ext'
         Note the extension/container chosen should be the same as the input
*  -r startTime-endTime
         e.g.  -r 11:30-21:45
         e.g.  -r 11:30-21:45,33:00-34:59
   -c    Concatenate the separate ranges into a single output video file
   -y    Overwrite output file without prompting
   -q    Make ffmpeg (more) quiet
   -C    Show the ffmpeg/ffprobe Commands executed
   -D    DEV/DEBUG mode on

EOM
}


Cleanup()
{
	if $DEV_MODE ; then
		cat << EOM
[Not removing temporary files:
tfFramelist  = $tfFramelist
tfConcatlist = $tfConcatlist
]
EOM
	else
		rm -f "$tfFramelist" "$tfConcatlist"
	fi
}
tfFramelist=''		# lists out the frames in the source file
tfConcatlist=''		# lists out the video files to concatenate


secondsToHHMMSS()
{
# Given a time in seconds, output as HH:MM:SS
	date --date="1970-01-01 + $1 seconds" +%H:%M:%S
}


debugsay() {
	test $DEV_MODE = true && echo -e "[ $* ]" >/dev/stderr
}


printTitle() {
	title="$SCRIPTNAME ($LAST_UPDATED)"
	echo "$title"
	printf "%0.s-" $(seq 1 ${#title})
	echo 
}


# ************************************************************
# Begin Main Line
# ************************************************************

# Process script args/settings
src=''
dst=''
range=''
runOptions=''
ConcatFiles=false
ShowCommands=false
while getopts ":hi:o:r:cyqCD" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		i) src="$OPTARG" ;;
		o) dst="$OPTARG" ;;
		r) range="$OPTARG" ;;
		y) runOptions="$runOptions -y" ;;
		q) runOptions="$runOptions -v error" ;;
		c) ConcatFiles=true ;;
		C) ShowCommands=true ;;
		D) test $DEV_MODE = true && set -x || DEV_MODE=true ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

# Ensure all required args are provided
test -n "$src" -a -n "$dst" -a -n "$range" || { echo 'Must supply all mandatory run options. Run with -h for usage info.'; exit 1; }
# Test input & outputs.
test -r "$src" -a -f "$src" || { echo "Error: '$src' is not a readable file."; exit 1; }
test "$src" != "$dst" || { echo "Error: input cannot be output"; exit 1; }
test -e "$dst" -a ! -f "$dst" && { echo "Error: '$dst' exists and is not a file."; exit 1; }

# Test for all required tools/resources
debugsay "Testing for required command(s): $requiredTools"
flagCmdsOK='yes'
for cmd in $requiredTools
do
	hash $cmd &>/dev/null || { echo "Error: command '$cmd' not present"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || exit 1

printTitle


# Split the provided arg into an array of ranges, 1-based index
readarray -O 1 -t arrRanges <<- EOD
	$(echo $range | tr --squeeze ',' '\n' )
EOD
totalClips=${#arrRanges[@]}

# Split out the output filename into base and extension, if multiple clips are to be created
if [ $totalClips -gt 1 ] ; then
	outBase=$(sed --regexp-extended 's/\.[^.]+$//' <<< $dst)
	outExt=${dst##*.}
	test -n "$outBase" -a -n "$outExt" || { echo "Error: could not split video output name '$dst' into base and extension"; exit 1; }
	test $ConcatFiles = false && dst="${outBase}_<clip#>_<startTime>-<endTime>.$outExt"
fi

# Get input clip duration and start time
srcMetadata=$(ffprobe -hide_banner -i "$src" 2>&1 |
	grep --only-matching --perl-regexp 'Duration.*, start: [0-9]+\.?[0-9]*'
)
srcDuration=$(cut -f2 -d' ' <<< $srcMetadata | tr -d ',')
srcStarttime=$(cut -f4 -d' ' <<< $srcMetadata)

cat <<- EOM
	Input video file      : $src ($srcDuration)
	Output video file     : $dst
	# clips to extract    : $totalClips
	Concatenate results   : $ConcatFiles
EOM

# -------------------------------
# Test the provided range(s) before moving on to the time-consuming video frame probing
# Note: these functions will be used again after all the probing
# -------------------------------

AnalyzeRange()
{
# Split the provided range into start and end times, and then determine those times in straight seconds
	readarray -t times <<- EOD
		$(echo $1 | tr --squeeze ' -' '\n' )
	EOD
	sTime=${times[0]}
	eTime=${times[1]}
	test -n "$sTime" -a -n "$eTime" || { echo "Error: bad range syntax.  See  -h  for help"; exit 1; }
	startSecs=$(timeToSeconds "$sTime")
	endSecs=$(timeToSeconds "$eTime")
}

timeToSeconds()
{
# Calculate time in seconds by summing pieces from small to large (s, m, h)
# e.g. 0:10:05 == 605 seconds
	awk -F: '{
		s = e = 0;
		while (NF) {
			s += $NF * 60**e;
			e++;
			NF--;
		}; 
		print s }' <<< "$1"
}

echo -e '\nChecking supplied ranges before proceeding with video frame probing...'

for (( i=1; i <= $totalClips; i++ ))
do
	debugsay "Testing range $i == ${arrRanges[$i]}"
	AnalyzeRange "${arrRanges[i]}"
	test $startSecs -lt $endSecs || { echo "Error: start time '$sTime' must be less than end time '$eTime'"; exit 1; }
done


# -------------------------------
# Set up temporary files
# -------------------------------

debugsay "Preparing temp file(s)"
trap Cleanup EXIT
tfFramelist=$(mktemp) || { echo 'Error: could not create temporary file'; exit 1; }
if $ConcatFiles ; then
	tfConcatlist=$(mktemp) || { echo 'Error: could not create temporary file'; exit 1; }
fi


# -------------------------------
# Analyze video: extract out keyframes, so we can identify frame to start (each) clip at
#
# Initially I thought that keyframes could be identified by doing: 
#	ffprobe -show_frames -select_streams v:0 -of csv "$src" | grep 'frame,video,0,1'
# Seems that's not quite the case.  Based on this reference, we just need to add  -skip_frame nokey  to get a list of just proper keyframes.  And it's faster too
#	https://github.com/mifi/lossless-cut/pull/13
# -------------------------------

echo -e '\nExtracting a list of all keyframes from source file ...'
(
	test $ShowCommands = true && set -x
	ffprobe -hide_banner -v error -show_frames -select_streams v:0 -skip_frame nokey -of csv -i "$src" |
       		grep ',I,' |
	       	cut -f6 -d, > "$tfFramelist"
)
if [ ! -s "$tfFramelist" ] ; then
	echo "Error: could not extract frame listing using 'ffprobe'"
       	exit 1
fi

if $DEV_MODE ; then
	debugsay 'First 10 keyframes timestamps:'
	head "$tfFramelist"
fi


# -------------------------------
# Process each provided range
# -------------------------------

debugsay "Process each of the $totalClips clips/ranges"

unset arrDelete	# unset this, as we'll be potentially using it to delete files later

for (( i=1; i <= $totalClips; i++ ))
do
	AnalyzeRange "${arrRanges[i]}"
	if [ $totalClips -gt 1 ]; then
		# Prepare filename for this clip.  Strip colons out, since they might cause issues
		dstClip=$(tr -d ':' <<< "${outBase}_$(printf %02d $i)_${sTime}-${eTime}.$outExt")
		if $ConcatFiles ; then
			# And then add it to the file listing if we must concatenate later
			sed --regexp-extended "s/^/file '/; s/$/'/" <<< "$dstClip" >> "$tfConcatlist"
			# And record the name to an array for easy deletion
			arrDelete[$i]="$dstClip"
		fi
	else
		dstClip="$dst"
	fi
	cat <<- EOM
		
		Clip #                      : $i
		Output filename             : $dstClip
		Start time                  : $sTime (${startSecs}s)
		End time                    : $eTime (${endSecs}s)
	EOM

	# Select keyframe by taking the one that is just before the start time
	kfStart=$(awk -F, -v matchTo=$startSecs '
		BEGIN { prev=0 }
		{
			if ($0 > matchTo)
			exit;
			prev = $0;
		}
		END { print prev }' "$tfFramelist")
	duration=$(awk '{ printf "%0d", $2 - $1 }' <<< "$kfStart $endSecs")
	echo "Keyframe-aligned start point: $kfStart"
	echo "Clip duration               : $(secondsToHHMMSS $duration) (${duration}s)"


	# And it's a relatively normal ffmpeg call from here:
	echo 'Calling FFmpeg to create the clip ...'
	(
	test $ShowCommands = true && set -x
	ffmpeg -hide_banner $runOptions -ss $kfStart -i "$src" -t $duration -c copy -map_metadata 0 "$dstClip"
	) || exit $?
done # looping through all the ranges

if $ConcatFiles ; then
# Not doing this, but doesn't seem to affect my tests:
# "If you cut with stream copy (-c copy) you need to use the -avoid_negative_ts 1 option if you want to use that segment with the ?concat demuxer."
	echo -e "\nConcatenating individual clips into final output file '$dst'"
	listToolPath="$(cygpath --absolute --windows "$tfConcatlist")"
	if $DEV_MODE ; then
		debugsay "Content of list to pass to 'concat' operation:"
		cat "$tfConcatlist"
	fi
	(
	test $ShowCommands = true && set -x
	ffmpeg -hide_banner $runOptions -f concat -i "$listToolPath" -c copy -map_metadata 0 "$dst"
	) || { echo 'ERROR - concatenation failed'; exit 1; }

	echo -e "\nDeleting individual clips"
	rm --verbose "${arrDelete[@]}"
fi

echo -e '\nScript finished successfuly.'

#EOF
