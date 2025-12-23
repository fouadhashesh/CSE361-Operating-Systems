#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define SIGNAL_FILE "state/signal.flag"
#define TIMEOUT 180

void write_flag(const char *msg) {
    FILE *f = fopen(SIGNAL_FILE, "w");
    if (f) {
        fprintf(f, "%s\n", msg);
        fclose(f);
    }
}

void on_sigint(int sig)  { write_flag("SIGINT"); }
void on_sigterm(int sig) { write_flag("SIGTERM"); exit(0); }
void on_alarm(int sig)   { write_flag("TIMEOUT"); }

int main() {
    signal(SIGINT, on_sigint);
    signal(SIGTERM, on_sigterm);
    signal(SIGALRM, on_alarm);

    alarm(TIMEOUT);

    while (1) pause();
}
