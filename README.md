# Router CLI Documentation

## 1. Overview
**Router CLI** is a unified C++ application designed to control a remote OpenWrt router using a Cisco-like Command Line Interface (CLI). It bridges the gap between familiar network administration commands (e.g., `interface`, `ip address`) and the underlying Linux/OpenWrt commands (e.g., `ifconfig`, `uci`) executed via SSH.

## 2. Architecture

The tool is built as a single binary using `libssh2` for secure communication. It operates on a **Local-Remote Hybrid Model**:

*   **Local Logic**: The command parser, state machine, and configuration queuing happen locally on your machine.
*   **Remote Execution**: When you commit changes (using `apply`), translated commands are sent to the router via SSH.

### State Machine
The CLI implements a hierarchical state machine with the following modes:

1.  **User Mode** (`>`)
    *   Initial mode. Limited verification commands.
2.  **Privileged Mode** (`#`)
    *   Entered via `enable`. Allows viewing configuration and entering config mode.
3.  **Global Configuration Mode** (`(config)#`)
    *   Entered via `configure terminal`. Allows global changes (hostname, routing).
4.  **Interface Configuration Mode** (`(config-if)#`)
    *   Entered via `interface <name>`. Allows specific interface settings (IP, shutdown).

### Command Queuing Strategy
To prevent network interruptions (e.g., changing the IP address you are connected to), connectivity commands are **not executed immediately**.
*   **Queuing**: Commands like `ip address` and `hostname` are stored in a pending list.
*   **Execution**: The `apply` command in Privileged Mode flushes the queue, sending all commands sequentially over the SSH channel.

## 3. Installation & Compilation

### Dependencies
*   **C++ Compiler** (g++ with C++11 support)
*   **libssh2** (Development headers and library)

### Compilation
Run the following command in the project directory:

```bash
g++ router_cli.cpp -lssh2 -o router_cli
```

## 4. Usage Guide

### Standard Mode
Attempts to connect to the router at `192.168.1.2` with user `root` and password `root`.

```bash
./router_cli
```

*Note: You can modify the `ROUTER_IP`, `USERNAME`, and `PASSWORD` macros in `router_cli.cpp` to match your environment.*

### Mock Mode (Testing)
Use this mode to test the CLI logic without a physical router. It simulates SSH success and prints the translated commands to the terminal.

```bash
./router_cli --mock
```

## 5. Command Reference

### User Mode (`>`)
| Command | Description |
| :--- | :--- |
| `enable` | Enter Privileged Mode. |
| `exit` | Exit the application. |

### Privileged Mode (`#`)
| Command | Description |
| :--- | :--- |
| `configure terminal` / `conf t` | Enter Global Configuration Mode. |
| `disable` | Return to User Mode. |
| `show running-config` | Show the list of pending commands waiting to be applied. |
| `show ip route` | Fetch and display the routing table from the remote router (`ip route show`). |
| `apply` | **Execute all pending commands** on the remote router. |
| `exit` | Return to User Mode. |

### Global Configuration Mode (`(config)#`)
| Command | Description | Translation (Linux/OpenWrt) |
| :--- | :--- | :--- |
| `hostname <name>` | Set router hostname. | `uci set system.@system[0].hostname='...'` |
| `interface <name>` | Enter Interface Configuration Mode. | N/A (Internal State Change) |
| `ip route <net> <mask> <gw>` | Add a static route. | `ip route add <net> via <gw>` |
| `exit` | Return to Privileged Mode. | N/A |

### Interface Configuration Mode (`(config-if)#`)
| Command | Description | Translation (Linux/OpenWrt) |
| :--- | :--- | :--- |
| `ip address <ip> <mask>` | Set interface IP. | `ifconfig <iface> <ip> netmask <mask> up` |
| `shutdown` | Disable the interface. | `ifconfig <iface> down` |
| `no shutdown` | Enable the interface. | `ifconfig <iface> up` |
| `exit` | Return to Global Config Mode. | N/A |

## Example Workflow

```bash
enable
configure terminal
interface eth0
ip address 192.168.10.1 255.255.255.0
no shutdown
exit
ip route 10.0.0.0 255.0.0.0 192.168.10.254
exit
apply
```
