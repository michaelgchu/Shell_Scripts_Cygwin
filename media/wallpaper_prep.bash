#!/usr/bin/env bash
SCRIPTNAME='Wallpaper Image Preparation Script'
LAST_UPDATED='2022-01-09'
# Author: Michael Chu, https://github.com/michaelgchu/
# See Usage() for purpose and call details
# Tested in Cygwin64 and Linux.

#-------------------------------------------------------------------------------
# Script requirements
#-------------------------------------------------------------------------------
# What tools the script needs, as an associative array that hopefully can help
# point the user to where to grab them.  The script aborts if any is not found
declare -A required_tools
required_tools['heif-convert']='"libheif-examples" or "libheif-tool" package'
required_tools['exiftool']='https://www.exiftool.org/'
#required_tools['exiftran']='"exiftran" package'
required_tools['ffmpeg']='"ffmpeg" package'

# One of these 2 is required: prefer exiftran
declare -A reqtool_rotate
reqtool_rotate['exiftran']='"exiftran" package'
reqtool_rotate['jpegtran']='"jpeg" package'

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------

Usage() {
	printTitle
	cat << EOM
Usage: ${0##*/} [options]

This script prepares all the HEIF (.heic) & JPEG (.jpg) files in the directory
for use as desktop wallpapers, saving the final images in JPEG format.
Sometimes image files have the *wrong* orientation metadata, which causes
improper rotation in the output. Since the results are JPEG, it should be
simple to use your system's image viewer to review and update the
orientation/rotation metadata of the generated files.

The processing steps:
- find all the images to process
- convert .heic to .jpg, as required (for compatibility with tools)
- rotate as indicated by the 'Orientation' EXIF metadata, if present
- shrink down to a maximum height
- save resulting image to a destination folder

OPTIONS
=======
   -h    Show this message
   -m max_height
	 The maximum height for the output images, after rotation. Any images
	 exceeding this value will get shrunken down. ($max_height)
   -i input_folder
	 The folder containing images to process.
         ($(readlink --canonicalize "$input_folder"))
   -s    Process images in subfolders too.
         Note: all output files get saved to a single folder
   -o output_folder
	 The folder to write all processed images to.
         ($(readlink --canonicalize "$output_folder"))
   -c    Clobber (overwrite) any existing output file.

EOM
}

printTitle()
{
	echo "${underline}$SCRIPTNAME ($LAST_UPDATED)${normal}"
}


#-------------------------------------------------------------------------------
# Prepare for displaying terminal colours
# https://unix.stackexchange.com/questions/9957/how-to-check-if-bash-can-print-colors
#-------------------------------------------------------------------------------
if [ "$(tput colors)" -ge 8 ]; then
	bold="$(tput bold)"   ; underline="$(tput smul)"
	red="$(tput setaf 1)" ; yellow="$(tput setaf 3)"
	normal="$(tput sgr0)"
fi


#-------------------------------------------------------------------------------
# Main Line
#-------------------------------------------------------------------------------
# Process script args/settings
# max_height    : If any images exceed this height, they are resized to match it
max_height=1080
# input_folder  : The folder with image files to process
input_folder='.'
# output_folder : The folder to write the prepared files into
output_folder='./prepared'
# Subfolders    : whether to process subfolders of the input folder
Subfolders=false
# SkipExisting  : whether to skip/overwrite existing output files
SkipExisting=true
while getopts ":hm:i:so:c" OPTION
do
	case $OPTION in
		h) Usage; exit 0 ;;
		m) max_height=$OPTARG ;;
		i) input_folder=$OPTARG ;;
		s) Subfolders=true ;;
		o) output_folder=$OPTARG ;;
		c) SkipExisting=false ;;
		*) echo "${yellow}Warning: ignoring unrecognized option -$OPTARG${normal}" ;;
	esac
done
shift $(($OPTIND-1))

# Check that all required tools are available
flagCmdsOK='yes'
for cmd in ${!required_tools[@]}
do
	hash $cmd &>/dev/null || { echo "${red}Error: command '$cmd' not present.${normal} Possible source: ${required_tools[$cmd]}"; flagCmdsOK=false; }
