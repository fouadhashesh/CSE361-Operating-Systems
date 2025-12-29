#include <libssh2.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

// Configuration
#define ROUTER_IP "192.168.1.2"
#define ROUTER_PORT 22
#define USERNAME "root"
#define PASSWORD "root"
#define MAX_COMMANDS 1000
#define MAX_COMMAND_LEN 512
#define MAX_TOKENS 50
#define MAX_TOKEN_LEN 256
#define MAX_HOSTNAME_LEN 256
#define MAX_INTERFACE_LEN 64

// Global SSH state
int sock = -1;
LIBSSH2_SESSION* session = NULL;
bool mock_mode = false;

// Command buffer for "apply"
char pending_commands[MAX_COMMANDS][MAX_COMMAND_LEN];
int pending_count = 0;

typedef enum {
    MODE_USER,
    MODE_PRIVILEGED,
    MODE_CONFIG,
    MODE_INTERFACE
} Mode;

Mode current_mode = MODE_USER;
char current_interface[MAX_INTERFACE_LEN] = "";
char hostname[MAX_HOSTNAME_LEN] = "Router";

// --- SSH Helper Functions ---

void execute_remote_command(const char* command) {
    if (mock_mode) {
        printf("[SSH MOCK] Executing: %s\n", command);
        return;
    }

    if (!session) {
        fprintf(stderr, "%% Not connected to router (SSH session null)\n");
        return;
    }

    LIBSSH2_CHANNEL* channel = libssh2_channel_open_session(session);
    if (!channel) {
        fprintf(stderr, "%% Unable to open channel\n");
        return;
    }

    int rc = libssh2_channel_exec(channel, command);
    if (rc != 0) {
         fprintf(stderr, "%% Execution failed: %d\n", rc);
         libssh2_channel_free(channel);
         return;
    }

    char buffer[4096];
    ssize_t n;
    while ((n = libssh2_channel_read(channel, buffer, sizeof(buffer))) > 0) {
        fwrite(buffer, 1, n, stdout);
    }
    
    // Check for errors (libssh2 returns negative on error)
    if (n < 0) {
         fprintf(stderr, "%% Error reading from channel\n");
    }

    libssh2_channel_close(channel);
    libssh2_channel_free(channel);
}

