source utils/prompt.sh
source utils/storage.sh
source utils/logger.sh

while true; do
  if [[ "$INTERRUPTED" -eq 1 ]]; then
    return
  fi

  print_prompt
  read -r cmd a b c d

  case "$cmd" in
    hostname)
      set_hostname "$a"
      log "Hostname set to $a"
      ;;
    enable)
	if [[ "$a" == "password" ]]; then
		[[ -z "$b" ]] && { echo "% Password required"; continue; }
    		set_enable_password "$b"
    		log "Enable password set"
  	elif [[ "$a" == "secret" ]]; then
    		[[ -z "$b" ]] && { echo "% Secret required"; continue; }
    		set_enable_secret "$b"
    		log "Enable secret set"
  	else
    		echo "% Invalid command"
  	fi
      ;;
    interface)
      add_interface "$a"
      CURRENT_IF="$a"
      MODE="interface"
      log "Entered interface $a"
      return
      ;;
    ip)
      [[ "$a" == "route" ]] || { echo "% Invalid command"; continue; }
      add_route "$b" "$c" "$d"
      log "Added static route $b via $d"
      ;;
    exit)
      MODE="privileged"
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

