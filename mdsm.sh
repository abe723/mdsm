#!/usr/bin/env bash
#             __
#.--------.--|  |.-----.--------.
#|        |  _  ||__ --|        |
#|__|__|__|_____||_____|__|__|__|
#*************************************************************************
# PROGRAM: mdsm.sh (Multi-threaded TSM Backup Scheduler)                 *
# VERSION: v1.011                                                        *
# DESCRIPTION:                                                           *
#   A multi-threaded TSM (Tivoli Storage Manager) backup scheduler       *
#   that operates in two distinct modes:                                 *
#     1. High-performance Mode: Optimized for evenly balanced            *
#        filesystems.                                                    *
#     2. LARGEFS Mode: Designed for very large filesystems and           *
#        directories.                                                    *
#   Multiple instances of the program can run simultaneously without     *
#   interference.                                                        *
#                                                                        *
# USAGE:                                                                 *
#   ./mdsm.sh mdsm.ini                                                   *
#     - `mdsm.ini` is the configuration file used for the current run.   *
#                                                                        *
# REQUIREMENTS:                                                          *
#   - Bash 4.4+                                                          *
#   - Coreutils                                                          *
#                                                                        *
# CONFIGURATION:                                                         *
#   - Set `LARGEFS[0], [1], [2]...` to enable LARGEFS mode for specified *
#     filesystems.                                                       *
#                                                                        *
# allan@bednarowski.ca        https://git.bednarowski.ca/public/mdsm.git *
#*************************************************************************
VER="v1.011"
MYPID=$$

set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# set things up
TIMEOUT="23h"
DSMCPATH="/usr/bin/dsmc"
TOPLOGDIR="logs/"
LOGFILE="mdsm.log"
LOGRET="+14"
LOGDIR="$(date +%Y-%h-%d.%H%M%S)/"
SLEEPDELAY=15
TSMERRMASK="AN[S,R,E][1-9][1-9][1-9][1-9][E,W]"
TSMIGNOREMASK="ANS1228E"
VERBOSE=1
INDEX=0
COMPLETED=0
success=0; warning=0; error=0; fail=0
numfs=0
numParentDir=0
highestrc=0

# custom logging
function log () {
  local msg="$*"
  printf '[%(%F %T)T] %s\n' -1 "${msg}"  | tee -a "${LOG:-/dev/null}"
}

function logError() {
    local msg="$*"
    log "[ERROR] $msg"
}

# enhanced die function
function die() {
    logError "$*"
    exit "${2:-1}"  # Default exit code is 1
}

# check if SIGTERM was sent because of job failures or actual terminate signal
function checkEnd() {
    # If backups completed, exit with highest return code, else exit 255 to signal interruption
    [[ -e "${RCFILE:-}" ]] && highestrc=$(<"${RCFILE}") || highestrc=255
    # get the highest return code
    if (( "${COMPLETED}" == 1 )); then
        exit "${highestrc}"
    fi
    # otherwise the program was interrupted so return a 255
    exit 255
}

# execute from EXIT trap
function cleanup() {
    if [[ -e "${RCFILE:-}" ]]; then
        highestrc=$(<"${RCFILE}")
    else
        highestrc=0
    fi
    log ""
    if [[ -n "${NEWDURATION:-}" && ${DURATION:-0} -gt 0 ]]; then
        log "Backup of ${numfs:-0} filesystems completed in ${NEWDURATION:-0 seconds} with highest return code: ${highestrc}"
    else
        log "Backup cancelled."
    fi
    (( exitCode == 255 )) && log "program received termination signal (255)"
    # Only remove temporary files if LOG is set
    if [[ -n "${LOG:-}" ]]; then
        log "removing temporary files"
        [[ -e "${LOG}.completed" ]] && rm "${LOG}.completed"
        [[ -e "${RCFILE:-}" ]] && rm "${RCFILE}"
        log "stopping process group [${MYPID}]"
    fi
    pkill -g "${MYPID}"
}

