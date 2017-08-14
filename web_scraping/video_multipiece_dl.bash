#!/usr/bin/env bash
SCRIPTNAME='Multipiece Video Downloader (m3u8)'
LAST_UPDATED='2017-08-13'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
#
# References:
# https://gist.github.com/flyswatter/7357098
#
# Updates
# =======
# 2017-08-13:
# - First released version

# -------------------------------
# "Constants", Globals
# -------------------------------

set -u  # abort if trying to use an unset variable

Default_Filename='output.mp4'
dlM3U8='downloaded.m3u8'
localM3U8='local.m3u8'

requiredTools='curl ffmpeg'

# -------------------------------
# Functions
# -------------------------------

Usage()
{
	printTitle
	cat << EOM
Usage: ${0##*/} [options] [URL]

Given the URL to a  .m3u8  file, this script will attempt to download
all the video pieces and then combine them into a single video file.

You can get the URL by activating your browser's "Developer Tools"
prior to navigating to the page that has the embedded video.

OPTIONS
=======
   -h    Show this message
   -n    Do not prompt before overwriting the final output file
   -o <filename>
         The name of the video file to save.  By default, the script
         will try to use the base filename seen in the .m3u8 list, and
         falls back on '$Default_Filename' as a last resort.
   -K    Keep all the individual video segments and the .m3u8 files.
         By default, the script deletes them on completion.

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
OutputFilename=''
FFmpegOptions=''
KeepTempfiles=false
while getopts ":hno:K" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		n) FFmpegOptions="$FFmpegOptions -y";;	# -y = do not prompt
		o) OutputFilename="$OPTARG" ;;
		K) KeepTempfiles=true ;;
		*) echo "Warning: ignoring unrecognized option -$OPTARG" ;;
	esac
done
shift $(($OPTIND-1))

# Test for all required tools/resources
flagCmdsOK='yes'
for cmd in $requiredTools
do
	hash $cmd &>/dev/null || { echo "Error: command '$cmd' not present"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || { echo "Aborting"; exit 1; }


# -------------------------------
# Get & process the URL to the .m3u8 file
# This includes creating a copy that uses local filenames (for FFmpeg)
# -------------------------------

if [ $# -eq 1 ] ; then
	urlM3U8="$1"
else
	echo "Enter the URL of the  .m3u8  file for the video:"
	read urlM3U8
	test -n "$urlM3U8" || { echo 'Exiting script'; exit 1; }
fi

echo -e "m3u8 URL:\n$urlM3U8"
if ! [[ "$urlM3U8" =~ ^https?:\/\/ ]] ; then
	echo 'WARNING: does not start with "http://"'
fi

echo "Base URL for video segments:"
urlBase="${urlM3U8%/*}"
echo $urlBase

echo -e '\nDownloading the  .m3u8  file ...'
curl "$urlM3U8" > "$dlM3U8" || { echo 'Error downloading  .m3u8  file!'; exit 1; }

# Perform super basic check of file
if [ "$(head -1 "$dlM3U8")" != '#EXTM3U' ] ; then
	echo -e "\nThe downloaded file, '$dlM3U8', does not appear to be a proper M3U file."
	echo "First 10 lines:"
	head -10 "$dlM3U8"
	echo -e "\nAborting"
	exit 1
fi

totalPieces=$(grep --count --invert '^#' "$dlM3U8")
echo -e "\nVideo is composed of $totalPieces pieces to download\n"

echo -e '\nCreating copy of  .m3u8  file with local filenames (for FFmpeg) ...'
# Note we must keep all the comments, as these are required for FFmpeg to process it
cut -f1 -d'?' < "$dlM3U8" > "$localM3U8" || { echo 'Error creating copy!'; exit 1; }


# -------------------------------
# Download the video piece by piece
# -------------------------------

i=1
while read partialURL
do
	fullURL="${urlBase}/${partialURL}"
	# Extract the filename, which contains the timecode bit
	filename="${partialURL%\?*}"
	timebit=$(grep --perl-regexp --only-matching '\+[0-9]+\.ts' <<< "$filename")
	if [ -e "$filename" ] ; then
		echo "Piece $i of $totalPieces ($timebit) already exists.  Skipping ..."
	else
		echo "Downloading $i of $totalPieces ($timebit):"
		# If curl is set to auto-resume partial transfers, it will fail if the server doesn't support that.
		# (options would be: '--output <filename>'  & <--continue-at -> )
		# Instead, we will use the shell's trap ability to catch the signal so curl can error out
		trap 'echo -e "\n^C Interrupt caught"' SIGINT
		curl --output "$filename" "$fullURL" || {
			echo 'Error downloading - removing failed video piece and aborting!';
			rm --force "$filename"
			exit 1;
		}
	fi
	i=$((i + 1))
done <<- EOD
	$(grep --invert '^#' "$dlM3U8")
EOD
echo -e '\nAll video pieces downloaded.'


# -------------------------------
# Merge into a single video file
# -------------------------------

if [ -z "$OutputFilename" ] ; then
	# Extract out final filename. Default to $Default_Filename
	OutputFilename=$(sed --regexp-extended 's/\+[0-9]+\.ts$//' <<< "$filename")
	if [ "$OutputFilename" = "$filename" ] ; then
		echo -e "\nCannot identify final filename.  Defaulting to 'output.mp4'"
		OutputFilename="$Default_Filename"
	else
		echo -e "\nFinal video file = '$OutputFilename'"
	fi
fi

# Performing the merge
# The -bsf option is required, otherwise the process fails
echo -e "\nMerging all pieces into a single output file using FFmpeg ..."
ffmpeg -hide_banner $FFmpegOptions -i "$localM3U8"  -c copy -bsf:a aac_adtstoasc "$OutputFilename" || { echo 'Merge failed!'; exit 1; }
echo -e "\nVideo file '$OutputFilename' generated."


# -------------------------------
# Cleanup
# -------------------------------

if $KeepTempfiles ; then
	echo -e "\nKeeping all temporary files, including the two  .m3u8  listings."
else
	echo -e "\nDeleting all temporary files ..."
	while read fn
	do
		rm "$fn"
	done <<- EOD
		$(grep --invert '^#' "$localM3U8")
		$localM3U8
		$dlM3U8
	EOD
fi

echo -e "\nScript completed."

#EOF
