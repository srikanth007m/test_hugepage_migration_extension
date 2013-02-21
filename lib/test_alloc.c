#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <getopt.h>
#include "include.h"

int flag = 1;

void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	char c;
	char *p;
	char *pipe = NULL;
	int mapflag = MAP_ANONYMOUS|MAP_HUGETLB;
	int protflag = PROT_READ|PROT_WRITE;

	PS = getpagesize();
	HPS = get_hugepagesize(); /* set default hugepage size */

	while ((c = getopt(argc, argv, "m:p:n:h:")) != -1) {
		switch(c) {
		case 'm':
			if (!strcmp(optarg, "private"))
				mapflag |= MAP_PRIVATE;
			else if (!strcmp(optarg, "shared"))
				mapflag |= MAP_SHARED;
			else
				errmsg("invalid optarg for -m\n");
			break;
		case 'p':
			pipe = optarg;
			{
				struct stat stat;
				lstat(pipe, &stat);
				if (!S_ISFIFO(stat.st_mode))
					errmsg("Given file is not fifo.\n");
			}
			break;
		case 'n':
			nr = strtoul(optarg, NULL, 10);
			break;
		case 'h':
			HPS = strtoul(optarg, NULL, 10) * 1024;
			/* todo: arch independent */
			if (HPS != 2097152 && HPS != 1073741824)
				errmsg("Invalid hugepage size\n");
			break;
		default:
			errmsg("invalid option\n");
			break;
		}
	}

	printf("pipe %p\n", pipe);
	p = mmap((void *)BASEVADDR, nr * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED)
		err("mmap");
	/* fault in */
	memset(p, 'a', nr * HPS);
	signal(SIGUSR1, sig_handle_flag);
	printf("pipe %p\n", pipe);
	write_pipe(pipe, "entering busy loop\n");
	while (flag)
		memset(p, 'a', nr * HPS);
	write_pipe(pipe, "exited busy loop\n");
	pause();
	return 0;
}