# terminate/interrupt/completion w/failure trap
trap "checkEnd" SIGINT SIGTERM INT TERM
# kill everything in $MYPID process group upon EXIT
exitCode=0
trap "exitCode=\$?; cleanup" EXIT

# check for existence of config file
[[ "${1:-}" != "" ]] || die "usage: $0 /path/to/config.file"
CONFIGFILE="$(cd "$(dirname "${1:-}" 2>/dev/null )" 2>/dev/null && pwd)/$(basename "${1:-}" 2>/dev/null)"
[[ -f "${CONFIGFILE}" ]] || die "cannot open ${CONFIGFILE}"

# parse config file
while IFS="=" read -r name value; do
  name=$(echo "${name}" | sed 's/#.*//g' | xargs 2>/dev/null)
  value=$(echo "${value}" | sed 's/#.*//g' | xargs 2>/dev/null)
  echo "${name}" | grep -Eq "^[A-Z]|^[a-z]" || continue
  declare "${name}=${value}"
done < "${CONFIGFILE}"

# MAXPROC is the only variable that needs to be set in the config file for the program to work
[[ -z "${MAXPROC}" || "${MAXPROC}" -le 1 ]] && die "MAXPROC unset or invalid"

# Sanity check
[[ "${TOPLOGDIR}" == "/" ]] && die "Log directory cannot be /"
mkdir -p "${TOPLOGDIR}" 2>/dev/null || die "Cannot write to log directory: ${TOPLOGDIR}"

DIR="${TOPLOGDIR}/${LOGDIR}"
mkdir -p "${DIR}" 2>/dev/null || die "Cannot write to log directory: ${DIR}"

# Resolve absolute directory path
ABSDIR="$(cd "${DIR}" && pwd)" || die "Cannot cd to ${DIR}"

# set LOG variable to READONLY
declare -r LOG="${ABSDIR}/$(basename "${LOGFILE}")"
RCFILE="${LOG}.highestrc"

# check to see which mode to run in
if [[ -v LARGEFS && ${#LARGEFS[@]} -gt 0 ]]; then
  MODEBOOL=1
  MODE="largeFS"
else
  MODEBOOL=0
  MODE="HighPerformance"
fi

# convert seconds to minutes and hours
function convertDur () {
  local hh mm
  local dur=${1:-0}
  local ss=${dur}
  local message="${ss} seconds"
  (( dur > 120 )) && mm=$((dur/60)) && ss=$((dur%60)) && message="${mm} minutes ${ss} seconds"
  (( dur > 7200 )) && hh=$((dur/60/60)) && mm=$((dur/60%60)) && ss=$((dur%60)) && message="${hh} hours ${mm} minutes ${ss} seconds"
  printf '%s\n' "${message}"
}

# run incremental backup of $1, parameters are $2
function ba () {
  local myFS myParm baStartTime baEndTime baRuntimeDur lastrc message
  [[ -z "${1:-}" ]] && die "nothing to backup"
  myFS=$1
  myParm=$2
  baStartTime=$(date +%s)
  timeout "${TIMEOUT}" "${DSMCPATH}" incr "${myFS}" "${myParm}"
  lastrc=$?
  [[ -e "${RCFILE}" ]] && highestrc=$(<"${RCFILE}")
  (( "${lastrc}" > "${highestrc}" )) && echo "${lastrc}" > "${RCFILE}"
  baEndTime=$(date +%s)
  baRuntimeDur=$((baEndTime-baStartTime))

  # passthrough client errors to main program
  grep -E "^${TSMERRMASK:-AN}" "${LOG}.${INDEX}" | grep -vE "${TSMIGNOREMASK:-}" | while read -r line; do
    [[ "${VERBOSE}" == "1" ]] && log "job[${INDEX}] ${line}" >> "${LOG}.err"
  done

  # condition code logic
  case "${lastrc}" in
    0)
      message="job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with a status of success"
      ;;
    4)
      message="job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with one or more warnings - return code: 4"
      printf '[%(%F %T)T] %s\n' -1 "job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with one or more warnings - return code: 4" >> "${LOG}.warning"
      ;;
    8)
      message="job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with one or more errors - return code: 8"
      printf '[%(%F %T)T] %s\n' -1 "job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with one or more errors - return code: 8" >> "${LOG}.error"
      ;;
    *)
      message="job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with a status of fail - return code: ${lastrc}"
      printf '[%(%F %T)T] %s\n' -1 "job[${INDEX}] backup for ${currentFS} completed in $(convertDur ${baRuntimeDur}) with a status of fail - return code: ${lastrc}" >> "${LOG}.fail"
      ;;
  esac
  log "${message}" >> "${LOG}.completed"

}

