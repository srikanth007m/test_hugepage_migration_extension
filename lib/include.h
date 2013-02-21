#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

void sig_handle(int signo) { return; }
int PS = 4096;
int HPS = 2097152;
#define BASEVADDR 0x700000000000
#define err(x) perror(x),exit(EXIT_FAILURE)
#define errmsg(x) fprintf(stderr, x),exit(EXIT_FAILURE)
#define strpair(x) x, strlen(x)

#define BUFLEN 256
int get_hugepagesize(void) {
	int size = 0;
	char buf[BUFLEN];
	FILE *f = fopen("/proc/meminfo", "r");
	while (fgets(buf, BUFLEN, f))
		if (sscanf(buf, "Hugepagesize: %li ", &size))
			return size * 1024;
	errmsg("fail to retrieve hugepage size.\n");
}

static int write_check(int fd, char *str) {
	int ret;
	if (fd == 0)
		fd = 1;
	ret = write(fd, strpair(str));
	if (ret < 0)
		err("write");
	return ret;
}

static int write_pipe(char *path, char *str) {
	int ret;
	if (!path)
		return 0;
	int pipefd = open(path, O_WRONLY);
	if (pipefd < 0)
		err("open pipe");
	ret = write_check(pipefd, str);
	close(pipefd);
	return ret;
}
