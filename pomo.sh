#!/bin/bash

# Copyright (c) 2013, James Spencer.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#--- pomo.sh ---

# pomo.sh is a simple Pomodoro timer.  It works by creating a file ($POMO) and
# inspecting the modification timestamp of that file to determine for how long
# a Pomodoro block has been running.  Pausing a Pomodoro block works by storing
# how long the Pomodoro block has been running in the $POMO file.  A paused
# Pomodoro block can then be resumed by updating the modification timestamp of
# the POMO file accordingly.

#--- Check environment ---
if [ "$(uname)" == "Darwin" ] || [ "${POMO_PREFIX_CMDS}" == "true" ]; then
    # Use GNU coreutils installed with a prefix
    DATE_CMD="gdate"
    STAT_CMD="gstat"
else
    DATE_CMD="date"
    STAT_CMD="stat"
fi

#--- Pomodoro functions ---

# Set the variable track_file_path based on current task name or $TASK
function set_track_file_path {
    unset track_file_path

    if [[ ! -z $TASK ]]; then
       export task=$TASK
    else
       [[ -e ${TASK_FILE} ]] && export task=$(cat ${TASK_FILE})
    fi

    [[ ! -z $task ]] && export track_file_path="${TASK_DIR}/$(echo $task | md5sum | awk '{print $1}').task"
}


function touch_track_file {
   set_track_file_path

   if [[ ! -z  ${track_file_path} ]]; then 
    
      # If the track file does not exist, then create it and write the task name
      # task name is also set upstream
      [[ ! -e ${track_file_path} ]] && echo ${task} > ${track_file_path}

      touch ${track_file_path}

       # Insert daystamp if it does not exist already
       day=$(date +'%Y-%m-%d')
       d=$(grep ${day} ${track_file_path})
       if [[ -z $d ]]; then
          printf "\n%s:" $day >> ${track_file_path}
       fi
   fi
}

function increment_track_file {
  [[ -z ${work_time} ]] && work_time=$WORK_TIME  
 
  touch_track_file && [[ ! -z  ${track_file_path} ]] && printf " %s" "${work_time}" >> ${track_file_path}
}

function increment_track_file_partial {
   running=$(pomo_stat)
   m=$((running/60))
   [[ ${m} != "0" ]] && touch_track_file && [[ ! -z  ${track_file_path} ]] && printf " %s" "${m}" >> ${track_file_path}
}

function pomo_start {
    # Start new pomo block (work+break cycle).
    test -e "$(dirname -- "$POMO")" || mkdir -p "$(dirname -- "$POMO")"
    :> "$POMO" # remove saved time stamp due to a pause.
    touch "$POMO"
    
    # Process task
    pomo_task

}

function pomo_add {
  [[ ! -z "$TASK" ]] && increment_track_file
}

function pomo_task {
  if [[ ! -z "$TASK" ]]; then
    [[ -f ${TASK_FILE} ]] && increment_track_file_partial && rm -f "${TASK_FILE}"
    touch ${TASK_FILE} && echo $TASK > ${TASK_FILE}
    touch_track_file
  fi

  print_current_task
}

function get_current_task {
  current_task=""
  if [[ -f "${TASK_FILE}" ]]; then
     current_task="$(cat ${TASK_FILE})"
  else
     current_task="No task set"
  fi
}

function print_current_task {
    get_current_task
    result="${current_task}"

    if [[ -f "${TASK_FILE}" ]]; then
       set_track_file_path
       if [[ ! -z ${track_file_path} ]]; then
         day="$(date +'%Y-%m-%d')"
         stars="$(grep ${day} ${track_file_path} | awk -F';' '{print $NF}')"
	     printf -v result "%s\n%s\n" "${current_task}" "${stars}"
       fi
    fi

    echo "${result}"
}

function pomo_isstopped {
    # Return 0 if stopped, 1 otherwise.
    # pomo.sh is stopped if the POMO file does not exist.
    [[ ! -e "$POMO" ]]
    return $?
}

function pomo_stop {
    pomo_clock

    # Increment partial if in the middle of a work block
    [[ -e ${TASK_FILE} ]] && [[ $prefix == "W" ]] && increment_track_file_partial

    # Stop pomo cycles.
    rm -f "$POMO"
}

function pomo_stamp {
    # Set the timestamp of the POMO file to $1 seconds ago.
    ago=$1
    mtime=$(${DATE_CMD} --date "@$(( $(date +%s) - ago))" +%m%d%H%M.%S)
    :> "$POMO" # erase saved time stamp due to a pause.
    touch -m -t "$mtime" "$POMO"
}

function pomo_ispaused {
    # Return 0 if paused, 1 otherwise.
    # pomo.sh is paused if the POMO file contains any information.
    [[ $(wc -l < "$POMO") -gt 0 ]]
    return $?
}

function pomo_pause {
    # Toggle the pause status on the POMO file.
    running=$(pomo_stat)
    if pomo_isstopped || pomo_ispaused; then
        # Restart a stopped/paused pomo block by updating the time stamp of the POMO
        # file.
        pomo_stamp "$running"
	echo "resumed"
    else
        # Pause a pomo block.
        echo "$running" > "$POMO"
    fi
}

