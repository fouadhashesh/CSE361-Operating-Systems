# Bash-Based Router CLI Simulation

This project contains a pure Shell script implementation of a simulated router command-line interface (CLI). It mimics the behavior of industry-standard network equipment (like Cisco IOS) using standard Bash scripts.

## 1. Overview
The system is built around a main loop that dynamically sources different "mode" scripts based on the user's current context. Use this to simulate network configuration and navigation.

## 2. Directory Structure
*   `main.sh`: The entry point. Handles the main loop, traps signals, and manages the global `MODE` state.
*   `modes/`: Contains the logic for each specific CLI mode.
    *   `user.sh`: Standard user mode.
    *   `privileged.sh`: Privileged "enable" mode.
    *   `config.sh`: Global configuration mode.
    *   `interface.sh`: Specific interface configuration.
*   `utils/`: Helper scripts for authenticating, logging, and persisting state.
*   `state/`: A directory where the simulated router state (hostname, interface config) is stored in flat files.

## 3. How to Run
Ensure the scripts are executable and run `main.sh`:

```bash
chmod +x main.sh
./main.sh
```

## 4. Modes and Navigation

### User Mode (`>`)
The default starting mode.
*   **Prompt**: `Router>`
*   **Commands**:
    *   `enable`: Switch to Privileged mode (Simulates authentication).
    *   `exit`: Terminate the simulator.

### Privileged Mode (`#`)
*   **Prompt**: `Router#`
*   **Commands**:
    *   `configure terminal` (or `conf t`): Enter Global Configuration mode.
    *   `show running-config`: Display current configuration state.
    *   `show ip route`: Display routing table (from `state/routes.conf`).
    *   `disable`: Return to User mode.
    *   `apply`: Trigger the configuration application script.

### Global Configuration Mode (`(config)#`)
*   **Prompt**: `Router(config)#`
*   **Navigation**: Entered from Privileged mode.
*   **Commands**:
    *   `hostname <name>`: Change the router's hostname.
    *   `interface <name>`: Enter Interface Configuration mode.
    *   `ip route <net> <netmask> <gateway>`: Add a static route.
    *   `enable password <pass>`: Set access passwords.
    *   `exit`: Return to Privileged mode.

### Interface Configuration Mode (`(config-if)#`)
*   **Prompt**: `Router(config-if)#`
*   **Navigation**: Entered from Config mode by specifying an interface (e.g., `interface eth0`).
*   **Commands**:
    *   `ip address <ip> <mask>`: Assign an IP address to the interface.
    *   `shutdown`: Disable the interface.
    *   `no shutdown`: Enable the interface.
    *   `exit`: Return to Global Configuration mode.

## 5. Signal Handling
The system handles standard Unix signals to mimic hardware behavior:
*   **Ctrl+C**: Gracefully exits the simulator.
*   **Ctrl+Z** (SIGTSTP): Returns the user immediately to **Privileged Mode**, similar to using a break sequence on real hardware.

## 6. Persistence
All configurations are saved to files in the `state/` directory (e.g., `router.conf`, `interfaces.conf`). This allows the state to persist across sessions if the `state/` folder is not cleared.
