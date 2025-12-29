#!/bin/bash

# Configuration
ROUTER_IP="192.168.1.2" # Default router IP
ROUTER_PORT=22 # Default router port for ssh
USERNAME="root" # Default username
PASSWORD="root" # Default password for ssh
HOSTNAME="Router" # Default hostname

# Global state
MODE="USER" # USER, PRIVILEGED, CONFIG, INTERFACE
CURRENT_INTERFACE=""
PENDING_COMMANDS=()
PENDING_PASSWORD_CHANGE=""
MockMode=false

# Helper Functions
# Executes a command on the remote router via SSH.
# Uses 'sshpass' if available to handle password authentication automatically.
# In mock mode, it simply prints the command to stdout.
#
# Arguments:
#   $1 - The command string to execute
execute_remote_command() {
    local cmd="$1"
    if [ "$MockMode" = true ]; then
        echo "[SSH MOCK] Executing: $cmd"
        return 0
    fi

    # Using sshpass for password handling if available, else plain ssh
    # Added -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa to support older routers
    local ssh_cmd="ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -p $ROUTER_PORT $USERNAME@$ROUTER_IP"
    
    if command -v sshpass &> /dev/null; then
        echo "Executing remote command via sshpass: $cmd"
        sshpass -p "$PASSWORD" $ssh_cmd "$cmd"
    else
        echo "Executing remote command via ssh: $cmd"
        $ssh_cmd "$cmd"
    fi
}

# Displays the CLI prompt based on the current mode and hostname.
# Format: [Hostname][(mode)]> or #
print_prompt() {
    local prompt_char=">"
    if [ "$MODE" != "USER" ]; then
        prompt_char="#"
    fi
    
    local mode_str=""
    if [ "$MODE" == "CONFIG" ]; then
        mode_str="(config)"
    elif [ "$MODE" == "INTERFACE" ]; then
        mode_str="(config-if)"
    elif [ "$MODE" == "WIRELESS" ]; then
        mode_str="(config-wifi)"
    fi

    echo -n "$HOSTNAME$mode_str$prompt_char "
}
# Handles commands in Global Configuration Mode.
# Supported commands:
#   hostname <name>         - Set router hostname (persisted locally)
#   enable secret <pass>    - Set privileged secret (local hash + remote change)
#   enable password <pass>  - Set privileged password (local plain only)
#   interface <name>        - Enter Interface Configuration Mode
#   wireless                - Enter Wireless Configuration Mode
#   ip route <net> ...      - Add static route
#   exit                    - Return to Privileged Mode
handle_config_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "hostname")
            if [ -n "${cmd[1]}" ]; then
                HOSTNAME="${cmd[1]}"
                PENDING_COMMANDS+=("uci set system.@system[0].hostname='$HOSTNAME'")
                PENDING_COMMANDS+=("uci commit system")
                PENDING_COMMANDS+=("/etc/init.d/system reload")
                
                # Persist hostname locally
                if [ -f "$CONF_FILE" ]; then
                     grep -v "hostname=" "$CONF_FILE" > "$CONF_FILE.tmp"
                     mv "$CONF_FILE.tmp" "$CONF_FILE"
                fi
                echo "hostname=$HOSTNAME" >> "$CONF_FILE"
            else
                 echo "% Invalid command"
            fi
            ;;
        "enable")
            if [ "${cmd[1]}" == "secret" ]; then
                if [ -z "${cmd[2]}" ]; then
                    echo "% Secret required"
                else
                    # 1. Queue remote router password change (User Request)
                    PENDING_PASSWORD_CHANGE="${cmd[2]}"
                    echo "Enable secret (router password) change pending"
                    
                    # 2. Update local CLI enable secret (Modes functionality)
                    mkdir -p "$STATE_DIR"
                    local hash=""
                    if command -v sha256sum &> /dev/null; then
                        hash=$(echo -n "${cmd[2]}" | sha256sum | cut -d' ' -f1)
                    else
                        hash=$(echo -n "${cmd[2]}" | shasum -a 256 | cut -d' ' -f1)
                    fi
                    
                    # Remove existing lines and append new
                    if [ -f "$CONF_FILE" ]; then
                        grep -v "enable_secret_hash=" "$CONF_FILE" | grep -v "enable_password=" > "$CONF_FILE.tmp"
                        mv "$CONF_FILE.tmp" "$CONF_FILE"
                    fi
                    echo "enable_secret_hash=$hash" >> "$CONF_FILE"
                fi
            elif [ "${cmd[1]}" == "password" ]; then
                if [ -z "${cmd[2]}" ]; then
                     echo "% Password required"
                else
                     echo "Enable password set (Local CLI only)"
                     # Update local CLI enable password
                     mkdir -p "$STATE_DIR"
                     if [ -f "$CONF_FILE" ]; then
                        grep -v "enable_secret_hash=" "$CONF_FILE" | grep -v "enable_password=" > "$CONF_FILE.tmp"
                        mv "$CONF_FILE.tmp" "$CONF_FILE"
                     fi
                     echo "enable_password=${cmd[2]}" >> "$CONF_FILE"
                fi
            else
                echo "% Invalid command"
            fi
            ;;
        "ip")
            if [ "${cmd[1]}" == "route" ] && [ -n "${cmd[2]}" ] && [ -n "${cmd[4]}" ]; then
                # ip route <net> <mask?> <gateway> -> ip route add <net> via <gateway>
                # Using positional params from C++ logic: 2=net, 4=gateway
                 local route_cmd="ip route add ${cmd[2]} via ${cmd[4]}"
                 PENDING_COMMANDS+=("$route_cmd")
            else
                 echo "% Invalid command"
            fi
            ;;
        "exit")
            MODE="PRIVILEGED"
            ;;
        "interface")
            if [ -n "${cmd[1]}" ]; then
                CURRENT_INTERFACE="${cmd[1]}"
                MODE="INTERFACE"
            else
                echo "% Invalid command"
            fi
            ;;
        "wireless")
             MODE="WIRELESS"
            ;;
        *)
             echo "% Unknown command"
            ;;
    esac
}

