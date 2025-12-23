#include <libssh2.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <map>

// Configuration
#define ROUTER_IP "192.168.1.2"
#define ROUTER_PORT 22
#define USERNAME "root"
#define PASSWORD "root"

// Global SSH state
int sock = -1;
LIBSSH2_SESSION* session = nullptr;
bool mock_mode = false;

// Command buffer for "apply"
std::vector<std::string> pending_commands;

enum Mode {
    MODE_USER,
    MODE_PRIVILEGED,
    MODE_CONFIG,
    MODE_INTERFACE
};

Mode current_mode = MODE_USER;
std::string current_interface = "";
std::string hostname = "Router";

// --- SSH Helper Functions ---

void execute_remote_command(const char* command) {
    if (mock_mode) {
        std::cout << "[SSH MOCK] Executing: " << command << std::endl;
        return;
    }

    if (!session) {
        std::cerr << "% Not connected to router (SSH session null)\n";
        return;
    }

    LIBSSH2_CHANNEL* channel = libssh2_channel_open_session(session);
    if (!channel) {
        std::cerr << "% Unable to open channel\n";
        return;
    }

    int rc = libssh2_channel_exec(channel, command);
    if (rc != 0) {
         std::cerr << "% Execution failed: " << rc << "\n";
         libssh2_channel_free(channel);
         return;
    }

    char buffer[4096];
    ssize_t n;
    while ((n = libssh2_channel_read(channel, buffer, sizeof(buffer))) > 0) {
        std::cout.write(buffer, n);
    }
    
    // Check for errors (libssh2 returns negative on error)
    if (n < 0) {
         std::cerr << "% Error reading from channel\n";
    }

    libssh2_channel_close(channel);
    libssh2_channel_free(channel);
}

bool connect_ssh() {
    if (mock_mode) return true;

    libssh2_init(0);
    sock = socket(AF_INET, SOCK_STREAM, 0);

    sockaddr_in sin{};
    sin.sin_family = AF_INET;
    sin.sin_port = htons(ROUTER_PORT);
    inet_pton(AF_INET, ROUTER_IP, &sin.sin_addr);

    if (connect(sock, (sockaddr*)(&sin), sizeof(sin)) != 0) {
        std::cerr << "% Failed to connect to " << ROUTER_IP << "\n";
        return false;
    }

    session = libssh2_session_init();
    if (libssh2_session_handshake(session, sock)) {
        std::cerr << "% SSH Handshake failed\n";
        return false;
    }

    if (libssh2_userauth_password(session, USERNAME, PASSWORD)) {
        std::cerr << "% Authentication failed\n";
        return false;
    }

    return true;
}

void cleanup_ssh() {
    if (mock_mode) return;
    if (session) {
        libssh2_session_disconnect(session, "Client disconnecting");
        libssh2_session_free(session);
    }
    if (sock != -1) {
        close(sock);
    }
    libssh2_exit();
}

// --- CLI Helper Functions ---

void print_prompt() {
    std::string prompt_char = (current_mode == MODE_USER) ? ">" : "#";
    std::string mode_str = "";
    
    if (current_mode == MODE_CONFIG) mode_str = "(config)";
    else if (current_mode == MODE_INTERFACE) mode_str = "(config-if)";

    std::cout << hostname << mode_str << prompt_char << " ";
}

std::vector<std::string> split_command(const std::string& line) {
    std::vector<std::string> tokens;
    std::stringstream ss(line);
    std::string token;
    while (ss >> token) {
        tokens.push_back(token);
    }
    return tokens;
}

// --- Mode Handlers ---

void handle_user_mode(const std::vector<std::string>& tokens) {
    if (tokens[0] == "enable") {
        // Simulating simple auth or no auth for now as per shell scripts
        current_mode = MODE_PRIVILEGED;
        std::cout << "% Entered privileged mode\n";
    } else if (tokens[0] == "exit") {
        std::cout << "Bye!\n";
        cleanup_ssh();
        exit(0);
    } else {
        std::cout << "% Unknown command\n";
    }
}