# check to see how many backup processes this program has spawned
function baProcs () {
  local dsmProcs localProc count
  count=0
  # dump the contents of ps to a file to read from to avoid multiple invokations
  ps -ef > "${LOG}.ps"
  mapfile -t dsmProcs < <(grep -E "[d]smc incr" "${LOG}.ps" | awk '{print $3}')
  for localProc in "${dsmProcs[@]}"; do
    (grep "$localProc" "${LOG}.ps" | grep -Ev 'grep' | grep -q "${MYPID}") && ((count++))
  done
  rm  "${LOG}.ps"
  echo "${count}"
}

# Check for the presence of any .err files to pass errors through to the main program
function checkErr () {
  if [[ -e "${LOG}.err" ]]; then
    cat "${LOG}.err" && rm "${LOG}.err"
  fi
}

# check for completed backups
function checkDone () {
  local s w e f
  if [[ -e "${LOG}.completed" ]]; then
    tee -a "${LOG}" < "${LOG}.completed"
    s=$(grep -c "success"  "${LOG}.completed" | xargs)
    w=$(grep -c "return code: 4" "${LOG}.completed" | xargs)
    e=$(grep -c "return code: 8" "${LOG}.completed" | xargs)
    f=$(grep -c "with a status of fail" "${LOG}.completed" | xargs)
    success=$((success+s))
    warning=$((warning+w))
    error=$((error+e))
    fail=$((fail+f))
    rm "${LOG}.completed"
 fi
}