# Handles commands in Wireless Configuration Mode.
# Supported commands:
#   ssid <name>      - Set WiFi SSID
#   password <key>   - Set WiFi password (WPA2)
#   hidden <yes/no>  - Hide SSID
#   channel <num>    - Set WiFi channel
#   exit             - Return to Global Configuration Mode
handle_wireless_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "ssid")
            if [ -n "${cmd[1]}" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].ssid='${cmd[1]}'")
            else
                 echo "% Invalid command"
            fi
            ;;
        "password")
            if [ -n "${cmd[1]}" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].encryption='psk2'")
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].key='${cmd[1]}'")
            else
                 echo "% Invalid command"
            fi
            ;;
        "hidden")
            if [ "${cmd[1]}" == "yes" ] || [ "${cmd[1]}" == "true" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].hidden='1'")
            elif [ "${cmd[1]}" == "no" ] || [ "${cmd[1]}" == "false" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].hidden='0'")
            else
                 echo "% Invalid command (use yes/no)"
            fi
            ;;
        "channel")
            if [ -n "${cmd[1]}" ]; then
                 PENDING_COMMANDS+=("uci set wireless.radio0.channel='${cmd[1]}'")
            else
                 echo "% Invalid command"
            fi
            ;;
        "exit")
            MODE="CONFIG"
            ;;
        *)
            echo "% Unknown command"
            ;;
    esac
}



# State directory
STATE_DIR="state"
CONF_FILE="$STATE_DIR/router_cli.conf"

# Initial state loading
mkdir -p "$STATE_DIR"
touch "$CONF_FILE"

# Persist connection info for monitor (Harmonization)
if [ -f "$CONF_FILE" ]; then
    grep -vE "^(router_ip|router_port|username|password)=" "$CONF_FILE" > "$CONF_FILE.tmp"
    mv "$CONF_FILE.tmp" "$CONF_FILE"
fi
echo "router_ip=$ROUTER_IP" >> "$CONF_FILE"
echo "router_port=$ROUTER_PORT" >> "$CONF_FILE"
echo "username=$USERNAME" >> "$CONF_FILE"
echo "password=$PASSWORD" >> "$CONF_FILE"