function pomo_update {
    # Update the time stamp on POMO a new cycle has started.
    running=$(pomo_stat)
    block_time=$(( (WORK_TIME+BREAK_TIME)*60 ))
    if [[ $running -ge $block_time ]]; then
        ago=$(( running % block_time )) # We should've started the new cycle a while ago?
        mtime=$(${DATE_CMD} --date "@$(( $(date +%s) - ago))" +%m%d%H%M.%S)
        touch -m -t "$mtime" "$POMO"
    fi
}

function pomo_stat {
    # Return number of seconds since start of pomo block (work+break cycle).
    [[ -e "$POMO" ]] && running=$(cat "$POMO") || running=0
    if [[ -z $running ]]; then
        pomo_start=$(${STAT_CMD} -c +%Y "$POMO")
        now=$(${DATE_CMD} +%s)
        running=$((now-pomo_start))
    fi
    echo $running
}

function pomo_clock {
    # Print out how much time is remaining in block.
    # WMM:SS indicates MM:SS left in the work block.
    # BMM:SS indicates MM:SS left in the break block.
    if ! pomo_isstopped; then
        pomo_update
        running=$(pomo_stat)
        left=$(( WORK_TIME*60 - running ))
        if [[ $left -lt 0 ]]; then
            left=$(( left + BREAK_TIME*60 ))
            prefix=B
        else
            prefix=W
        fi
        pomo_ispaused && prefix=P$prefix
        min=$(( left / 60 ))
        sec=$(( left - 60*min ))

        get_current_task
        printf -v clock "%2s%02d:%02d - %s" $prefix $min $sec "${current_task}"
    else
        printf -v clock "  --:--"
    fi

    echo "${clock}"
}

function pomo_status {
    while true; do
        pomo_clock
        sleep 300
    done
}

function pomo_msg {
    # Send a message using the GUI or console at the end of the next
    # work or break block.  This requires a Pomodoro session to
    # have already been started...
    [[ -e "$POMO" ]] || return 1
    pomo_update
    running=$(pomo_stat)
    while true; do
        left=$(( WORK_TIME*60 - running ))
        work=true
        if [[ $left -lt 0 ]]; then
            left=$(( left + BREAK_TIME*60 ))
            work=false
        fi
        sleep $left
        # pomo_stat is time from the start of the work+block cycle.
        # 1. If switching from work->break then stat >= running + left.
        # 2. If switching from break->work then either
        #    stat >= running + left (haven't updated timestamp) or
        #    stat < running (have just updated the timestamp from a
        #    separate pomo call, e.g. using pomo status).
        stat=$(pomo_stat)
        [[ $stat -ge $(( running + left )) ]] && break
        $work || { [[ $stat -lt $running ]] && break; }
        running=$stat
    done
    if [[ $(( stat - running - left )) -le 1 ]]; then
        if $work; then
            increment_track_file
            $MSG_CALLBACK 0  # end of work block
        else
            $MSG_CALLBACK 1  # end of break block
        fi
    fi
    return 0
}