done
# Abort if anything is missing
test $flagCmdsOK = 'yes' || exit 1
# Similarly, check for the rotation tool - need at least 1
flagCmdsOK=false
for cmd in ${!reqtool_rotate[@]}
do
	hash $cmd &>/dev/null && { rotator=$cmd; flagCmdsOK='yes'; }
done
# Abort if anything is missing
if [ $flagCmdsOK = false ] ; then
	echo "${red}Error: no JPEG rotation tool available.${normal} Need one of:"
	for cmd in ${!reqtool_rotate[@]} ; do
		echo -e "$cmd\t${reqtool_rotate[$cmd]}"
	done
fi

# Check & process script settings
test -z $(tr -d [:digit:] <<< $max_height) || { echo "${red}ERROR: max height must be a number${normal}"; exit 1; }
canon_if=$(readlink --canonicalize "$input_folder")
test -e "$canon_if" -a -d "$canon_if" || { echo "${red}ERROR: input folder '$canon_if' is invalid.${normal}"; exit 1; }
canon_of=$(readlink --canonicalize "$output_folder")
test -e "$canon_of" -a -d "$canon_of" || { echo "${red}ERROR: output folder '$canon_of' is invalid.${normal} Create it, or specify a folder using -o option."; exit 1; }
test "$canon_if" = "$canon_of" && { echo "${red}Sorry, input and output folders are the same!${normal}"; exit 1; }
if $Subfolders ; then
	desc_sub=' (including subfolders)'
	find_opt=
else
	desc_sub=
	find_opt='-maxdepth 1'
fi

# Confirm selection with the user
printTitle
cat << EOM
The processing steps to execute:
- find all the images to process in${desc_sub}:
 '${bold}$canon_if${normal}'
- convert .heic to .jpg, as required (JPEG is better supported by the tools)
- rotate as indicated by the 'Orientation' EXIF metadata, if present (using $rotator)
- shrink down to a maximum height of ${bold}$max_height${normal} px
- save resulting image to a destination folder:
 '${bold}$canon_of${normal}'

EOM
read -p 'Press ENTER to continue, or CTRL-C to cancel now ' confirm
echo

#-------------------------------------------------------------------------------
# Perform processing
#-------------------------------------------------------------------------------
# Create temp files, with .jpg extensions so the tools don't barf on us
trap 'rm -rf "$buffer1" "$buffer2"' EXIT
buffer1=$(mktemp --suffix=.jpg) || { echo 'ERROR: cannot create temp/buffer file'; exit 1; }
buffer2=$(mktemp --suffix=.jpg) || { echo 'ERROR: cannot create temp/buffer file'; exit 1; }

# Get total files to process (using same basic find command as below)
total=$(find "$canon_if" $find_opt -regextype posix-extended -type f -iregex '.*(jpe?g|heic)' -printf '1\n' | wc -l)
echo -e "Folder has $total image files to process.\n"

