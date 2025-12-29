#!/bin/bash

# Configuration
ROUTER_IP="192.168.1.2"
ROUTER_PORT=22
USERNAME="root"
PASSWORD="root"
HOSTNAME="Router"

# Global state
MODE="USER" # USER, PRIVILEGED, CONFIG, INTERFACE
CURRENT_INTERFACE=""
PENDING_COMMANDS=()
PENDING_PASSWORD_CHANGE=""
MockMode=false

# Helper Functions
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
    fi

    echo -n "$HOSTNAME$mode_str$prompt_char "
}

# Mode Handlers
handle_user_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "enable")
            MODE="PRIVILEGED"
            echo "% Entered privileged mode"
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

handle_config_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "hostname")
            if [ -n "${cmd[1]}" ]; then
                HOSTNAME="${cmd[1]}"
                PENDING_COMMANDS+=("uci set system.@system[0].hostname='$HOSTNAME'")
                PENDING_COMMANDS+=("uci commit system")
                PENDING_COMMANDS+=("/etc/init.d/system reload")
            else
                 echo "% Invalid command"
            fi
            ;;
        "enable")
            if [ "${cmd[1]}" == "secret" ]; then
                if [ -z "${cmd[2]}" ]; then
                    echo "% Secret required"
                else
                    PENDING_PASSWORD_CHANGE="${cmd[2]}"
                    echo "Enable secret (router password) change pending"
                fi
            elif [ "${cmd[1]}" == "password" ]; then
                 echo "% Use 'enable secret' to change router password"
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
        "exit")
            MODE="PRIVILEGED"
            ;;
        *)
             echo "% Unknown command"
            ;;
    esac
}

handle_interface_mode() {
    local cmd=($1)
    case "${cmd[0]}" in
        "ip")
             # ip address <ip> <mask> -> ifconfig <iface> <ip> netmask <mask> up
             if [ "${cmd[1]}" == "address" ] && [ -n "${cmd[2]}" ] && [ -n "${cmd[3]}" ]; then
                  local if_cmd="ifconfig $CURRENT_INTERFACE ${cmd[2]} netmask ${cmd[3]} up"
                  PENDING_COMMANDS+=("$if_cmd")
             else
                  echo "% Invalid command"
             fi
             ;;
        "shutdown")
             PENDING_COMMANDS+=("ifconfig $CURRENT_INTERFACE down")
             ;;
        "no")
             if [ "${cmd[1]}" == "shutdown" ]; then
                 PENDING_COMMANDS+=("ifconfig $CURRENT_INTERFACE up")
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

# Main

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
    esac
done
