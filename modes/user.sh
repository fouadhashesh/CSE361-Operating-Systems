source utils/prompt.sh
source utils/logger.sh

while true; do
  if [[ "$INTERRUPTED" -eq 1 ]]; then
    return
  fi

  print_prompt
  read -r cmd

  case "$cmd" in
    enable)
      source utils/auth.sh
      if [[ $? -ne 0 ]]; then
        echo "% Access denied"
        log "Enable authentication failed"
        continue
      fi
      log "Entered privileged mode"
      MODE="privileged"
      return
      ;;
    exit)
      log "Router exited"
      exit 0
      ;;
    "")
      continue
      ;;
    *)
      echo "% Unknown command"
      ;;
  esac
done

