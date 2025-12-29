# Router CLI Tool and Monitor

This project provides a robust, bash-based Command Line Interface (CLI) for managing OpenWrt routers, paired with a C-based background monitor implementation for real-time state tracking.

## 🚀 Key Features

*   **Bash CLI (`router_cli.sh`)**: A full-featured CLI mimicking Cisco IOS behavior (User > Privileged > Config > Interface/Wireless).
*   **Active Monitor (`router_monitor`)**: A background C program that automatically fetches and logs router state (Hostname, IP, Interfaces) whenever changes are applied.
*   **Wireless Configuration**: Dedicated mode for managing WiFi SSID, password, channel, and visibility.
*   **Instant Application**: WiFi changes are committed and reloaded instantly.
*   **Harmonized State**: The CLI and Monitor share configuration (IP, Credentials) dynamically.
*   **Local Persistence**: Saves hostname, interface config, and authentication locally across sessions.
*   **SSH Compatibility**: Built-in support for legacy `ssh-rsa` routers and `sshpass` for password automation.

---

## 📋 Prerequisites

*   `bash` (Main shell)
*   `gcc` (To compile the monitor)
*   `ssh` client
*   `sshpass` (Optional, but recommended for automatic login)
    *   Mac: `brew install sshpass`
    *   Linux: `sudo apt install sshpass`

---

## 🛠 Usage

1.  **Start the CLI**:
    ```bash
    ./router_cli.sh
    ```
    *   *Note*: On first run, it compiles `router_monitor.c` automatically.

2.  **Flags**:
    *   `--mock`: Run in simulation mode (no SSH connection).
    *   `--clean`: Wipe local state (`state/` directory) and start fresh.

---

## 🎮 Command Reference

### 1. User Mode (`>`)
Default entry mode.
*   `enable`: Enter Privileged Mode (Prompts for password if set).
*   `exit`: Close the CLI.

### 2. Privileged Mode (`#`)
high-level viewing and applying.
*   `configure terminal` (or `conf t`): Enter Global Config Mode.
*   `show running-config`: View queued changes.
*   `show ip route`: View remote routing table.
*   `show ip interface`: **[NEW]** View all remote interface IP addresses.
*   `apply`: Execute all queued commands on the router. **Triggers Monitor Update**.
*   `disable`: Return to User Mode.

### 3. Global Configuration (`(config)#`)
*   `hostname <name>`: Set system hostname.
*   `enable secret <pass>`: Set privileged password (updates local & remote).
*   `interface <name>`: Enter Interface Config Mode.
*   `wireless`: **[NEW]** Enter Wireless Config Mode.
*   `ip route <net> <mask> <gw>`: Add static route.
*   `exit`: Return to Privileged Mode.

### 4. Interface Configuration (`(config-if)#`)
*   `ip address <ip> <mask>`: Set IP.
*   `shutdown` / `no shutdown`: Disable/Enable interface.
*   `exit`: Back to Config Mode.

### 5. Wireless Configuration (`(config-wifi)#`)
**[NEW]** Manage WiFi settings. Changes perform `uci commit` and `wifi reload` instantly on `apply`.
*   `ssid <name>`: Set WiFi SSID.
*   `password <key>`: Set WPA2 password.
*   `hidden <yes/no>`: Hide network SSID.
*   `channel <num>`: Set radio channel.
*   `exit`: Back to Config Mode.

---

## 📡 Router Monitor

The system automatically launches a companion C program, `router_monitor`, in the background.

*   **Lifecycle**: Auto-started by `router_cli.sh`, killed on exit.
*   **Logging**: Writes to `router_monitor.log`.
*   **Function**:
    *   Listens for `SIGUSR1` signals (sent by CLI `apply` command).
    *   **Actively Fetches**: Connects to the router via SSH to pull `uci show system` and `ip address show`.
    *   **Logs**: Timestamps and records the fetched state to the log file.
    *   **Shared Config**: Reads IP/User/Pass from `state/router_cli.conf` to match the CLI's connection settings.

---

## 📂 Internal State

State is stored in `state/`:
*   `router_cli.conf`: Persists Hostname, Auth, and **Connection Details** (IP, User, Port).
*   `interfaces.conf`: Persists Interface settings.

---

## ⚠️ SSH Compatibility
The script uses `-o HostKeyAlgorithms=+ssh-rsa` to support older OpenWrt devices.
