#!/bin/bash

PREPEND_TIMESTAMP_PY='prepend-timestamp.py'
if ! curl -LfsSo $PREPEND_TIMESTAMP_PY https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/util/$PREPEND_TIMESTAMP_PY; then
    echo "Error getting script dependency: $PREPEND_TIMESTAMP_PY"
    exit 1
fi

echo_green() {
  local lightgreen='\033[1;32m'
  local nocolor='\033[0m'
  echo -e "${lightgreen}$1${nocolor}"
}

echo_red() {
  local lightred='\033[1;31m'
  local nocolor='\033[0m'
  echo -e "${lightred}$1${nocolor}"
}

file_timestamp() {
  local python=$(which python3 || which python)
  $python -c "from datetime import datetime; print(datetime.now().strftime('%Y%m%d-%H%M%S%f'))"
}

prepend_timestamp() {
  local python=$(which python3 || which python)
  $python $PREPEND_TIMESTAMP_PY
}

log_good() {
  echo_green "[$0] $1"
}

log() {
  local lightgrey='\033[0;37m'
  local darkgrey='\033[1;30m'
  local nocolor='\033[0m'
  echo -e "${darkgrey}[$0] $1${nocolor}"
}

log_bad() {
  echo_red "[$0] $1"
}

div() {
  echo "---"
}

set_log_file() {
  if (( $# == 1 )) && [[ "$1" != "" ]]; then
    # Use the specified log file.
    local log_file="$1"
  else
    return 1
  fi
  # Capture STDOUT and STDERR to a log file, and display to the terminal.
  exec &> /dev/tty
  exec &> >(prepend_timestamp | tee -a "$log_file")
}
