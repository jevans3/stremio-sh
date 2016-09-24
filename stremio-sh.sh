#!/bin/bash
# TODO:
# check for double symllinks with find -L . -samefile ~/.config/stremio/stremio-cache/a26c30516417c5c0dad9a166cfbb9f57c721f930/12
# if clean_old_symlinks then .. get next guid! (check modify date)
# wait option -w waiting for new symlink to create. Test modify date!
# Put main script in a function main(), so exit function can be placed at the bottom of the script
# Auto detect current User

# HISTORY:
# version="1.04.2016-07-25" # initial
# version="1.05.2016-08-21" # getFileNameNr() bug fixed, list -t sorting on modify date added
# version="1.06.2016-08-24" # getAllSymlinks() test added
# version="1.07.2016-09-01" # rename functions properly change get_newest_guid() added -l (list) and -d (delete) options
# version="1.08.2016-09-02" # add -r #number option: create second or third most recent symlinks. Add destination_dir. Add -f option
# version="1.09.2016-09-07" # add function get_global_arguments(), added command line options and aliases
# script_version="1.10.1" # 2016-09-11 - technout - Implement getopts, Semantic Versioning added.
script_version="1.10.3" # 2016-09-12 - technout - Many bug fixes. Fixing repeated -1 printing. Print normal text to terminal and log.
script_version="1.10.4" # 2016-09-17 - technout - Fix clean_old_symlinks for filenames with spaces. Added print log file flag --print_log
script_version_date="2016-09-17"

# DEBUG:
# variables must be set before using them!!
# if [ "${strict}" == "1" ]; then
  # set -o nounset
# fi

#===============================================================================
# User may change these variables
current_user="technout"
working_dir="/home/$current_user/.config/stremio/stremio-cache"
subdir="/home/$current_user/.config/stremio/subtitles"
logfile_location="/var/log/stremio-casting-script.log"
# destination_dir="/home/$current_user/Downloads/No_Backup/Stremio" # gives problem with sharing symbolic links
destination_dir=$working_dir # script outputs symbolic links to this location
datetime=$(date +"%d-%m-%Y %T") # default is $(date +"%d-%m-%Y %T")
guid_length=40 # default is 40
mime_type="video" # default is video
vid_extension="mp4" # default is "mp4"
sub_extension="srt" # default is "srt"
default_logtail_size=50 # size of the log tail if -v or --verbose is given
silent_mode=0 # default is 0, if set to 1 no output is send to the terminal
mode="create" # default mode is create
force_overwrite=0 # when setting -f flag, force_overwrite will be set to 1

# Declare other variables
file_index=1
subtitle_index=0 # subtitle_index will be the same as file_index, if set to 0
custom_name=0 # changing this has no effect
show_log_tail=0
script_name="$(basename "${0}")" # don't change this
var_file_name_nr="0"
var_guid="0"
bold=$(tput bold)
normal=$(tput sgr0)
# IFS="\n" # set Internal Field Seperator to 'new line'

#===============================================================================
# Start logging
cd $working_dir
echo "" >> $logfile_location
echo "$datetime - Running $script_name version: $script_version ($script_version_date)" >> $logfile_location
echo "$datetime - Change working dir to: $working_dir" >> $logfile_location

#===============================================================================
# Exit and trap_cleanup functions
trap_cleanup_before_terminating()
{
  # If script stops abrupt, clean here files and stop services
  error_code=${1:-0}
  echo "$datetime - Execute trap_cleanup_before_terminating($error_code)" >> $logfile_location
  if (( show_log_tail > 0 )); then # show logfile tail at the end
    tail -n $show_log_tail $logfile_location
  fi
}
# Trap bad exits with trap_cleanup function
trap trap_cleanup_before_terminating INT TERM

normal_exit()
{
  # Use this function for normal exit, cleanup files or stop services here!!
  exit_code=${1:-0}
  echo "$datetime - Execute normal_exit($exit_code)" >> $logfile_location
  if (( show_log_tail > 0 )); then # show logfile tail at the end
    echo "---------------------------------== Log file ==---------------------------------"
    echo ""
    tail -n $show_log_tail "$logfile_location"
    echo ""
  fi
  trap - INT TERM EXIT
  exit
}

set_logtail()
{
  echo "$datetime - Execute set_logtail($default_logtail_size)" >> $logfile_location
  show_log_tail="$default_logtail_size"
}

