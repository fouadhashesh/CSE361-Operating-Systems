source utils/prompt.sh
source utils/logger.sh

while true; do
  if [[ "$INTERRUPTED" -eq 1 ]]; then
    return
  fi

  print_prompt
  read -r cmd a b c

  case "$cmd" in
    disable)
      MODE="user"
      log "Returned to user mode"
      return
      ;;
    configure)
      [[ "$a" == "terminal" ]] || { echo "% Invalid command"; continue; }
      MODE="config"
      log "Entered config mode"
      return
      ;;
    conf)
      [[ "$a" == "t" ]] || { echo "% Invalid command"; continue; }
      MODE="config"
      log "Entered config mode"
      return
      ;;
    show)
      if [[ "$a" == "running-config" ]]; then
        cat state/router.conf
        echo "!"
        cat state/interfaces.conf
        echo "!"
        cat state/routes.conf
      elif [[ "$a" == "ip" && "$b" == "route" ]]; then
        cat state/routes.conf
      else
        echo "% Invalid command"
      fi
      ;;
    apply)
      log "Applied configuration"
      sudo utils/apply.sh
      ;;
    exit)
      MODE="user"
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