bool connect_ssh() {
    if (mock_mode) return true;

    libssh2_init(0);
    sock = socket(AF_INET, SOCK_STREAM, 0);

    struct sockaddr_in sin;
    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons(ROUTER_PORT);
    inet_pton(AF_INET, ROUTER_IP, &sin.sin_addr);

    if (connect(sock, (struct sockaddr*)(&sin), sizeof(sin)) != 0) {
        fprintf(stderr, "%% Failed to connect to %s\n", ROUTER_IP);
        return false;
    }

    session = libssh2_session_init();
    if (libssh2_session_handshake(session, sock)) {
        fprintf(stderr, "%% SSH Handshake failed\n");
        return false;
    }

    if (libssh2_userauth_password(session, USERNAME, PASSWORD)) {
        fprintf(stderr, "%% Authentication failed\n");
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
    const char* prompt_char = (current_mode == MODE_USER) ? ">" : "#";
    char mode_str[32] = "";
    
    if (current_mode == MODE_CONFIG) strcpy(mode_str, "(config)");
    else if (current_mode == MODE_INTERFACE) strcpy(mode_str, "(config-if)");

    printf("%s%s%s ", hostname, mode_str, prompt_char);
    fflush(stdout);
}

int split_command(const char* line, char tokens[][MAX_TOKEN_LEN]) {
    int count = 0;
    char* line_copy = strdup(line);
    char* token = strtok(line_copy, " \t\n");
    
    while (token && count < MAX_TOKENS) {
        strncpy(tokens[count], token, MAX_TOKEN_LEN - 1);
        tokens[count][MAX_TOKEN_LEN - 1] = '\0';
        count++;
        token = strtok(NULL, " \t\n");
    }
    
    free(line_copy);
    return count;
}

void add_pending_command(const char* command) {
    if (pending_count < MAX_COMMANDS) {
        strncpy(pending_commands[pending_count], command, MAX_COMMAND_LEN - 1);
        pending_commands[pending_count][MAX_COMMAND_LEN - 1] = '\0';
        pending_count++;
    }
}

// --- Mode Handlers ---

void handle_user_mode(char tokens[][MAX_TOKEN_LEN], int token_count) {
    if (strcmp(tokens[0], "enable") == 0) {
        // Simulating simple auth or no auth for now as per shell scripts
        current_mode = MODE_PRIVILEGED;
        printf("%% Entered privileged mode\n");
    } else if (strcmp(tokens[0], "exit") == 0) {
        printf("Bye!\n");
        cleanup_ssh();
        exit(0);
    } else {
        printf("%% Unknown command\n");
    }
}

void handle_privileged_mode(char tokens[][MAX_TOKEN_LEN], int token_count) {
    if (strcmp(tokens[0], "disable") == 0) {
        current_mode = MODE_USER;
        printf("%% Returned to user mode\n");
    } else if (strcmp(tokens[0], "configure") == 0 || strcmp(tokens[0], "conf") == 0) {
        if (token_count > 1 && (strcmp(tokens[1], "terminal") == 0 || strcmp(tokens[1], "t") == 0)) {
            current_mode = MODE_CONFIG;
            printf("%% Entered config mode\n");
        } else {
            printf("%% Invalid command\n");
        }
    } else if (strcmp(tokens[0], "show") == 0) {
        if (token_count > 1 && strcmp(tokens[1], "running-config") == 0) {
            // In a real scenario, we might dump local state or fetch from router
            printf("! Pending commands:\n");
            for (int i = 0; i < pending_count; i++) {
                printf("%s\n", pending_commands[i]);
            }
        } else if (token_count >= 3 && strcmp(tokens[1], "ip") == 0 && strcmp(tokens[2], "route") == 0) {
             execute_remote_command("ip route show");
        } else {
            printf("%% Invalid command\n");
        }
    } else if (strcmp(tokens[0], "apply") == 0) {
        if (pending_count == 0) {
            printf("%% No changes to apply\n");
        } else {
            printf("Applying %d commands...\n", pending_count);
            for (int i = 0; i < pending_count; i++) {
                execute_remote_command(pending_commands[i]);
            }
            pending_count = 0;
        }
    } else if (strcmp(tokens[0], "exit") == 0) {
        current_mode = MODE_USER;
    } else {
        printf("%% Unknown command\n");
    }
}

void handle_config_mode(char tokens[][MAX_TOKEN_LEN], int token_count) {
    if (strcmp(tokens[0], "hostname") == 0 && token_count > 1) {
        strncpy(hostname, tokens[1], MAX_HOSTNAME_LEN - 1);
        hostname[MAX_HOSTNAME_LEN - 1] = '\0';
        // OpenWrt: uci set system.@system[0].hostname='hostname'; uci commit
        char cmd[MAX_COMMAND_LEN];
        snprintf(cmd, sizeof(cmd), "uci set system.@system[0].hostname='%s'", hostname);
        add_pending_command(cmd);
        add_pending_command("uci commit system");
        add_pending_command("/etc/init.d/system reload"); // Apply hostname
    } else if (strcmp(tokens[0], "interface") == 0 && token_count > 1) {
        strncpy(current_interface, tokens[1], MAX_INTERFACE_LEN - 1);
        current_interface[MAX_INTERFACE_LEN - 1] = '\0';
        current_mode = MODE_INTERFACE;
    } else if (strcmp(tokens[0], "ip") == 0 && token_count >= 5 && strcmp(tokens[1], "route") == 0) {
        // ip route <net> <mask?> <gateway> -- simplifying to: ip route add <net> via <gateway>
        // Simple mapping: keys off tokens. 
        // Example: ip route 192.168.2.0 255.255.255.0 192.168.1.1
        // Linux: ip route add 192.168.2.0/24 via 192.168.1.1
        // For simplicity, passing raw tokens or doing basic translation
        char route_cmd[MAX_COMMAND_LEN];
        snprintf(route_cmd, sizeof(route_cmd), "ip route add %s via %s", tokens[2], tokens[4]);
        add_pending_command(route_cmd);
    } else if (strcmp(tokens[0], "exit") == 0) {
        current_mode = MODE_PRIVILEGED;
    } else {
        printf("%% Unknown command\n");
    }
}

void handle_interface_mode(char tokens[][MAX_TOKEN_LEN], int token_count) {
    if (strcmp(tokens[0], "ip") == 0 && token_count >= 4 && strcmp(tokens[1], "address") == 0) {
        // ip address <ip> <mask>
        // Linux: ifconfig <iface> <ip> netmask <mask> up
        char cmd[MAX_COMMAND_LEN];
        snprintf(cmd, sizeof(cmd), "ifconfig %s %s netmask %s up", current_interface, tokens[2], tokens[3]);
        add_pending_command(cmd);
    } else if (strcmp(tokens[0], "shutdown") == 0) {
        char cmd[MAX_COMMAND_LEN];
        snprintf(cmd, sizeof(cmd), "ifconfig %s down", current_interface);
        add_pending_command(cmd);
    } else if (strcmp(tokens[0], "no") == 0 && token_count > 1 && strcmp(tokens[1], "shutdown") == 0) {
        char cmd[MAX_COMMAND_LEN];
        snprintf(cmd, sizeof(cmd), "ifconfig %s up", current_interface);
        add_pending_command(cmd);
    } else if (strcmp(tokens[0], "exit") == 0) {
        current_mode = MODE_CONFIG;
        current_interface[0] = '\0';
    } else {
        printf("%% Unknown command\n");
    }
}

int main(int argc, char** argv) {
    if (argc > 1 && strcmp(argv[1], "--mock") == 0) {
        mock_mode = true;
        printf("[INFO] Running in MOCK mode. No real SSH connection.\n");
    }

    if (!connect_ssh()) {
        if (!mock_mode) {
             fprintf(stderr, "Fatal: Could not connect to router. Use --mock for testing.\n");
             return 1;
        }
    }

    char line[1024];
    char tokens[MAX_TOKENS][MAX_TOKEN_LEN];
    
    while (true) {
        print_prompt();
        if (!fgets(line, sizeof(line), stdin)) break;
        
        // Remove newline if present
        size_t len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
        }
        
        if (strlen(line) == 0) continue;

        int token_count = split_command(line, tokens);
        if (token_count == 0) continue;

        switch (current_mode) {
            case MODE_USER: 
                handle_user_mode(tokens, token_count); 
                break;
            case MODE_PRIVILEGED: 
                handle_privileged_mode(tokens, token_count); 
                break;
            case MODE_CONFIG: 
                handle_config_mode(tokens, token_count); 
                break;
            case MODE_INTERFACE: 
                handle_interface_mode(tokens, token_count); 
                break;
        }
    }

    cleanup_ssh();
    return 0;
}