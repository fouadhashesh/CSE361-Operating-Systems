# Router CLI Tool (`router_cli.sh`)

**router_cli.sh** is a Bash-based Command Line Interface (CLI) tool designed to manage and configure OpenWrt routers via SSH. It mimics the behavior of a standard Cisco-like router interface (User Mode, Privileged Mode, Config Mode).

## 🚀 Features

*   **Hierarchical Modes**: Standard navigation `User` > `Privileged` > `Config` > `Interface`.
*   **Stateful Configuration**: Queue multiple commands and execute them in batch with `apply`.
*   **Local Persistence**: Saves hostname, authentication credentials, and interface states locally in a `state/` directory across sessions.
*   **Automated SSH**: Uses `sshpass` for password handling and supports legacy `ssh-rsa` key types for older routers.
*   **Mock Mode**: built-in simulation mode for testing without a router.

## 📋 Prerequisites

*   `bash`
*   `ssh`
*   `sshpass` (Optional, for automatic password entry)
    *   *Install on Mac:* `brew install sshpass`
    *   *Install on Linux:* `sudo apt install sshpass`

## 🛠 Usage

```bash
./router_cli.sh [FLAGS]
```

### Flags
*   `--mock`: Run in simulation mode. No SSH connections are attempted; commands are printed to stdout.
*   `--clean`: Clears all local state (`state/` directory) before starting.

## 🎮 Navigation & Commands

### 1. User Mode (`>`)
The default entry mode. Limited functionality.
*   `enable`: Enter Privileged Mode. Prompts for password if one is set.
*   `exit`: Close the CLI.

### 2. Privileged Mode (`#`)
high-level operations and executing changes.
*   `configure terminal` (or `conf t`): Enter Global Config Mode.
*   `show running-config`: Display queued commands and pending changes.
*   `show ip route`: Query the remote router's routing table.
*   `apply`: **Execute** all pending configuration changes on the remote router via SSH.
*   `disable`: Return to User Mode.

### 3. Global Configuration Mode (`(config)#`)
System-wide settings.
*   `hostname <name>`: Set the router's hostname.
    *   *Action*: Updates prompt immediately, persists locally, and queues remote hostname change.
*   `enable secret <password>`: Set privileged access password.
    *   *Action*: Updates local login hash immediately and queues a remote `passwd root` change.
*   `enable password <password>`: Set local privileged access password (plaintext).
    *   *Action*: Updates local login only.
*   `interface <name>`: Enter Interface Config Mode for the specified interface (e.g., `eth0`).
*   `ip route <network> <gateway>`: Add a static route.
    *   *Example*: `ip route 192.168.2.0 255.255.255.0 192.168.1.1`
*   `exit`: Return to Privileged Mode.

### 4. Interface Configuration Mode (`(config-if)#`)
Interface-specific settings.
*   `ip address <ip> <mask>`: Set IP address and netmask.
    *   *Action*: Updates local state file and queues `ifconfig` command.
*   `shutdown`: Disable the interface.
*   `no shutdown`: Enable the interface.
*   `exit`: Return to Global Config Mode.

## 📂 Internal Structure & State

The script maintains its state in the `state/` directory, which is automatically created.

### `state/router_cli.conf`
Stores persistent router configuration:
*   `hostname`: The last set hostname.
*   `enable_password`: Plaintext password for `enable`.
*   `enable_secret_hash`: SHA256 hash for secure `enable` authentication.

### `state/interfaces.conf`
Stores the local view of interface states in CSV format:
`interface,ip_address,netmask,status`

## 🔧 Configuration Variables

You can modify the "Configuration" section at the top of `router_cli.sh` to target your specific device:

```bash
ROUTER_IP="192.168.1.2"    # Target Router IP
ROUTER_PORT=22             # SSH Port
USERNAME="root"            # SSH Username
PASSWORD="root"            # SSH Password (used by sshpass)
```

## ⚠️ SSH Compatibility
The script explicitly adds `-o HostKeyAlgorithms=+ssh-rsa` and `-o PubkeyAcceptedKeyTypes=+ssh-rsa` options to the SSH command. This is necessary for connecting to many older OpenWrt devices or legacy routers that only offer `ssh-rsa`, which modern SSH clients disable by default.
