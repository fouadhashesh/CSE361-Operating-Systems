#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <time.h>

volatile sig_atomic_t update_request = 0;
volatile sig_atomic_t stop_request = 0;

void handle_sigusr1(int sig) {
    update_request = 1;
}

void handle_sigterm(int sig) {
    stop_request = 1;
}

void log_with_timestamp(const char* msg) {
    time_t now;
    time(&now);
    char buf[20];
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", localtime(&now));
    printf("[%s] [MONITOR] %s\n", buf, msg);
}

void log_file_content(const char* filepath, const char* label) {
    FILE* fp = fopen(filepath, "r");
    if (!fp) return;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        // Remove trailing newline
        line[strcspn(line, "\n")] = 0;
        time_t now;
        time(&now);
        char buf[20];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", localtime(&now));
        printf("[%s] [MONITOR] %s: %s\n", buf, label, line);
    }
    fclose(fp);
}

// Helper to read a value from config file
// Returns 1 if found, 0 if not. Value is copied to dest.
int read_config_value(const char* filepath, const char* key, char* dest, size_t dest_size) {
    FILE* fp = fopen(filepath, "r");
    if (!fp) return 0;

    char line[256];
    int found = 0;
    size_t key_len = strlen(key);
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, key, key_len) == 0 && line[key_len] == '=') {
            // Found key="val\n"
            char* val = line + key_len + 1;
            val[strcspn(val, "\n")] = 0; // trim newline
            strncpy(dest, val, dest_size - 1);
            dest[dest_size - 1] = '\0';
            found = 1;
            break;
        }
    }
    fclose(fp);
    return found;
}

void fetch_remote_config() {
    char ip[64] = "192.168.1.2"; // Defaults
    char port[16] = "22";
    char user[64] = "root";
    char pass[64] = "root";
    
    // Read from config if available
    read_config_value("state/router_cli.conf", "router_ip", ip, sizeof(ip));
    read_config_value("state/router_cli.conf", "router_port", port, sizeof(port));
    read_config_value("state/router_cli.conf", "username", user, sizeof(user));
    read_config_value("state/router_cli.conf", "password", pass, sizeof(pass));

    // Construct the command dynamically
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), 
             "sshpass -p '%s' ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -p %s %s@%s \"echo '--- Remote Hostname ---'; uci show system.@system[0].hostname; echo '--- Remote Interfaces ---'; ip address show\" 2>&1",
             pass, port, user, ip);

    FILE* fp = popen(cmd, "r");
    if (!fp) {
        log_with_timestamp("Error: Failed to execute remote fetch command.");
        return;
    }

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        // Remove trailing newline for cleaner log
        line[strcspn(line, "\n")] = 0;
        time_t now;
        time(&now);
        char buf[20];
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", localtime(&now));
        
        printf("[%s] [MONITOR] REMOTE: %s\n", buf, line);
    }
    
    int status = pclose(fp);
    if (status != 0) {
        log_with_timestamp("Warning: Remote fetch command finished with errors (or mock mode/network issue).");
    }
}

void fetch_router_updates() {
    log_with_timestamp("Received signal. Fetching REAL updates from router...");
    
    // Fetch from remote
    fetch_remote_config();
    
    // Also log local state for comparison
    log_with_timestamp("Local State (for comparison):");
    log_file_content("state/router_cli.conf", "Config");
    
    printf("\n"); // Separator
}

int main() {
    printf("[MONITOR] Starting router monitor (PID: %d)...\n", getpid());

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_sigusr1;
    sigaction(SIGUSR1, &sa, NULL);

    struct sigaction sa_term;
    memset(&sa_term, 0, sizeof(sa_term));
    sa_term.sa_handler = handle_sigterm;
    sigaction(SIGTERM, &sa_term, NULL);
    sigaction(SIGINT, &sa_term, NULL);

    while (!stop_request) {
        if (update_request) {
            update_request = 0;
            fetch_router_updates();
        }
        // Sleep to save CPU, wake up on signal
        sleep(10);
    }

    printf("[MONITOR] Shutting down...\n");
    return 0;
}
