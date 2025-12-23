#include <libssh2.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cstring>
#include <iostream>

#define ROUTER_IP "192.168.1.2"
#define ROUTER_PORT 22
#define USERNAME "root"
#define PASSWORD "root"

void run_command(LIBSSH2_SESSION* session, const char* command)
{
    LIBSSH2_CHANNEL* channel = libssh2_channel_open_session(session);
    if (!channel) {
        std::cerr << "Unable to open channel\n";
        return;
    }

    libssh2_channel_exec(channel, command);

    char buffer[4096];
    ssize_t n;

    while ((n = libssh2_channel_read(channel, buffer, sizeof(buffer))) > 0) {
        std::cout.write(buffer, n);
    }

    libssh2_channel_close(channel);
    libssh2_channel_free(channel);
}





int main()
{
    libssh2_init(0);

    int sock = socket(AF_INET, SOCK_STREAM, 0);

    sockaddr_in sin{};
    sin.sin_family = AF_INET;
    sin.sin_port = htons(ROUTER_PORT);
    inet_pton(AF_INET, ROUTER_IP, &sin.sin_addr);

    if (connect(sock, (sockaddr*)(&sin), sizeof(sin)) != 0) {
        std::cerr << "Failed to connect\n";
        return 1;
    }

    LIBSSH2_SESSION* session = libssh2_session_init();
    libssh2_session_handshake(session, sock);

    if (libssh2_userauth_password(session, USERNAME, PASSWORD)) {
        std::cerr << "Authentication failed\n";
        return 1;
    }

    // === PoC commands ===
    run_command(session, "netstat");

    libssh2_session_disconnect(session, "Done");
    libssh2_session_free(session);
    close(sock);
    libssh2_exit();

    return 0;
}