# Load hostname if exists
SAVED_HOSTNAME=$(grep "^hostname=" "$CONF_FILE" | cut -d= -f2)
if [ -n "$SAVED_HOSTNAME" ]; then
    HOSTNAME="$SAVED_HOSTNAME"
fi

# Verifies the user's password against the stored local configuration.
# Checks for both plaintext password (enable_password) and SHA256/SHASum hash (enable_secret_hash).
# Returns 0 on success, 1 on failure.
check_enable_auth() {
    mkdir -p "$STATE_DIR"
    touch "$CONF_FILE"
    
    local plain=$(grep "^enable_password=" "$CONF_FILE" | cut -d= -f2)
    local hash=$(grep "^enable_secret_hash=" "$CONF_FILE" | cut -d= -f2)
    
    if [ -z "$plain" ] && [ -z "$hash" ]; then
        return 0
    fi
    
    read -s -p "Password: " input
    echo
    
    if [ -n "$hash" ]; then
        # Check for sha256sum or shasum
        if command -v sha256sum &> /dev/null; then
             local calc=$(echo -n "$input" | sha256sum | cut -d' ' -f1)
        else
             local calc=$(echo -n "$input" | shasum -a 256 | cut -d' ' -f1)
        fi
        
        if [ "$calc" == "$hash" ]; then
            return 0
        fi
    else
        if [ "$input" == "$plain" ]; then
            return 0
        fi
    fi
    
    return 1
}

# Mode Handlers
# Handles commands in User Mode (default mode).
# Supported commands:
#   enable - Switch to Privileged Mode (requires auth)
#   exit   - Terminate the CLI session
handle_user_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "enable")
            if check_enable_auth; then
                MODE="PRIVILEGED"
                echo "% Entered privileged mode"
            else
                echo "% Access denied"
            fi
            ;;
        "exit")
            echo "Bye!"
            exit 0
            ;;
        *)
            echo "% Unknown command"
            ;;
    esac
}

# Handles commands in Privileged Exec Mode.
# Supported commands:
#   disable                 - Return to User Mode
#   configure terminal      - Enter Global Configuration Mode
#   show running-config     - Display pending commands and password changes
#   show ip route           - Display remote routing table
#   show ip interface       - Display remote interface IPs
#   apply                   - Execute all pending commands on remote router
#   exit                    - Return to User Mode
handle_privileged_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "disable")
            MODE="USER"
            echo "% Returned to user mode"
            ;;
        "configure"|"conf")
            if [ "${cmd[1]}" == "terminal" ] || [ "${cmd[1]}" == "t" ]; then
                MODE="CONFIG"
                echo "% Entered config mode"
            else
                echo "% Invalid command"
            fi
            ;;
        "show")
            if [ "${cmd[1]}" == "running-config" ]; then
                echo "! Pending commands:"
                for pending in "${PENDING_COMMANDS[@]}"; do
                    echo "$pending"
                done
                if [ -n "$PENDING_PASSWORD_CHANGE" ]; then
                    echo "Change password to: $PENDING_PASSWORD_CHANGE"
                fi
            elif [ "${cmd[1]}" == "ip" ] && [ "${cmd[2]}" == "route" ]; then
                execute_remote_command "ip route show"
            elif [ "${cmd[1]}" == "ip" ] && [ "${cmd[2]}" == "interface" ]; then
                execute_remote_command "ip address show"
            else
                 echo "% Invalid command"
            fi
            ;;
        "apply")
            if [ ${#PENDING_COMMANDS[@]} -eq 0 ] && [ -z "$PENDING_PASSWORD_CHANGE" ]; then
                echo "% No changes to apply"
            else
                echo "Applying changes..."
                for pending in "${PENDING_COMMANDS[@]}"; do
                    execute_remote_command "$pending"
                done
                PENDING_COMMANDS=()
                
                if [ -n "$PENDING_PASSWORD_CHANGE" ]; then
                     echo "Applying password change..."
                     # Using printf to pipe newline-separated password to passwd command
                     local pass_cmd="printf \"$PENDING_PASSWORD_CHANGE\\n$PENDING_PASSWORD_CHANGE\" | passwd root"
                     execute_remote_command "$pass_cmd"
                     if [ $? -eq 0 ]; then
                         PASSWORD="$PENDING_PASSWORD_CHANGE"
                         echo "Password updated successfully."
                     else
                         echo "% Failed to update password."
                     fi
                     PENDING_PASSWORD_CHANGE=""
                fi
                
                # Notify monitor to fetch updates
                if [ -n "$MONITOR_PID" ]; then
                    kill -SIGUSR1 "$MONITOR_PID" 2>/dev/null
                fi
            fi
            ;;
        "exit")
            MODE="USER"
            ;;
        *)
            echo "% Unknown command"
            ;;
    esac
}

