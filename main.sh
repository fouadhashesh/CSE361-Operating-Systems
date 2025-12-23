#!/bin/bash

export MODE="user"
export CURRENT_IF=""
export INTERRUPTED=0

mkdir -p state
touch state/router.log
rm -f state/signal.flag

# Start C signal handler once
./c_helpers/signal_handler &
SIGNAL_PID=$!

# Cleanup on exit (Ctrl+C will trigger this naturally)
trap "kill $SIGNAL_PID 2>/dev/null; exit" EXIT

# Ctrl + Z → return to privileged mode (Cisco-like)
trap '
  INTERRUPTED=1
  MODE="privileged"
  CURRENT_IF=""
  echo
  echo "% Returned to privileged mode"
' SIGTSTP

while true; do
  INTERRUPTED=0

  case "$MODE" in
    user)        source modes/user.sh ;;
    privileged) source modes/privileged.sh ;;
    config)      source modes/config.sh ;;
    interface)   source modes/interface.sh ;;
  esac
done

