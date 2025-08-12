#!/usr/bin/env bash
#
# Assign a weight to each filesystem based on change rate of objects
# Allan Bednarowski
# October 20, 2024
# getfsweight.sh v1.1
#
# 1.1 - added change rate

set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# Declare associative arrays to store filesystem info
declare -A fs_weight fs_size fs_inodes fs_changerate found_size fs_changesize

function getCursor () { tput sc; }                              # save cursor position
function putCursor () { tput rc; }                              # retrieve cursor position

# initialize variables
size=0
inodes=0
total_size=0
total_inodes=0
total_weight=0
avg_changerate=0
total_changesize=0
exclude=""
scale="kb"

# read inline configuration ( ./getfsweight.sh  exclude=/mnt/tank scale=mb )
for arg in "$@"; do
  IFS="=" read -r name value <<< "$arg"
  # Remove comments and trim leading/trailing spaces from name and value
  name="${name%%#*}"            # Remove everything after '#' in name
  name="${name//[[:space:]]/}"  # Trim spaces in name

  value="${value%%#*}"          # Remove everything after '#' in value
  value="${value//[[:space:]]/}"  # Trim spaces in value

  # Check if name starts with a letter
  [[ "$name" =~ ^[A-Za-z] ]] || continue

  # Declare the variable
  declare "$name=$value"
done

# add /run and /dev to any existing excludes which may have been set inline
[[ "$exclude" == "" ]] && exclude="/dev|/run" || exclude="${exclude%/}|/run|/dev|/proc"

# run find on each filesystem
while read -r mount; do
    getCursor
    echo -n "calculating weight for : ${mount}"
    
    #fs_weight["$mount"]=$(find "${mount}" -xdev -type f -mtime -1 -exec sh -c 'printf %c "$@" | wc -c' '' '{}' + 2>/dev/null | awk '{sum+=$1;} END{print sum;}')
    sum_size=0
    unset found_size
    unset found_elements
    
    # found array will contain a list of file sizes for files that were changed in the last 24 hours
    found_size=( $(find "$mount" -xdev -type f -mtime -1 -printf '%s\n' 2>/dev/null) )    
    found_elements=$(( ${#found_size[@]} - 1 ))
    (( "$found_elements" < 0 )) && found_elements=0
    fs_weight["$mount"]="$found_elements"
    
    # if there are any changed files found in the filesystem, calculate their cumulative size
    if (( "$found_elements" > 0 )); then
      for size in "${!found_size[@]}"; do
        (( sum_size+="$size" ))
      done
      if [[ "$scale" == "mb" ]]; then
        # convert to MB
        fs_changesize["$mount"]=$(( sum_size / 1024 / 1024 ))
        (( total_changesize+="$sum_size" / 1024 / 1024 ))
        scalar="MB"
      elif [[ "$scale" == "gb" ]]; then
        # convert to GB
        fs_changesize["$mount"]=$(( sum_size / 1024 / 1024 / 1024 ))
        (( total_changesize+="$sum_size" / 1024 / 1024 / 1024 ))
        scalar="GB"
      else
      # convert to KB
      fs_changesize["$mount"]=$(( sum_size / 1024 ))
      (( total_changesize+="$sum_size" / 1024 ))
      scalar="KB"
      fi
    else
      fs_changesize["$mount"]=0
    fi
    total_weight=$(( total_weight + fs_weight[$mount] ))
    unset size

    # Get size and inode information for each filesystem
    size=$(df -Pk "$mount"   | awk 'NR==2 {print $3}')    
    [[ "$scalar" == "MB" ]] && size=$(df -P --block-size=1M "$mount"   | awk 'NR==2 {print $3}')
    [[ "$scalar" == "GB" ]] && size=$(df -P --block-size=1G "$mount"   | awk 'NR==2 {print $3}')
    inodes=$(df -Pi "$mount" | awk 'NR==2 {print $3}')

    # avoid division by zero
    (( $inodes == 0 )) && inodes=$(find "$mount" -type f | wc -l)
    (( $inodes == 0 )) && inodes=1

    # Store the size and inode count in associative arrays
    fs_size["$mount"]="$size"
    fs_inodes["$mount"]="$inodes"   

    # Update total size and max inodes
    total_size=$((total_size + size))
    total_inodes=$((total_inodes + inodes))

    putCursor
    echo -n "calculating weight for :                                                                                                               "
    putCursor

done < <(df -P | awk 'NR > 1 {print $6}' | grep -Ev "$exclude")

# calculate change rate
for mount in "${!fs_size[@]}"; do
  weight="${fs_weight[$mount]:-0}"
  change_rate=$(echo "scale=4; ${weight} / ${fs_inodes[$mount]} * 100" | bc)
  fs_changerate["$mount"]="${change_rate}"
done

avg_changerate=$(echo "scale=4; ${total_weight} / ${total_inodes} * 100" | bc )

# display the results
for mount in "${!fs_size[@]}"; do
  printf "chgObj: %'8d |chgRate: %7.2f %% |chgSize: %'20d %2s |totSize: %'20d %2s |totObj: %'18d |Filesystem: %s\n" \
  "${fs_weight[$mount]}" "${fs_changerate[$mount]}" "${fs_changesize[$mount]}" "${scalar}" "${fs_size[$mount]}" "${scalar}" "${fs_inodes[$mount]}" "$mount"
done

# show totals
printf " Total: %'8d |  Total: %7.2f %% |  Total: %'20d %2s |  Total: %'20d %2s | Total: %'18d |Filesystem: %s\n" \
    "${total_weight}" "${avg_changerate}" "${total_changesize}" "${scalar}" "${total_size}" "${scalar}" "${total_inodes}" "(ALL)"