# shuffle filesystem array
function shuffle () {
   local i tmp size max rand
   size=${#fs[*]}
   max=$(( 32768 / size * size ))
   for ((i=size-1; i>0; i--)); do
      while (( (rand=RANDOM) >= max )); do :; done
      rand=$(( rand % (i+1) ))
      tmp=${fs[i]} fs[i]=${fs[rand]} fs[rand]=$tmp
   done
}

# Clean up the log directories based on retention
function logCleanup() {
    log "Cleaning up logs older than ${LOGRET} days"
    local dir old_dirs
    mapfile -t old_dirs < <(find "${TOPLOGDIR:-logs/}" -mindepth 1 -maxdepth 1 -type d -mtime "${LOGRET}" 2>/dev/null)

    if (( ${#old_dirs[@]} > 0 )); then
        for dir in "${old_dirs[@]}"; do
            [[ -d "$dir" && "$dir" != "/" ]] && rm -rf -- "$dir"
        done
        log "${#old_dirs[@]} log directories removed."
    else
        log "No log directories older than ${LOGRET} days found."
    fi
}

# show backup summary
function summary() {
    ENDTIME=$(date +%s)
    DURATION=$((ENDTIME - STARTTIME))
    NEWDURATION="$(convertDur ${DURATION})"
    log ""
    log "+-------------------------------------------------------------------------------------------------------+"
    log "|                                   B A C K U P       C O M P L E T E                                   |"
    log "+-------------------------------------------------------------------------------------------------------+"
    log ""
    # Use an array to handle log file types
    local log_types=("success" "warning" "error" "fail")

    for log_type in "${log_types[@]}"; do
        if [[ -e "${LOG}.${log_type}" ]]; then
            log "${log_type}:"
            tee -a "${LOG}" < "${LOG}.${log_type}"
        fi
    done
    log ""
    log "Jobs completed successfully: ${success}"
    log "Jobs completed with warnings: ${warning}"
    log "Jobs completed with errors: ${error}"
    log "Jobs failed: ${fail}"
}

# show a list of filesystems to be backed up
function showFsList () {
  local x localFs
  x=${numParentDir:-0}
  for localFs in "${fs[@]}"; do
    ((x++))
    log "job[${x}] will backup : ${localFs%%/}/"
  done
}

# start the program
fs=()

if (( MODEBOOL == 0 )); then
  # use df to generate filesystem array
  mapfile -t fs < <(df -P | awk -v incl="${INCLREGX:-.}" -v excl="${EXCLREGX:--}" 'NR > 1 && $6 ~ incl && !($6 ~ excl) {print $6}')
fi

if (( MODEBOOL == 1 )); then
  parentDir=()

  # iterate through the filesystems set for LARGEFS mode
  for localLARGEFS in "${LARGEFS[@]}"; do
    parentDir+=( "${localLARGEFS%%/}/" )

    # Use find to scan directories 1 level down
    while IFS= read -r localDir; do
      fs+=( "${localDir%%/}/" )
    done < <(find "${localLARGEFS}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done

  # get count of parent dir after processing to ignore problematic filesystems
  numParentDir="${#parentDir[@]}"
fi

numfs="${#fs[@]}"
df -P | awk -v incl="${INCLREGX:-.}" -v excl="${EXCLREGX:-}" 'NR > 1 && $6 ~ incl && !($6 ~ excl) {print $6}'
(( "${numfs}" == 0 )) && die "cannot find any eligible filesystems for backup"
shuffle

# header
log "mdsm - multi-threaded tsm backup [${MODE}]"
log "${VER}"
log "PID: ${MYPID}"
log "timeout: ${TIMEOUT}"
log ""
while read -r line; do
  log "${line}"
done < <(ps f | grep -E "[d]smc incr|$0" | grep -v grep )
log ""
log "config file: ${CONFIGFILE}"
log "logging to: ${LOG}"
log "working directory: ${ABSDIR}"
log ""
logCleanup
log ""
STARTTIME=$(date +%s)
if (( MODEBOOL == 1 )); then
  log "top level directories found: ${numParentDir}"
  for currentFS in "${parentDir[@]}"; do
    ((INDEX+=1))
    { ba "${currentFS%%/}/" -subdir=no & } >> "${LOG}.${INDEX}" 2>&1
    localPid=$!
    log "job[${INDEX}] backup started for top level directory ${currentFS%%/}/ as pid: ${localPid}"
    PIDS+=( "${localPid}" )
  done
  numfs=$((numfs+numParentDir))
  log ""
fi
log "generating job list:"
showFsList
log ""
log "starting incremental backup jobs for ${numfs} filesystems using ${MAXPROC} threads."
log ""

# iterate through filesystems
for currentFS in "${fs[@]}"; do
  while (( $(baProcs) >= "${MAXPROC}" )); do
    checkErr
    checkDone
    sleep "${SLEEPDELAY}"
  done
  checkErr
  checkDone
  ((INDEX+=1))
  { ba "${currentFS%%/}/" -subdir=yes & } >> "${LOG}.${INDEX}" 2>&1
  localPid=$!
  log "job[${INDEX}] backup started for ${currentFS%%/}/ as pid: ${localPid}"
  PIDS+=( "${localPid}" )
done

# wait for remaining jobs to complete
for localPid in "${PIDS[@]}"; do
  if pgrep -P "${MYPID}" | grep -q "${localPid}"; then
    log "waiting for pid: ${localPid}"
    wait "${localPid}"
    checkErr
    checkDone
  fi
done

# show a summary
checkErr
checkDone
summary
[[ -e "${RCFILE}" ]] && highestrc=$(<"${RCFILE}")

# the program has completed
COMPLETED=1