# Handles commands in Global Configuration Mode.
# Supported commands:
#   hostname <name>         - Set router hostname (persisted locally)
#   enable secret <pass>    - Set privileged secret (local hash + remote change)
#   enable password <pass>  - Set privileged password (local plain only)
#   interface <name>        - Enter Interface Configuration Mode
#   ip route <net> ...      - Add static route
#   exit                    - Return to Privileged Mode
handle_config_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "hostname")
            if [ -n "${cmd[1]}" ]; then
                HOSTNAME="${cmd[1]}"
                PENDING_COMMANDS+=("uci set system.@system[0].hostname='$HOSTNAME'")
                PENDING_COMMANDS+=("uci commit system")
                PENDING_COMMANDS+=("/etc/init.d/system reload")
                
                # Persist hostname locally
                if [ -f "$CONF_FILE" ]; then
                     grep -v "hostname=" "$CONF_FILE" > "$CONF_FILE.tmp"
                     mv "$CONF_FILE.tmp" "$CONF_FILE"
                fi
                echo "hostname=$HOSTNAME" >> "$CONF_FILE"
            else
                 echo "% Invalid command"
            fi
            ;;
        "enable")
            if [ "${cmd[1]}" == "secret" ]; then
                if [ -z "${cmd[2]}" ]; then
                    echo "% Secret required"
                else
                    # 1. Queue remote router password change (User Request)
                    PENDING_PASSWORD_CHANGE="${cmd[2]}"
                    echo "Enable secret (router password) change pending"
                    
                    # 2. Update local CLI enable secret (Modes functionality)
                    mkdir -p "$STATE_DIR"
                    local hash=""
                    if command -v sha256sum &> /dev/null; then
                        hash=$(echo -n "${cmd[2]}" | sha256sum | cut -d' ' -f1)
                    else
                        hash=$(echo -n "${cmd[2]}" | shasum -a 256 | cut -d' ' -f1)
                    fi
                    
                    # Remove existing lines and append new
                    if [ -f "$CONF_FILE" ]; then
                        grep -v "enable_secret_hash=" "$CONF_FILE" | grep -v "enable_password=" > "$CONF_FILE.tmp"
                        mv "$CONF_FILE.tmp" "$CONF_FILE"
                    fi
                    echo "enable_secret_hash=$hash" >> "$CONF_FILE"
                fi
            elif [ "${cmd[1]}" == "password" ]; then
                if [ -z "${cmd[2]}" ]; then
                     echo "% Password required"
                else
                     echo "Enable password set (Local CLI only)"
                     # Update local CLI enable password
                     mkdir -p "$STATE_DIR"
                     if [ -f "$CONF_FILE" ]; then
                        grep -v "enable_secret_hash=" "$CONF_FILE" | grep -v "enable_password=" > "$CONF_FILE.tmp"
                        mv "$CONF_FILE.tmp" "$CONF_FILE"
                     fi
                     echo "enable_password=${cmd[2]}" >> "$CONF_FILE"
                fi
            else
                echo "% Invalid command"
            fi
            ;;
        "interface")
            if [ -n "${cmd[1]}" ]; then
                CURRENT_INTERFACE="${cmd[1]}"
                MODE="INTERFACE"
            else
                echo "% Invalid command"
            fi
            ;;
        "ip")
            if [ "${cmd[1]}" == "route" ] && [ -n "${cmd[2]}" ] && [ -n "${cmd[4]}" ]; then
                # ip route <net> <mask?> <gateway> -> ip route add <net> via <gateway>
                # Using positional params from C++ logic: 2=net, 4=gateway
                 local route_cmd="ip route add ${cmd[2]} via ${cmd[4]}"
                 PENDING_COMMANDS+=("$route_cmd")
            else
                 echo "% Invalid command"
            fi
            ;;
        "wireless")
             MODE="WIRELESS"
            ;;
        "exit")
            MODE="PRIVILEGED"
            ;;
        *)
             echo "% Unknown command"
            ;;
    esac
}