print_log()
{
  case $log_lines in # good old bourne shell test for: check if valid number
    ( ''|*[!0-9]* ) show_log_tail=$default_logtail_size ;;
    ( * ) show_log_tail=$log_lines ;;
  esac
  echo "$datetime - Execute print_log($show_log_tail)" >> $logfile_location
  normal_exit
}

#===============================================================================
# Help, usage en script info
usage()
{
  echo "$datetime - Execute usage()" >> $logfile_location
  show_log_tail=0
  echo ""
  echo "  ${bold}SYNOPSIS${normal}
    ${script_name} [options]

  ${bold}DESCRIPTION${normal}
    Command line interface for sharing files from the stremio-cache directory.
    Creating symbolic links to the files and adding the subtitles to
    the same directory, with the same name as the video file.

  ${bold}OPTIONS${normal}
  -c [name], --custom_name=[name]
    Creates symbolic link file and subtitle file with the given name. If no name
    is given, the DEFAULT name will be the date and time of that moment.
  -i [number], --file_index=[number]
    Creates symbolic link to the video file with the given index number. A high
    number creates a less recent video symlink. If no number is given, the
    DEFAULT number will be 1. (links to most recent video file)
  -j [number], --subtitle_index=[number]
    DEFAULT is the same index as -i. A high number tells the script to use an
    older subtitle file.
  -l [search], --list=[search]
    List all requested symlink files that contain the search value.
    The DEFAULT value lists all files starting with symlink.
  -d [search], --delete=[search]
    Deletes all requested symlink files that contain the search value.
  -s, --silent_mode             No output is send to the terminal
  -f, --force_overwrite         Delete symbolic link and subtitle if files
                                already exists.
  -v, --verbose                 Print logfile tail at the end of the script.
  -h, --help                    Print this help
  --version                     Print script information
  --print_log=[#lines]          Print logfile [number of lines]

  ${bold}EXAMPLES${normal}
    ${script_name} --list
    ${script_name} -c my-video-titel
    ${script_name} -l my-video-titel
    ${script_name} -fc my-video-titel -i 4 -j 1"
  echo ""
  normal_exit
}

script_info()
{
  echo "$datetime - Execute script_info()" >> $logfile_location
  show_log_tail=0
  echo ""
  echo "  ${bold}IMPLEMENTATION${normal}
    Version         ${script_name} ${script_version} (${script_version_date})
    Author          technout
    Copyright       Copyright (c) 2016"
  echo ""
  normal_exit
}

#===============================================================================
# reading arguments, flags and options
get_options()
{
  echo "$datetime - Execute get_options($@)" >> $logfile_location
  local OPTIND
  local arg
  while getopts :fhsvc:d:i:j:l:-: arg; do
    case $arg in
      ( f )  force_overwrite=1 ;;
      ( h )  usage ;;
      ( s )  silent_mode=1 ;;
      ( v )  set_logtail ;;
      ( c )  custom_name="$OPTARG" ;;
      ( d )  delete_pattern="$OPTARG"; mode="delete" ;;
      ( i )  file_index="$OPTARG" ;;
      ( j )  subtitle_index="$OPTARG" ;;
      ( l )  list_pattern="$OPTARG"; mode="list" ;; # TODO: Fix -l without options
      ( - )  LONG_OPTARG="${OPTARG#*=}" # delete shortest match from the beginning
           case $OPTARG in
             ( force_overwrite ) force_overwrite=1 ;;
             ( custom_name=?* ) custom_name="$LONG_OPTARG" ;;
             ( custom_name ) echo "No argument for --$OPTARG option" >&2; normal_exit 2 ;;
             ( delete=?* ) delete_pattern="$LONG_OPTARG"; mode="delete" ;;
             ( delete ) echo "No argument for --$OPTARG option" >&2; normal_exit 2 ;;
             ( list=?* ) list_pattern="$LONG_OPTARG"; mode="list" ;;
             ( list ) list_pattern=""; mode="list" ;;
             ( help ) usage ;;
             ( version ) script_info ;;
             ( verbose ) set_logtail ;;
             ( print_log=?* ) log_lines="$LONG_OPTARG"; print_log ;;
             ( print_log ) log_lines=$default_logtail_size; print_log ;;
             ( '' )         break ;; # "--" terminates argument processing
             ( * )          echo "Illegal option --$OPTARG" >&2; normal_exit 2 ;;
           # ( list* | show* ) echo "No argument allowed for --$OPTARG option" >&2; normal_exit 2 ;;
           esac ;;
      ( \? ) echo "Illegal option -$OPTARG" >&2; normal_exit 2 ;;  # getopts already reported the illegal option
    esac
  done
  shift $((OPTIND-1)) # remove parsed options and args from $@ list
}

get_arguments() # obsolete function
{
  # Reads arguments. Needs all global arguments passed to this function.
  echo "$datetime - Execute get_global_arguments() with $# parameters" >> $logfile_location
  counter=1
  next=2
  for var in "$@"; do
    # echo "$datetime - var: $var" >> $logfile_location
    if [[ "$var" == "-c" || "$var" == "--custom-name" ]]; then
      custom_name="${!next}"  # get argument value of next index, possible with indirection !
      # echo "$datetime - custom_name: $custom_name" >> $logfile_location
    elif [[ "$var" == "-f" || "$var" == "--force-delete" ]]; then
      force_overwrite=1
    elif [[ "$var" == "-i" || "$var" == "-fi" || "$var" == "--index" || "$var" == "--file-index" ]]; then
      file_index="${!next}"
    elif [[ "$var" == "-l" || "$var" == "--list" ]]; then
      list_pattern="${!next}"
      mode="list"
    fi
    (( counter++ ))
    (( next++ ))
  done
}

set_default_values()
{
  echo "$datetime - Execute set_default_values()" >> $logfile_location
  if [ "$file_index" -ne "$file_index" ] 2>/dev/null; then
    file_index=1 # if not a valid integer, set value to 1
  fi
  # subtitle_index will be the same as file_index, if set to 0
  if [ "$subtitle_index" -ne "$subtitle_index" ] 2>/dev/null; then
    subtitle_index=0 # if not a valid integer, set value to 0
  fi
  list_pattern="${list_pattern:-symlink}" # set default value to symlink
  delete_pattern="${delete_pattern:-0}" # set default value to 0
  # custom_name="${custom_name:-0}"
  if (( "${#custom_name}" < 4 )); then
    custom_name="" # set $custom_name to empty if shorter then 4
  fi
  if [[ "$custom_name" =~ [^a-zA-Z0-9_-] ]]; then
    custom_name="" # set $custom_name to empty if invalid characters are found
  fi
}

#===============================================================================
# Main script functions
get_newest_guid()
{
  number=${1:-1} # if parameter 1 is empty/null, then set default value to 1
  echo "$datetime - Execute get_newest_guid()" >> $logfile_location
  guids=$(ls -dt */ | head -n "$number") # returns newest two directories first
  for item in $guids; do
    guid=$item # return last item in loop
  done
  echo "$datetime - $guid found as newest guid" >> $logfile_location
  if (( ${#guid} == guid_length+1 )); then # test for correct guid length
    # delete the / from the guid string
    guid=${guid%/*} # delete shortest match of pattern from the end
    echo "$datetime - correct guid ($guid) was found" >> $logfile_location
    echo "$guid" # return value
  else
    echo "$datetime - wrong guid found" >> $logfile_location
    echo -1 # return no_guid_found_error
  fi
}

get_file_name_nr()
{
  echo "$datetime - Execute get_file_name_nr(guid=$1)" >> $logfile_location
  guid=${1:-0} # if parameter 1 is empty/null, then set default value to 0
  if (( ${#guid} == guid_length )); then
    datetime=$(date +"%d-%m-%Y %T")
    echo "$datetime - request for file_index: $file_index" >> $logfile_location
    file_name_list=$(find "$working_dir"/"$guid" -maxdepth 1 -type f -size +30M | xargs ls -t | file -if- | grep "$mime_type" | awk -F: '{print $1}' | head -n "$file_index")
    for item in $file_name_list; do
      file_name_nr="$item" # return last item in loop
    done
    file_name_nr=${file_name_nr##*/} # delete longest match of pattern from the beginning
    # find /home/$current_user/.config/stremio/stremio-cache/2b4640d868b9defcc8e5bf9dbb9838f337800a90 -maxdepth 1 -type f -size +30M | xargs ls -t | file -if- | grep video | awk -F: '{print $1}'
    # file_name_nr=$(find $working_dir/$guid -maxdepth 1 -type f -size +30M | xargs ls -t | file -if- | grep $mime_type | awk -F: '{print $1}' | head -n 1)
    # file_name_nr=${file_name_nr##*/} # delete longest match of pattern from the beginning
    if (( ${#file_name_nr} < 1 )); then # length is smaller then 1
      echo "$datetime - No file_name_nr found!" >> $logfile_location
      echo -1 # return no_file_nr_found_error
    else
      echo "$datetime - Found internal file_name_nr: $file_name_nr" >> $logfile_location
      echo "$file_name_nr" # return value
    fi
  else
    echo "$datetime - No valid guid was given." >> $logfile_location
    echo -2 # return invalid_guid_error
  fi
}

generate_movie_nr()
{
  echo "$datetime - Execute generate_movie_nr()" >> $logfile_location
  movie_nr=$(date +"%Y-%m-%d_%H-%M")
  echo "$datetime - movie_nr (symlink-$movie_nr) generated" >> $logfile_location
  echo "symlink-$movie_nr" # return value
}

get_custom_name()
{
  echo "$datetime - Execute get_custom_name()" >> $logfile_location
  if [[ ! -z $custom_name ]]; then # test if custom_name is not zero length
    echo "$datetime - custom_name was found: $custom_name" >> $logfile_location
    echo $custom_name # return value
  else
    echo "$datetime - no custom_name found" >> $logfile_location
    echo "$(generate_movie_nr)" # return value
  fi
}

get_subtitle_name()
{
  index=${1:-1} # if parameter 1 is empty/null, then set default value to 1
  echo "$datetime - Execute get_subtitle_name($index)" >> $logfile_location
  sub_file_list=$(cd $subdir && ls -dt *.srt | head -n "$index") # returns newest *.srt file first
  for item in $sub_file_list; do # repeate until last item in list
    sub_file_name=$item
  done
  if (( ${#sub_file_name} >= 4 && ${#sub_file_name} <= 25 )); then # test for correct filename length
    echo "$datetime - Correct subtitle filename ($sub_file_name) found" >> $logfile_location
    echo "$sub_file_name"
  else
    echo "$datetime - No subtitle filename" >> $logfile_location
    echo -1 # return no_subtitle_found_error
  fi
}

copy_subtitle()
{
  echo "$datetime - Execute copy_subtitle()" >> $logfile_location
  subfilename=$1
  dest_filename=$2
  sub_ext=${subfilename##*.} # delete longest match from the beginning
  if (( ${#sub_ext} == 3 )); then
    sub_extension=$sub_ext
    echo "$datetime - sub_extension is found: $sub_extension" >> $logfile_location
  fi
  cp -v "$subdir"/"$subfilename" "$destination_dir"/"$dest_filename"."$sub_extension" 2>&1 >> $logfile_location
}

create_symbolic_link()
{
  echo "$datetime - Execute create_symbolic_link()" >> $logfile_location
  file_name_nr=-1
  count_number=1
  while (( file_name_nr < 0 )); do
    guid=$(get_newest_guid $count_number)
    file_name_nr=$(get_file_name_nr "$guid")
    if [[ "$file_name_nr" == "-2" ]]; then
      count_number=-2
      break
    fi
    (( count_number++ ))
  done
  if (( count_number > 0 )); then
    datetime=$(date +"%d-%m-%Y %T")
    custom_name=$(get_custom_name)
    if [[ $force_overwrite == "1" ]]; then
      if [[ $custom_name == *".mp4" ]]; then
        ret=$(delete_symlink "$custom_name")
      else
        ret=$(delete_symlink "$custom_name".$vid_extension)
      fi
      echo "$datetime - forcing existing file to overwrite: $custom_name return_code($ret)" >> $logfile_location
    fi
    echo "$datetime - custom_name received: $custom_name" >> $logfile_location
    ln -s $working_dir/"$guid"/"$file_name_nr" $destination_dir/"$custom_name".mp4
    echo "$datetime - symlink $custom_name.mp4 created" >> $logfile_location
    echo "$datetime - symlink to $working_dir/$guid/$file_name_nr" >> $logfile_location
    var_file_name_nr=$file_name_nr # save as global variable will not work!!
    var_guid=$guid # save as global variable not working!!
    echo "$custom_name" # return value
  else
    echo "$datetime => No symlink created, no correct guid or file_nr found!" | tee -a $logfile_location
    echo -1 # return no_symlink_created
  fi
}

clean_old_symlinks()
{
  # find . -type f -name "*.srt" -exec grep -Iq . {} \; -and -print # list all textbased .srt files
  # find . -type l -! -exec test -e {} \; -exec rm {} \; -print # list all broken symlinks and remove them
  echo "$datetime - Execute clean_old_symlinks()" >> $logfile_location
  sub_ext=$1
  # pipe find to while in seperate parallel process. -print0 means null byte at end of line.
  find . -type l -! -exec test -e {} \; -print0 | while IFS= read -r -d '' file; do
    result=$(delete_symlink "$file")
    if (( $result < -1 )); then
      echo "$datetime => Error while cleaning symlinks $i - error($result)" | tee -a $logfile_location
    fi
  done
  # for i in $(find . -type l -! -exec test -e {} \; -print | tr '\n' ','); do # replace newline with comma
    # i=${i#*/} # delete shortest match from beginning, just keep the filename
    # result=$(delete_symlink "$i")
  # done
}

delete_file()
{
  # test if file exists -e and is a normal file -f (no device or directory) OR is a symbolic link
  if [[ -e "$1" && -f "$1" ]] || [[ -L "$1" ]]; then
    echo "$datetime - delete file $1" >> $logfile_location
    rm "$1" 2>&1 >> $logfile_location
    echo 0 # return normal execution
  else
    echo -1 # return file_not_found_error
  fi
}

delete_symlink()
{
  echo "$datetime - Execute delete_symlink($1)" >> $logfile_location
  if (( ${#1} > 0 )); then
    del1=$(delete_file "$1")
    del2=$(delete_file "${1%.*}.$sub_extension")
    echo $(( del1 + del2 )) # return sum
  else
    echo -3 # return no_parameter_given
  fi
}

get_all_symlinks()
{
  sym_name=${1:-symlink} # if parameter 1 is empty/null, then set default value
  echo "$datetime - Get all symbolic links with $sym_name" >> $logfile_location
  # date_time=$(date +"%Y-%m-%d_%H-%M")
  # arr_symlinks=( $(find $destination_dir -type l -ls) ) # list all symbolic links
  counter=0
  for i in $(find $destination_dir -type l -ls | sort -k11); do # sort result by column #11
    if [[ "$i" == *"$sym_name"* ]]; then # check if $i contains string $sym_name
      new_list[$counter]=$i
      # echo "item i var: $i"
    fi
    (( counter++ ))
    # echo "counter var: $counter"
  done
  echo "${new_list[@]}" # return array of found symlinks
  # echo "$datetime - Resulting list: ${new_list[@]}" >> $logfile_location
}

symlink_is_unique()
{
  # check if symlink destination is unique
  echo "$datetime - Execute symlink_is_unique()" >> $logfile_location
  # TODO
}

#===============================================================================
# Main script
if (( $# > 0 )); then
  get_options "$@" # pass all global arguments to the function
fi
set_default_values

if [[ "$mode" == "list" ]]; then # user wants to list symlinks
  echo "$datetime - Listing symbolic links: $mode." >> $logfile_location
  # get_nr_of_arguments
  symlinks=$(get_all_symlinks "$list_pattern")
  counter=0
  for item in $symlinks; do
    echo "$item"
    (( counter++ ))
  done
  echo "$datetime => $counter symbolic links found!" | tee -a $logfile_location

elif [[ "$mode" == "delete" && "$delete_pattern" != "0" ]]; then # user wants to delete symlinks
  echo "$datetime - Deleting symbolic links ($mode)" >> $logfile_location
  symlinks=$(get_all_symlinks "$delete_pattern")
  counter=0
  for item in $symlinks; do
    echo "$item"
    result=$(delete_symlink "$item")
    if (( $result < -1 )); then
      echo "$datetime - Error while removing symlinks.. ($result)" >> $logfile_location
      break
    fi
    (( counter++ ))
  done
  echo "$datetime => $counter symbolic links deleted!" | tee -a $logfile_location
  echo "$datetime - And $counter subtitles deleted!" >> $logfile_location

elif [[ "$mode" == "create" ]]; then # default, user wants to create new symlink
  echo "$datetime - Creating new symlink ($mode)" >> $logfile_location
  custom_name=$(create_symbolic_link)
  echo "Symbolic link $custom_name.mp4 created"
  # echo "Symlink to $working_dir/$var_guid/$var_file_name_nr"
  if [[ $custom_name != "-1" ]]; then # only if no error returned, continue
    datetime=$(date +"%d-%m-%Y %T")
    if [[ "$subtitle_index" == "0" ]]; then
      subtitle_index=$file_index # when no (valid) $subtitle_index was given, keep $file_index
    fi
    subfilename=$(get_subtitle_name "$subtitle_index") # read return value of a function
    copy_subtitle "$subfilename" "$custom_name" # pass arguments to a function
    echo "$datetime - Done!" >> $logfile_location
  else
    echo "$datetime - No action is done here! ($custom_name)" >> $logfile_location
  fi
  clean_old_symlinks "$sub_extension"
else
  echo "$datetime => No valid execution mode! ($mode)" | tee -a $logfile_location
fi

normal_exit # exit the script savely