void handle_privileged_mode(const std::vector<std::string>& tokens) {
    if (tokens[0] == "disable") {
        current_mode = MODE_USER;
        std::cout << "% Returned to user mode\n";
    } else if (tokens[0] == "configure" || tokens[0] == "conf") {
        if (tokens.size() > 1 && (tokens[1] == "terminal" || tokens[1] == "t")) {
            current_mode = MODE_CONFIG;
            std::cout << "% Entered config mode\n";
        } else {
            std::cout << "% Invalid command\n";
        }
    } else if (tokens[0] == "show") {
        if (tokens.size() > 1 && tokens[1] == "running-config") {
            // In a real scenario, we might dump local state or fetch from router
            std::cout << "! Pending commands:\n";
            for (const auto& cmd : pending_commands) {
                std::cout << cmd << "\n";
            }
        } else if (tokens.size() >= 3 && tokens[1] == "ip" && tokens[2] == "route") {
             execute_remote_command("ip route show");
        } else {
            std::cout << "% Invalid command\n";
        }
    } else if (tokens[0] == "apply") {
        if (pending_commands.empty()) {
            std::cout << "% No changes to apply\n";
        } else {
            std::cout << "Applying " << pending_commands.size() << " commands...\n";
            for (const auto& cmd : pending_commands) {
                execute_remote_command(cmd.c_str());
            }
            pending_commands.clear();
        }
    } else if (tokens[0] == "exit") {
        current_mode = MODE_USER;
    } else {
        std::cout << "% Unknown command\n";
    }
}

void handle_config_mode(const std::vector<std::string>& tokens) {
    if (tokens[0] == "hostname" && tokens.size() > 1) {
        hostname = tokens[1];
        // OpenWrt: uci set system.@system[0].hostname='hostname'; uci commit
        pending_commands.push_back("uci set system.@system[0].hostname='" + hostname + "'");
        pending_commands.push_back("uci commit system");
        pending_commands.push_back("/etc/init.d/system reload"); // Apply hostname
    } else if (tokens[0] == "interface" && tokens.size() > 1) {
        current_interface = tokens[1];
        current_mode = MODE_INTERFACE;
    } else if (tokens[0] == "ip" && tokens.size() >= 4 && tokens[1] == "route") {
        // ip route <net> <mask?> <gateway> -- simplifying to: ip route add <net> via <gateway>
        // Simple mapping: keys off tokens. 
        // Example: ip route 192.168.2.0 255.255.255.0 192.168.1.1
        // Linux: ip route add 192.168.2.0/24 via 192.168.1.1
        // For simplicity, passing raw tokens or doing basic translation
        std::string route_cmd = "ip route add " + tokens[2] + " via " + tokens[4]; 
        pending_commands.push_back(route_cmd);
    } else if (tokens[0] == "exit") {
        current_mode = MODE_PRIVILEGED;
    } else {
        std::cout << "% Unknown command\n";
    }
}

void handle_interface_mode(const std::vector<std::string>& tokens) {
    if (tokens[0] == "ip" && tokens.size() >= 4 && tokens[1] == "address") {
        // ip address <ip> <mask>
        // Linux: ifconfig <iface> <ip> netmask <mask> up
        std::string cmd = "ifconfig " + current_interface + " " + tokens[2] + " netmask " + tokens[3] + " up";
        pending_commands.push_back(cmd);
    } else if (tokens[0] == "shutdown") {
        pending_commands.push_back("ifconfig " + current_interface + " down");
    } else if (tokens[0] == "no" && tokens.size() > 1 && tokens[1] == "shutdown") {
        pending_commands.push_back("ifconfig " + current_interface + " up");
    } else if (tokens[0] == "exit") {
        current_mode = MODE_CONFIG;
        current_interface = "";
    } else {
        std::cout << "% Unknown command\n";
    }
}

int main(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "--mock") {
        mock_mode = true;
        std::cout << "[INFO] Running in MOCK mode. No real SSH connection.\n";
    }

    if (!connect_ssh()) {
        if (!mock_mode) {
             std::cerr << "Fatal: Could not connect to router. Use --mock for testing.\n";
             return 1;
        }
    }

    std::string line;
    while (true) {
        print_prompt();
        if (!std::getline(std::cin, line)) break;
        if (line.empty()) continue;

        auto tokens = split_command(line);
        if (tokens.empty()) continue;

        switch (current_mode) {
            case MODE_USER: handle_user_mode(tokens); break;
            case MODE_PRIVILEGED: handle_privileged_mode(tokens); break;
            case MODE_CONFIG: handle_config_mode(tokens); break;
            case MODE_INTERFACE: handle_interface_mode(tokens); break;
        }
    }

    cleanup_ssh();
    return 0;
}