# Handles commands in Interface Configuration Mode.
# Supported commands:
#   ip address <ip> <mask>  - Set interface IP and mask
#   shutdown                - Disable interface
#   no shutdown             - Enable interface
#   exit                    - Return to Global Configuration Mode
handle_interface_mode() {
    local cmd=($1)
    
    # Ensure interface config file exists
    local IF_CONF="$STATE_DIR/interfaces.conf"
    mkdir -p "$STATE_DIR"
    touch "$IF_CONF"
    
    # Escape interface name for sed
    local IF_ESC="${CURRENT_INTERFACE//\//\\/}"

    case "${cmd[0]}" in
        "ip")
             # ip address <ip> <mask> -> ifconfig <iface> <ip> netmask <mask> up
             if [ "${cmd[1]}" == "address" ] && [ -n "${cmd[2]}" ] && [ -n "${cmd[3]}" ]; then
                  local if_cmd="ifconfig $CURRENT_INTERFACE ${cmd[2]} netmask ${cmd[3]} up"
                  PENDING_COMMANDS+=("$if_cmd")
                  
                  # Update local interface state (Modes functionality)
                  # If entry exists, replace it. If not, append it?
                  # modes/interface.sh assumes entry exists: sed -i "/^${IF_ESC},/c\\${CURRENT_IF},${b},${c},down"
                  # We will append if not found for robustness, or just try sed
                  if grep -q "^$CURRENT_INTERFACE," "$IF_CONF"; then
                      # Mac sed differs from GNU sed. Using text file logic compatible with both if possible or just assuming GNU sed as per standard linux router environment? 
                      # The user is on Mac (OS version: mac). Mac sed requires -i ''.
                      if [[ "$OSTYPE" == "darwin"* ]]; then
                          sed -i '' "/^${IF_ESC},/s/.*/${CURRENT_INTERFACE},${cmd[2]},${cmd[3]},up/" "$IF_CONF"
                      else
                          sed -i "/^${IF_ESC},/s/.*/${CURRENT_INTERFACE},${cmd[2]},${cmd[3]},up/" "$IF_CONF"
                      fi
                  else
                      echo "${CURRENT_INTERFACE},${cmd[2]},${cmd[3]},up" >> "$IF_CONF"
                  fi
             else
                  echo "% Invalid command"
             fi
             ;;
        "shutdown")
             PENDING_COMMANDS+=("ifconfig $CURRENT_INTERFACE down")
             if grep -q "^$CURRENT_INTERFACE," "$IF_CONF"; then
                  if [[ "$OSTYPE" == "darwin"* ]]; then
                      sed -i '' "/^${IF_ESC},/s/up/down/" "$IF_CONF"
                  else
                      sed -i "/^${IF_ESC},/s/up/down/" "$IF_CONF"
                  fi
             fi
             ;;
        "no")
             if [ "${cmd[1]}" == "shutdown" ]; then
                 PENDING_COMMANDS+=("ifconfig $CURRENT_INTERFACE up")
                 if grep -q "^$CURRENT_INTERFACE," "$IF_CONF"; then
                     if [[ "$OSTYPE" == "darwin"* ]]; then
                         sed -i '' "/^${IF_ESC},/s/down/up/" "$IF_CONF"
                     else
                         sed -i "/^${IF_ESC},/s/down/up/" "$IF_CONF"
                     fi
                 fi
             else
                 echo "% Invalid command"
             fi
             ;;
        "exit")
             MODE="CONFIG"
             CURRENT_INTERFACE=""
             ;;
        *)
             echo "% Unknown command"
             ;;
    esac
}

