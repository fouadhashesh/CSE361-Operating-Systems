source utils/prompt.sh
source utils/logger.sh

while true; do
  if [[ "$INTERRUPTED" -eq 1 ]]; then
    return
  fi

  print_prompt
  read -r cmd a b c

  IF_ESC="${CURRENT_IF//\//\\/}"

  case "$cmd" in
    ip)
      [[ "$a" == "address" ]] || { echo "% Invalid command"; continue; }
      sed -i "/^${IF_ESC},/c\\${CURRENT_IF},${b},${c},down" state/interfaces.conf
      log "Interface $CURRENT_IF IP set to $b $c"
      ;;
    shutdown)
      sed -i "/^${IF_ESC},/s/up/down/" state/interfaces.conf
      log "Interface $CURRENT_IF shutdown"
      ;;
    no)
      [[ "$a" == "shutdown" ]] || { echo "% Invalid command"; continue; }
      sed -i "/^${IF_ESC},/s/down/up/" state/interfaces.conf
      log "Interface $CURRENT_IF enabled"
      ;;
    exit)
      MODE="config"
      CURRENT_IF=""
      return
      ;;
    "")
      continue
      ;;
    *)
      echo "% Unknown command"
      ;;
  esac
done

