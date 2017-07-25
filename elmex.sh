#!/bin/bash
# ---------------------------------------------------------------------------
# elmEx - Convert and export McAfee ELM logs.
#
#
# Usage: elmex -r | -h | -n | [-f YYYY-MM-DD] [-l YYYY-MM-DD] <OUTPUT_DIR>
# Resume an existing job or Start a new job [with optional dates]. Exported logs are put in specified directory.
#
# Time format is: "YYYY-MM-DD [HH:MM:SS]" "YYYY-MM-DD [HH:MM:SS]" or most any valid format accepted by date().
# Example: elmex -t "2015-07-01 00:01:00" "2015-07-01 23:59"
# Time and its parts are optional, date parts are not:  "2015-07-01", "2015-07-01 14", "2015-07-01 14:12" are all valid.
# Use double quotes when including the time part.
#
#set -o errexit
#set -o nounset
PROGNAME=${0##*/}
VERSION="2.0.1"
# Revision history:
# 2015-06-25 Version 1 Created by AW
# 2015-08-13 Version 2 Updated with Time functionality
# 2016-06-03 Version 2.0.1 - Bug fix - Thanks RH
# ---------------------------------------------------------------------------
#
# Declare globals
declare outdir=
declare cfgdir="/root/.elmex"
declare workdir="/tmp/.working"

declare done_f="${cfgdir}/exported-logs"
declare bookmark_f="${cfgdir}/logs-for-export"
declare -a dir=("${workdir}" "${cfgdir}")
declare ftime="0"
declare ltime="0"
declare action=

output_seperator() {
  printf "=========================================\n"
}

setup() {
  printf "Setting up...\n"
  output_seperator
  for dir in ${dir[@]}; do
    if [ -d ${dir} ]; then
      echo "Directory "${dir}" exists."
    else
      printf "Directory %s does not exist - creating now.\n" "${dir}"
      mkdir -p "${dir}"
    fi
  done
  output_seperator
}

resume_export() {
  if [[ -s ${bookmark_f} ]]; then
    while read r; do
      if [[ ! ${r} =~ ^([0-9]+,[0-9]+,[0-9]+$) ]]; then
        printf "Corrupt log entry found in %s\n" "$bookmark_f"
        printf "File Preserved. Manually inspect file to fix\n"
        exit 1
      else
        export_logs
      fi
    done <${bookmark_f}
  else
   printf "Error: Cannot resume export. No bookmark file found at %s.\n" "${bookmark_f}"
   exit 1
  fi
}

get_dsids() {
  printf "Building data source list\n"
  output_seperator
  dsarray="$(elm cmd='elmd.list_dsrcs' | /usr/bin/cut -d , -f 1)"
  if [[ ! ${PIPESTATUS[0]} ]]; then
    printf "Failed to get data sources.\n"
    exit 1
  fi

 for i in ${dsarray[@]}; do
    if [[ ${i} ]]; then
      elm_list_logs="/usr/local/bin/elm cmd='elmd.list_logfiles(/[ ]/ie,"${i}","${ftime}","${ltime}",10000000)' | /usr/bin/cut -d , -f 2,4,6"
      log_list=$( eval ${elm_list_logs} )
 
      for l in ${log_list[@]}; do
        if [[ ${l} =~ ^([0-9]+,[0-9]+,[0-9]+$) ]]; then
          printf "%s\n" "${l}" >> "${bookmark_f}"
          printf "Adding datasource log: %s to export file\n" "${i}"
          output_seperator
        else
          printf "No logs found for data source %s\n" ${i}
          output_seperator
        fi
      done
    fi
  done
}

export_logs() {
printf "Processing the export file\n"
output_seperator

while IFS=, read -r dsid firstlog logcnt
  do
    if [[ ${dsid} ]] && [[ ${firstlog} ]] && [[ ${logcnt} ]]; then
      tmpfile="${dsid}"."${firstlog}"
      printf "Processing data source: %s at record %s for %s logs.\n" "${dsid}" "${firstlog}" "${logcnt}"
      elm_get_logs="/usr/local/bin/elm cmd='elmd.get_logfile("${dsid}","${firstlog}","${workdir}/${tmpfile}")'"
      eval "${elm_get_logs}"
      printf "Converting ELM record to text...\n"
      eval elmlfcat "${workdir}/${tmpfile}" > "${outdir}"/log."${tmpfile}"
      rm "${workdir}"/"${tmpfile}"
      sed -i 1d "${bookmark_f}"
      printf "%s logs successfully exported\n" "${logcnt}"
      echo "${tmpfile}" >> "${done_f}"
      echo $(wc --lines <"${done_f}") total log files processed.
      echo $(wc --lines <"${bookmark_f}") logs remaining for export.
      output_seperator
    else
      printf "Data Source ID: %s had no valid logs to export\n" "${dsid}"
    fi

done < "${bookmark_f}"
}

clean_up() {
[[ -d ${cfgdir} ]] && rm -rf "${cfgdir}"
[[ -d ${workdir} ]] && rm -rf "${workdir}"
}

export_fin() {
printf "Export Complete!\n"
printf "Your logs are available in %s\n" "${outdir}"
}

#signal_exit() { # Handle trapped signals
#  case $1 in
#    INT)
#      error_exit "Program interrupted by user" ;;
#    TERM)
#      echo -e "\n$PROGNAME: Program terminated" >&2
#      graceful_exit ;;
#    *)
#      error_exit "$PROGNAME: Terminating on unknown signal" ;;
# esac
#}

help_message() {
  cat <<- _EOF_
Usage: ${PROGNAME} [OPTION]... [DIRECTORY]
Converts and exports ELM logs from an store to a specified directory.

Mandatory arguments:
 -r, Resume existing job.
 -n, Create a new job. Existing jobs will be deleted.
 -d, Export directory. Exported logs are placed in this directory.

 Optional arguments:
 -f, First log time, format: YYYY-MM-DD [HH:MM:SS]
 -l, Last log time, format: YYYY-MM-DD [HH:MM:SS]
 -h, Display this help message and exit.


 Either the -r or -n option is required. The -d option is always required.
 For the date flag, fractions of date/time are acceptable.

Examples:
# Resume existing job.
 ${PROGNAME} -r -d /mnt/exported-logs

# Create new job. Delete existing job.
 ${PROGNAME} -n -d /mnt/exported-logs

# Create new job between two dates.
 ${PROGNAME} -n -f 2015-01-01 -l 2015-02-01 -d /mnt/exported-logs

# Create new job between two times. Quotes are required.
 ${PROGNAME} -n -f "2015-01-01 03:00:00" -l "2015-01-02 14:00:00" -d /mnt/exported-logs

# Create new job to export logs from a past date until current.
 ${PROGNAME} -n -f 2015-08-01 -d /mnt/exported-logs

_EOF_
 exit 0
}

usage() {
  printf "Usage: ${PROGNAME} -r | -n [-f YYYY-MM-DD] [-l YYYY-MM-DD] <OUTPUT_DIR>\n"
  printf " Resume an existing job or Start a new job [with optional dates].\n Exported logs are put in specified directory.\n"
  printf " ${PROGNAME} -h for additional help.\n\n"
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Check for root UID
if [[ $(id -u) != 0 ]]; then
  error_exit "You must be the superuser to run this script."
fi

if [ $# -lt 1 ]
  then
    usage
    exit
fi

PROGNAME=${0}

while getopts 'hnrf:l:d:' flag; do
  case ${flag} in
    n) action_n="new"  ;;
    r) action_r="resume" ;;
    f) ftime="$(date -d "${OPTARG}" +%s)";;
    l) ltime="$(date -d "${OPTARG}" +%s)";;
    d) outdir="${OPTARG}";;
    h) help_message ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -d ${outdir} ]]; then
  if [[ ${action_n} = "new" ]] && [[ ${action_r} != "resume" ]]; then

    if [[ -z ${ftime} ]]; then
      ftime=0
    fi

    if [[ -z ${ltime} ]]; then
      ltime=0
    fi

    if [[ ${ftime} = 0 ]]; then
      printf "First log time is not set. Exporting logs from the start.\n"
    else
      printf "First log time set to: %s\n" "$( date -d "@$ftime" )"
    fi

    if [[ ${ltime} = 0 ]]; then
      printf "Last log time is not set. Exporting logs until done.\n"
    else
      printf "Last log time set to: %s\n" "$( date -d "@$ltime" )"
    fi

    if [[ ${ltime} != 0 ]] && [[ ${ftime} != 0 ]]; then
      if [[ ${ftime} -gt ${ltime} ]] ||  [[ ${ftime} -gt $( date +%s ) ]]; then
        printf "Time error: Start time is greater than Last time or the future\n\n"
        usage
        exit 1
      fi
    fi

    printf "Creating new log export job...\n"
    printf "Sending logs to %s\n" "${outdir}"

    clean_up
    setup
    get_dsids
    export_logs
    export_fin

  elif [[ ${action_r} = "resume" ]] && [[ ${action_n} != "new" ]]; then
    if [[ ${ltime} != 0 ]] && [[ ${ftime} != 0 ]]; then
      printf "Time constraints can only be used with the -n flag\n\n"
      usage
      exit 1
    else
      printf "Attempting to resume job...\n"
      printf "Sending logs to %s\n" "${outdir}"
      resume_export
    fi
  fi
else
   printf "Need to specify output directory: invalid -d flag. Does dir exist?\n\n"
   usage
   exit 1
fi
