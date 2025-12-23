
get_hostname() {
  grep hostname state/router.conf | cut -d= -f2
}

print_prompt() {
  host=$(get_hostname)
  case "$MODE" in
    user)        echo -n "$host> " ;;
    privileged) echo -n "$host# " ;;
    config)     echo -n "$host(config)# " ;;
    interface)  echo -n "$host(config-if-$CURRENT_IF)# " ;;
  esac
}