# Handles commands in Wireless Configuration Mode.
# Supported commands:
#   ssid <name>      - Set WiFi SSID
#   password <key>   - Set WiFi password (WPA2)
#   hidden <yes/no>  - Hide SSID
#   channel <num>    - Set WiFi channel
#   exit             - Return to Global Configuration Mode
handle_wireless_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "ssid")
            if [ -n "${cmd[1]}" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].ssid='${cmd[1]}'")
                 PENDING_COMMANDS+=("uci commit wireless")
                 PENDING_COMMANDS+=("wifi reload")
            else
                 echo "% Invalid command"
            fi
            ;;
        "password")
            if [ -n "${cmd[1]}" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].encryption='psk2'")
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].key='${cmd[1]}'")
                 PENDING_COMMANDS+=("uci commit wireless")
                 PENDING_COMMANDS+=("wifi reload")
            else
                 echo "% Invalid command"
            fi
            ;;
        "hidden")
            if [ "${cmd[1]}" == "yes" ] || [ "${cmd[1]}" == "true" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].hidden='1'")
                 PENDING_COMMANDS+=("uci commit wireless")
                 PENDING_COMMANDS+=("wifi reload")
            elif [ "${cmd[1]}" == "no" ] || [ "${cmd[1]}" == "false" ]; then
                 PENDING_COMMANDS+=("uci set wireless.@wifi-iface[0].hidden='0'")
                 PENDING_COMMANDS+=("uci commit wireless")
                 PENDING_COMMANDS+=("wifi reload")
            else
                 echo "% Invalid command (use yes/no)"
            fi
            ;;
        "channel")
            if [ -n "${cmd[1]}" ]; then
                 PENDING_COMMANDS+=("uci set wireless.radio0.channel='${cmd[1]}'")
                 PENDING_COMMANDS+=("uci commit wireless")
                 PENDING_COMMANDS+=("wifi reload")
            else
                 echo "% Invalid command"
            fi
            ;;
        "exit")
            MODE="CONFIG"
            ;;
        *)
            echo "% Unknown command"
            ;;
    esac
}

# Main

if [ "$1" == "--clean" ]; then
    rm -rf "$STATE_DIR"
    echo "[INFO] State cleared."
fi
 
if [ "$1" == "--mock" ]; then
    MockMode=true
    echo "[INFO] Running in MOCK mode. No real SSH connection."
fi

# Basic check for SSH connectivity if not mock (simplified)
if [ "$MockMode" = false ]; then
    # Netcat check to see if port is open
    nc -z -w 2 "$ROUTER_IP" "$ROUTER_PORT"
    if [ $? -ne 0 ]; then
         echo "Fatal: Could not connect to router. Use --mock for testing."
         # In strict C++ version it exits, here we also exit to match
         exit 1
    fi
fi

# --- Router Monitor Integration ---
# Compile if source exists and binary doesn't (or source is newer)
if [ -f "router_monitor.c" ]; then
    if [ ! -f "router_monitor" ] || [ "router_monitor.c" -nt "router_monitor" ]; then
         echo "[INFO] Compiling router_monitor..."
         gcc router_monitor.c -o router_monitor
         if [ $? -ne 0 ]; then
             echo "[WARN] Failed to compile router_monitor. Continuing without it."
         fi
    fi
fi

MONITOR_PID=""
if [ -f "router_monitor" ]; then
    # Redirect output to log file
    ./router_monitor >> router_monitor.log 2>&1 &
    MONITOR_PID=$!
    # Ensure monitor is killed on exit
    trap "kill $MONITOR_PID 2>/dev/null" EXIT
    echo "[INFO] Started router_monitor (PID: $MONITOR_PID). Logs at router_monitor.log"
else
    echo "[WARN] router_monitor binary not found."
fi
# ----------------------------------

while true; do
    print_prompt
    read -r line || break # Handle EOF
    
    # Trim leading/trailing whitespace
    line=$(echo "$line" | xargs)
    if [ -z "$line" ]; then
        continue
    fi

    case "$MODE" in
        "USER") handle_user_mode "$line" ;;
        "PRIVILEGED") handle_privileged_mode "$line" ;;
        "CONFIG") handle_config_mode "$line" ;;
        "INTERFACE") handle_interface_mode "$line" ;;
        "WIRELESS") handle_wireless_mode "$line" ;;
    esac
done
