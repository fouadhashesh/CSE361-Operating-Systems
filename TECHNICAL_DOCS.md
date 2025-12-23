# router_cli - Technical Explanation

This document provides a comprehensive breakdown of the `router_cli` program, explaining its variable state, function logic, and execution flow.

## 1. Global State & Configuration
The program maintains the state of the router connection and the user's current context (mode) using global variables. This simplifies the logic by avoiding passing state objects to every function.

### Constants (`#define`)
*   `ROUTER_IP`: The target IP address of the router (default: `192.168.1.2`).
*   `ROUTER_PORT`: SSH port (default: `22`).
*   `USERNAME` / `PASSWORD`: Credentials used for the SSH connection.

### Global Variables
*   `sock`: The raw socket file descriptor for the TCP connection.
*   `session`: Pointer to the `LIBSSH2_SESSION` struct, managing the encrypted SSH session.
*   `mock_mode`: Boolean flag. If `true`, the program skips actual network calls and prints commands to stdout instead.
*   `pending_commands`: A `std::vector<std::string>` that acts as a buffer. Configuration commands are stored here and only executed when the user types `apply`.
*   `current_mode`: An enum tracking the user's CLI location (`USER`, `PRIVILEGED`, `CONFIG`, `INTERFACE`).
*   `current_interface`: Stores the name of the interface currently being edited (e.g., `eth0`), used only when in `MODE_INTERFACE`.

---

## 2. SSH Communication Layer
These functions handle the low-level networking and direct interaction with the `libssh2` library.

### `connect_ssh()`
*   **Purpose**: Establishes the connection to the router.
*   **Logic**:
    1.  Checks if `mock_mode` is enabled. If so, returns `true` immediately.
    2.  Initializes `libssh2`.
    3.  Creates a standard TCP socket and connects to `ROUTER_IP`.
    4.  Starts the SSH session handshake explicitly on that socket.
    5.  Authenticates using the defined username and password.
*   **Returns**: `true` on success, `false` on failure.

### `execute_remote_command(const char* command)`
*   **Purpose**: Sends a single shell command to the router for execution.
*   **Logic**:
    1.  If `mock_mode` is on, it simply prints `[SSH MOCK] Executing: ...` to the console.
    2.  Opens a new "Channel" within the existing SSH session. **Note**: SSH executes every command in a new channel (similar to opening a new terminal window for each command).
    3.  Calls `libssh2_channel_exec` to run the command on the remote server.
    4.  Reads the output (stdout) into a 4096-byte buffer loop and prints it to the local console.
    5.  Closes and frees the channel.

### `cleanup_ssh()`
*   **Purpose**: Gracefully shuts down the connection.
*   **Logic**: Disconnects the session, frees the `libssh2` structures, closes the socket, and de-initializes the library.

---

## 3. Command Line Interface (CLI) Logic
These functions mimic the behavior of a Cisco IOS terminal.

### `main()` (Entry Point)
*   **Logic Flow**:
    1.  **Argument Parsing**: Checks for `--mock` to enable testing mode.
    2.  **Connection**: Calls `connect_ssh()`. If it fails (and not in mock mode), the program exits.
    3.  **REPL Loop (Read-Eval-Print Loop)**:
        *   **Print**: Calls `print_prompt()` to show the current context (e.g., `Router(config)#`).
        *   **Read**: Uses `std::getline` to wait for user input.
        *   **Parse**: Calls `split_command` to break the line into tokens.
        *   **Dispatch**: Uses a `switch` statement on `current_mode` to forward the tokens to the specific handler function (`handle_user_mode`, etc.).

### `print_prompt()`
*   **Logic**: Dynamically constructs the prompt string based on `current_mode` and `hostname`.
    *   User Mode: `Router>`
    *   Privileged: `Router#`
    *   Config: `Router(config)#`
    *   Interface: `Router(config-if)#`

### `split_command(string line)`
*   **Logic**: A helper utility that splits a string by spaces into a vector of strings (tokens). This makes parsing commands like `ip address 1.2.3.4` easier.

---

## 4. Mode Handlers (The State Machine)
The core logic is divided into four functions, allowing strict control over which commands are available in which context.

### A. `handle_user_mode` (State: `>`)
*   **Available Commands**:
    *   `enable`: Switches state to `MODE_PRIVILEGED`.
    *   `exit`: Closes the program.

### B. `handle_privileged_mode` (State: `#`)
*   **Available Commands**:
    *   `configure terminal`: Switches state to `MODE_CONFIG`.
    *   `show running-config`: Displays the contents of the `pending_commands` vector (local changes waiting to be sent).
    *   `show ip route`: **Direct Execution**. Calls `execute_remote_command("ip route show")` immediately to fetch data from the router.
    *   `apply`: **Critical Function**. Iterates through `pending_commands`, calls `execute_remote_command` for each one, and then clears the vector. This is the only time configuration changes are actually pushed to the router.

### C. `handle_config_mode` (State: `(config)#`)
*   **Available Commands**:
    *   `hostname <name>`: Queues a pending command to change the hostname (using OpenWrt `uci` commands).
    *   `interface <name>`: Switches state to `MODE_INTERFACE` and sets the global `current_interface` variable.
    *   `ip route ...`: Queues a standard Linux `ip route add ...` command.
    *   `exit`: Returns to `MODE_PRIVILEGED`.

### D. `handle_interface_mode` (State: `(config-if)#`)
*   **Context**: All commands here apply to the interface stored in `current_interface`.
*   **Available Commands**:
    *   `ip address <ip> <mask>`: Queues a Linux `ifconfig` command.
    *   `shutdown`: Queues `ifconfig ... down`.
    *   `no shutdown`: Queues `ifconfig ... up`.
    *   `exit`: Returns to `MODE_CONFIG`.

---

## 5. Summary of Data Flow

1.  User types: `ip address 192.168.1.1 255.255.255.0`
2.  `main` reads string -> `split_command` creates tokens.
3.  `handle_interface_mode` parses tokens.
4.  **Translation**: The C++ code translates this "Cisco-style" command into a Linux command: `"ifconfig eth0 192.168.1.1 netmask 255.255.255.0 up"`.
5.  **Queuing**: This string is pushed to `pending_commands`. Nothing is sent to the router yet.
6.  User types: `exit`, `exit`, `apply`.
7.  `handle_privileged_mode` sees `apply`.
8.  **Execution**: The queue is flushed. `execute_remote_command` sends the stored `ifconfig` string over SSH.
9.  Router executes the command.
