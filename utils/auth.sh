#!/bin/bash

plain=$(grep enable_password state/router.conf | cut -d= -f2)
hash=$(grep enable_secret_hash state/router.conf | cut -d= -f2)

# No password or secret set → allow enable without prompt
if [[ -z "$plain" && -z "$hash" ]]; then
  return 0
fi

# Ask for password only when needed
read -s -p "Password: " input
echo

if [[ -n "$hash" ]]; then
  calc=$(echo -n "$input" | sha256sum | cut -d' ' -f1)
  [[ "$calc" == "$hash" ]] && return 0 || return 1
else
  [[ "$input" == "$plain" ]] && return 0 || return 1
fi