function pomo_log {
  echo "Task Directory: ${TASK_DIR}. Displaying all log entries"
  echo "--"
  tasks=$(ls ${TASK_DIR}/*.task)
  for t in $tasks
  do
    printf "%s\n" "$t"
    cat $t
    printf "\n"
  done
}

function pomo_day {
  echo "Task Directory: ${TASK_DIR}. Displaying log entries from today."
  day=$(date +'%Y-%m-%d')
  tasks=$(ls ${TASK_DIR}/*.task)
  for t in $tasks
  do
    r=$(grep $day $t)
    if [[ ! -z $r ]]; then
      printf "%s\n" "--"
      printf "%s (%s)\n" "$(head -n 1 $t)" "$t"
      echo $r
    fi
  done
}

function pomo_search {
  echo "Searching task Directory: ${TASK_DIR} for task $TASK"
  tasks=$(ls ${TASK_DIR}/*.task)
  for t in $tasks
  do
    r=$(grep -i $TASK $t)
    if [[ ! -z $r ]]; then
      printf "%s\n" "--"
      printf "%s (%s)\n" "$(head -n 1 $t)" "$t"
      echo $r
    fi
  done
}

function pomo_notify {
    while true; do
        if pomo_msg; then
            # sleep for a second so that the timestamp of POMO is not the
            # current time (i.e. allow next unit to start).
            sleep 1
        else
            sleep 60
        fi
    done
}

function pomo_msg_callback {
    block_type=$1
    if [[ $block_type -eq 0 ]]; then
        msg='End of a work period. Time for a break!'
    elif [[ $block_type -eq 1 ]]; then
        msg='End of a break period. Time for work!'
    else
        echo "Unknown block type"
        exit 1
    fi
    send_msg "$msg"
}

# This function will send an audible notification via a MacOS system sound
function pomo_macos_notify {

    # Play a sound if macos
    [[ $(uname) == "Darwin" ]] && afplay /System/Library/Sounds/Glass.aiff

    # Print messages
    printf '~~~\n%s\n~~~\n%s\n~~~\n%s\n~~~\n' "$(fortune)" "$(python3 /Users/kawsark/tools/wisdom.py)" "$($HOME/tools/ticker.sh)"
}


function pomo_msg_callback_echo {
    block_type=$1
    if [[ $block_type -eq 0 ]]; then
        msg='End of a work period. Time for a break!'
    elif [[ $block_type -eq 1 ]]; then
        msg='End of a break period. Time for work!'
    else
        echo "Unknown block type"
        exit 1
    fi
    echo "$msg"
    print_current_task

    pomo_macos_notify
}

# This function will stop the current task once end of a work period is reached
function pomo_msg_callback_auto_stop {
    block_type=$1
    if [[ $block_type -eq 0 ]]; then
        msg="End of a work period. Auto stopping current task: Time $(date +%T)"
        print_current_task
        pomo_macos_notify
        pomo_stop
    else
        msg='Previous task was auto stopped'
    fi
    echo "$msg"
}

function send_msg {
    if [ "$(uname)" == "Darwin" ]; then
        osascript -e "tell app \"System Events\" to display dialog \"${1}\"" &> /dev/null
    elif command -v notify-send &> /dev/null; then
        notify-send -a "Pomodoro" "${1}"
    else
        echo "${1}"
    fi
}

#--- Help ---

function pomo_usage {
    # Print out usage message.
    cat <<END
pomo.sh [-h] [-c file] [start | stop | pause | clock | status | notify | usage | log | day | add | task | search]

pomo.sh - a simple Pomodoro timer.

Options:

-c file
    Specify the path to the config file containing variable definitions.
-h
    Print this usage message.

Actions:

start
    Start Pomodoro timer. 
    Optionally provide a task name. E.g. pomo.sh start training
stop
    Stop Pomodoro timer.
pause
    Pause a running Pomodoro timer or restart a paused Pomodoro timer.
clock
    Print how much time (minutes and seconds) is remaining in the current
    Pomodoro cycle.  A prefix of B indicates a break period, a prefix of
    W indicates a work period and a prefix of P indicates the current period is
    paused.
notify
    Raise a notification at the end of every Pomodoro work and break block in
    an infinite loop.  Requires notify-send (linux) or osascript (OS X).
status
    Continuously print the current status of the Pomodoro timer once a second,
    in the same format as the clock action.
log
    Prints all tasks that were logged
day
    Same as log but print today's entries only
add
    Adds a work block to specified task
task
    Changes the current task
usage
    Print this usage message.
search
    Look for a previous task name

Note that the notify and status actions (unlike all others) do not terminate and
are best run in the background.

Environment variables:

POMO_CONFIG
    Location of the config file. Default: \$XDG_CONFIG_HOME/pomo.cfg. Can also
    be set using the -c option.
POMO_FILE
    Location of the Pomodoro file used to store the duration of the Pomodoro
    period (mostly using timestamps).  Multiple Pomodoro timers can be run by
    using different files.  Default: \$HOME/.local/share/pomo.
POMO_WORK_TIME
    Duration of the work period in minutes.  Default: 25.
POMO_BREAK_TIME
    Duration of the break period in minutes.  Default: 5.
POMO_MSG_CALLBACK
   Function to call at the end of a period, with argument of 0 for end of a
   work period and 1 for the end of a break period. Default: pomo_msg_callback.

Environment variables other than POMO_CONFIG can also be set in POMO_CONFIG,
which is sourced if it exists.
END
}

#--- Command-line interface ---

action=
config=${POMO_CONFIG:-"$XDG_CONFIG_HOME/pomo.cfg"}
while getopts "hc:" arg; do
    case $arg in
	c)
	    config=$OPTARG
	    ;;
        h|?)
            action=usage
            ;;
    esac
done
shift $((OPTIND-1))

actions="start stop pause clock usage notify status log day add task search"
for act in $actions; do
    if [[ $act == "$1" ]]; then
        action=$act
        [[ ! -z "$2" ]] && export TASK=$2
        [[ ! -z "$3" ]] && [[ $act == "add" ]] && export work_time=$3
        break
    fi
done

#--- Configuration (can be set via environment variables) ---

[[ -e ${config} ]] && source "${config}"
POMO=${POMO_FILE:-"$HOME/.local/share/pomo"}
WORK_TIME=${POMO_WORK_TIME:-25}
BREAK_TIME=${POMO_BREAK_TIME:-5}
MSG_CALLBACK=${POMO_MSG_CALLBACK:-pomo_msg_callback}
TASK_DIR=$HOME/.local/share
TASK_FILE=${TASK_DIR}/pomo_task.txt

#--- Run! ---

if [[ -n $action ]]; then
    pomo_"$action"
else
    [[ $# -gt 0 ]] && echo "Unknown option/action: $1." || echo "Action not supplied."
    pomo_usage
fi
