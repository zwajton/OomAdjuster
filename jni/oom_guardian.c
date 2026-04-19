#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/resource.h>
#include <errno.h>

#define CONFIG_PATH "/data/adb/modules/oom_adjuster/config.conf"
#define LOG_PATH    "/data/adb/modules/oom_adjuster/oom_adjuster.log"
#define MAX_APPS    32
#define APP_LEN     256
#define POLL_NS     100000000L  /* 100 ms */

static char apps[MAX_APPS][APP_LEN];
static int  napp = 0;

static void log_msg(const char *msg) {
    FILE *f = fopen(LOG_PATH, "a");
    if (!f) return;
    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", tm);
    fprintf(f, "%s [oom_guardian] %s\n", ts, msg);
    fclose(f);
}

static void parse_config(void) {
    napp = 0;
    FILE *f = fopen(CONFIG_PATH, "r");
    if (!f) return;

    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "protected_apps=", 15) != 0) continue;
        char *val = line + 15;

        /* strip leading quote */
        if (*val == '"') val++;

        /* strip trailing quote, newline, carriage return */
        char *end = val + strlen(val) - 1;
        while (end >= val && (*end == '"' || *end == '\n' || *end == '\r'))
            *end-- = '\0';

        char *tok = strtok(val, " ");
        while (tok && napp < MAX_APPS) {
            strncpy(apps[napp], tok, APP_LEN - 1);
            apps[napp][APP_LEN - 1] = '\0';
            napp++;
            tok = strtok(NULL, " ");
        }
        break;
    }
    fclose(f);
}

/* Match cmdline against protected list.
   Matches "com.pkg" and "com.pkg:process" sub-processes. */
static int is_protected(const char *cmdline, int len) {
    for (int i = 0; i < napp; i++) {
        int plen = (int)strlen(apps[i]);
        if (len < plen) continue;
        if (strncmp(cmdline, apps[i], plen) != 0) continue;
        if (len == plen || cmdline[plen] == ':' || cmdline[plen] == '\0')
            return 1;
    }
    return 0;
}

static void write_file(const char *path, const char *val) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return;
    write(fd, val, strlen(val));
    close(fd);
}

static void protect_pid(int pid) {
    char path[128];
    char pidbuf[24];
    snprintf(pidbuf, sizeof(pidbuf), "%d", pid);

    snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", pid);
    write_file(path, "-1000");

    /* legacy interface — ignore failures on kernels without it */
    snprintf(path, sizeof(path), "/proc/%d/oom_adj", pid);
    write_file(path, "-17");

    write_file("/dev/cpuset/top-app/tasks", pidbuf);
    write_file("/dev/stune/top-app/tasks", pidbuf);

    setpriority(PRIO_PROCESS, (id_t)pid, -18);
}

static void scan_procs(void) {
    DIR *dp = opendir("/proc");
    if (!dp) return;

    struct dirent *de;
    while ((de = readdir(dp)) != NULL) {
        /* skip non-numeric entries fast */
        const char *p = de->d_name;
        if (*p < '1' || *p > '9') continue;

        int pid = atoi(p);
        if (pid <= 0) continue;

        char cmdpath[64];
        snprintf(cmdpath, sizeof(cmdpath), "/proc/%d/cmdline", pid);
        int fd = open(cmdpath, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;

        char cmdline[APP_LEN];
        int n = (int)read(fd, cmdline, sizeof(cmdline) - 1);
        close(fd);
        if (n <= 0) continue;
        cmdline[n] = '\0';

        if (is_protected(cmdline, n))
            protect_pid(pid);
    }
    closedir(dp);
}

int main(void) {
    parse_config();

    char msg[512];
    int off = snprintf(msg, sizeof(msg), "Started (pid=%d) — protecting:", (int)getpid());
    for (int i = 0; i < napp && off < (int)sizeof(msg) - 2; i++)
        off += snprintf(msg + off, sizeof(msg) - off, " %s", apps[i]);
    log_msg(msg);

    struct timespec ts = { .tv_sec = 0, .tv_nsec = POLL_NS };

    while (1) {
        scan_procs();
        nanosleep(&ts, NULL);
    }
    return 0;
}
