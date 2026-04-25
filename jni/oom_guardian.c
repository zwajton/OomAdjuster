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
#define MAX_APPS    64
#define APP_LEN     256
#define POLL_NS     100000000L  /* 100 ms */

/* -1000: never killed  |  -999: killable, expected to be restarted by root */
static char critical_apps[MAX_APPS][APP_LEN];
static int  n_critical = 0;
static char restartable_apps[MAX_APPS][APP_LEN];
static int  n_restartable = 0;

/* ── Logging ──────────────────────────────────────────────────────────────── */

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

/* ── Config parsing ───────────────────────────────────────────────────────── */

static void parse_list(char *val, char dest[][APP_LEN], int *count) {
    /* strip leading quote */
    if (*val == '"') val++;
    /* strip trailing quote / newline / carriage return */
    char *end = val + strlen(val) - 1;
    while (end >= val && (*end == '"' || *end == '\n' || *end == '\r'))
        *end-- = '\0';

    char *tok = strtok(val, " ");
    while (tok && *count < MAX_APPS) {
        strncpy(dest[*count], tok, APP_LEN - 1);
        dest[*count][APP_LEN - 1] = '\0';
        (*count)++;
        tok = strtok(NULL, " ");
    }
}

static void parse_config(void) {
    n_critical = 0;
    n_restartable = 0;
    int found_critical = 0;

    FILE *f = fopen(CONFIG_PATH, "r");
    if (!f) return;

    char line[1024];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "protected_apps_critical=", 24) == 0) {
            parse_list(line + 24, critical_apps, &n_critical);
            found_critical = 1;
        } else if (strncmp(line, "protected_apps_restartable=", 27) == 0) {
            parse_list(line + 27, restartable_apps, &n_restartable);
        } else if (!found_critical && strncmp(line, "protected_apps=", 15) == 0) {
            /* backward compat: treat legacy field as critical */
            parse_list(line + 15, critical_apps, &n_critical);
        }
    }
    fclose(f);
}

/* ── Process matching ─────────────────────────────────────────────────────── */

/* Match cmdline against a list.
   Accepts "com.pkg" (main process) and "com.pkg:process" (sub-process). */
static int match_app(const char *cmdline, int len,
                     char apps[][APP_LEN], int count) {
    for (int i = 0; i < count; i++) {
        int plen = (int)strlen(apps[i]);
        if (len < plen) continue;
        if (strncmp(cmdline, apps[i], plen) != 0) continue;
        if (len == plen || cmdline[plen] == ':' || cmdline[plen] == '\0')
            return 1;
    }
    return 0;
}

/* ── Kernel writes ────────────────────────────────────────────────────────── */

static void write_file(const char *path, const char *val) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return;
    write(fd, val, strlen(val));
    close(fd);
}

static void protect_pid(int pid, int score) {
    char path[128];
    char buf[24];

    snprintf(buf, sizeof(buf), "%d", score);
    snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", pid);
    write_file(path, buf);

    /* legacy oom_adj: -17 = fully protected, -16 = one step below */
    snprintf(path, sizeof(path), "/proc/%d/oom_adj", pid);
    write_file(path, score <= -1000 ? "-17" : "-16");

    char pidbuf[24];
    snprintf(pidbuf, sizeof(pidbuf), "%d", pid);
    write_file("/dev/cpuset/top-app/tasks", pidbuf);
    write_file("/dev/stune/top-app/tasks", pidbuf);

    setpriority(PRIO_PROCESS, (id_t)pid, -18);
}

/* ── Main scan loop ───────────────────────────────────────────────────────── */

static void scan_procs(void) {
    DIR *dp = opendir("/proc");
    if (!dp) return;

    struct dirent *de;
    while ((de = readdir(dp)) != NULL) {
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

        if (match_app(cmdline, n, critical_apps, n_critical))
            protect_pid(pid, -1000);
        else if (match_app(cmdline, n, restartable_apps, n_restartable))
            protect_pid(pid, -999);
    }
    closedir(dp);
}

int main(void) {
    parse_config();

    char msg[768];
    int off = snprintf(msg, sizeof(msg),
                       "Started (pid=%d) | critical:", (int)getpid());
    for (int i = 0; i < n_critical && off < (int)sizeof(msg) - 2; i++)
        off += snprintf(msg + off, sizeof(msg) - off, " %s", critical_apps[i]);
    off += snprintf(msg + off, sizeof(msg) - off, " | restartable:");
    for (int i = 0; i < n_restartable && off < (int)sizeof(msg) - 2; i++)
        off += snprintf(msg + off, sizeof(msg) - off, " %s", restartable_apps[i]);
    log_msg(msg);

    struct timespec ts = { .tv_sec = 0, .tv_nsec = POLL_NS };
    while (1) {
        scan_procs();
        nanosleep(&ts, NULL);
    }
    return 0;
}