# Process any files with extensions: jpg; jpeg; heic
# Coding note: the pipe between find & while spawns a subshell, so changes to
# tally variables are not observed after the loop ends. The solution: "attach"
# the final echo commands to the subshell by introducing parentheses.
# https://serverfault.com/questions/259339/bash-variable-loses-value-at-end-of-while-read-loop
current=1 ; skipped=0 ; errors=0
find "$canon_if" $find_opt -regextype posix-extended -type f -iregex '.*(jpe?g|heic)' -printf '%P\0%f\0' | (
while read -d $'\0' fp ; do
	read -d $'\0' fn # Grab the filename from the  find  listing
	echo -e "$current/$total\t$fp"
	current=$((current + 1))
	# Determine image file type and set the output filename
	ftype=$(file --brief "$canon_if/$fp")
	if [[ "$ftype" =~ 'JPEG image data' ]] ; then
		infile_metadata="$canon_if/$fp" ; outfile=$fn
	elif [[ "$ftype" =~ 'HEIF Image' ]] ; then
		infile_metadata="$buffer1" ;      outfile="${fn}.jpg"
	else
		echo -e "${yellow}\t\tUNKNOWN type: $ftype${normal}"
		skipped=$((skipped + 1))
		continue
	fi
	# And also set final output filepath here
	final_outfile="$canon_of/$outfile"

	# Check if we should skip this file
	if [ -e "$canon_of/$outfile" -a $SkipExisting = true ] ; then
		echo -e "${yellow}\t\tSKIP EXISTING output file: $outfile${normal}"
		skipped=$((skipped + 1))
		continue
	fi

	# Convert HEIF to JPEG if required
	if [[ "$ftype" =~ 'HEIF Image' ]] ; then
		# Must convert to JPEG before passing to exiftran. It ought to keep EXIF data
		echo -e '\t\tconverting to JPEG'
		heif-convert "$canon_if/$fp" "$buffer1" >/dev/null
		test $? -eq 0 || { echo -e "${red}\t\tERROR converting!${normal}"; errors=$((errors + 1)); continue; }
	fi

	# Perform the image rotation, IF there is metadata available.
	# Use exiftool for this step, which allows us to go directly to jpegtran if that is the rotation tool
	# NOTE 2: (Jan2022) ffmpeg will not apply rotation -- or at least, not
	# when using the parameters below
	# https://jdhao.github.io/2019/07/31/image_rotation_exif_info/
	orientation=$(exiftool -n -Orientation "$infile_metadata" | cut -f2 -d: | tr -dc [:digit:] )
	if [ -n "$orientation" ] ; then
		if [ $orientation -eq 1 ] ; then
			infile_ffmpeg="$infile_metadata"
		else
			echo -e '\t\tapplying rotation from EXIF metadata'
			if [ $rotator = 'exiftran' ] ; then
				# Perform auto-rotation using exiftran
				exiftran -a -o "$buffer2" "$infile_metadata"
				test $? -eq 0 || { echo -e "${red}\t\tERROR rotating!${normal}"; errors=$((errors + 1)); continue; }
			else
				# Rotate using jpegtran - must map exiftool output
				# https://exiftool.org/forum/index.php?topic=2178.0
				case $orientation in 
					2) opt='-flip horizontal' ;;
					3) opt='-rotate 180' ;;
					4) opt='-flip vertical' ;;
					5) opt='-transpose' ;;
					6) opt='-rotate 90' ;;
					7) opt='-transverse' ;;
					8) opt='-rotate 270' ;;
					*) echo -e "${yellow}\t\tUNKNOWN exiftool rotation value: $orientation${normal}"; skipped=$((skipped + 1)); continue; ;;
				esac
				jpegtran -copy all $opt -outfile "$buffer2" "$infile_metadata"
				test $? -eq 0 || { echo -e "${red}\t\tERROR rotating!${normal}"; errors=$((errors + 1)); continue; }
			fi
			infile_ffmpeg="$buffer2"
		fi
	else
		# No orientation info - move on to resize
		infile_ffmpeg="$infile_metadata"
	fi

	# Grab (new) dimensions, to decide if resizing is required based on height
	height=$(exiftool -ImageHeight "$infile_ffmpeg" | cut --fields=2 --delimiter=: | tr -d ' ')
	if [ "$height" -gt "$max_height" ] ; then
		echo -e "\t\tresizing down from $height"
		if [ $OSTYPE = 'cygwin' ] ; then
			# If this is Cygwin, convert the input and output filepaths to Windows
			# (because it's very possible that ffmpeg is a Windows based command)
			infile_ffmpeg=$(cygpath --absolute --windows "$infile_ffmpeg")
			final_outfile=$(cygpath --absolute --windows "$final_outfile")
		fi
		# This command sometimes consumes characters from stdin, so use -nostdin to prevent that
		ffmpeg -y -nostdin -hide_banner -loglevel error \
			-i "$infile_ffmpeg" \
			-vf "scale=-1:$max_height" "$final_outfile"
		test $? -eq 0 || { echo -e "${red}\t\tERROR resizing!${normal}"; errors=$((errors + 1)); continue; }
	else
		cp "$infile_ffmpeg" "$final_outfile"
		test $? -eq 0 || { echo -e "${red}\t\tERROR copying!${normal}"; errors=$((errors + 1)); continue; }
	fi
done

echo "${underline}${bold}Summary:${normal}"
echo "$((total - errors - skipped)) files processed."
test $skipped -gt 0 && echo "$skipped files skipped."
test $errors  -gt 0 && echo "$errors files had problems."
)

#EOF
