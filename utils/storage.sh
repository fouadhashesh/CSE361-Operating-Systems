set_hostname() {
  sed -i "s/^hostname=.*/hostname=$1/" state/router.conf
}

set_enable_password() {
  sed -i "s/^enable_password=.*/enable_password=$1/" state/router.conf
}

set_enable_secret() {
  hash=$(echo -n "$1" | sha256sum | cut -d' ' -f1)
  sed -i "s/^enable_secret_hash=.*/enable_secret_hash=$hash/" state/router.conf
}

add_interface() {
  grep -q "^$1," state/interfaces.conf || echo "$1,,," >> state/interfaces.conf
}

set_interface_ip() {
  sed -i "/^$1,/c\\$1,$2,$3,up" state/interfaces.conf
}

set_interface_status() {
  sed -i "/^$1,/c\\$1,$2,$3,$4" state/interfaces.conf
}

add_route() {
  echo "$1,$2,$3" >> state/routes.conf
}
