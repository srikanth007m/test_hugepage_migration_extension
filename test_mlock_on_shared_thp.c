#define _GNU_SOURCE
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
#include <numa.h>
#include <numaif.h>
#include <sched.h>
#include <wait.h>
#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

void set_cpu_affinity(int cpu) {
	int ret;
	cpu_set_t cpuset;

	CPU_ZERO(&cpuset);
	CPU_SET(cpu, &cpuset);
	pprintf("current CPU %d\n", sched_getcpu());
	ret = sched_setaffinity(0, sizeof(cpuset), &cpuset);
	if (ret == -1)
		err("sched_setaffinity");
	pprintf("current CPU %d\n", sched_getcpu());
}

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	char c;
	char *p;
	int mapflag = MAP_ANONYMOUS | MAP_PRIVATE;
	int protflag = PROT_READ|PROT_WRITE;
        unsigned long nr_nodes = numa_max_node() + 1;
        unsigned long nodemask;
	int ret;
	pid_t pid;

	while ((c = getopt(argc, argv, "vp:n:")) != -1) {
		switch(c) {
                case 'v':
                        verbose = 1;
                        break;
                case 'p':
                        testpipe = optarg;
                        {
                                struct stat stat;
                                lstat(testpipe, &stat);
                                if (!S_ISFIFO(stat.st_mode))
                                        errmsg("Given file is not fifo.\n");
                        }
                        break;
		case 'n':
			nr = strtoul(optarg, NULL, 10);
			break;
		default:
			errmsg("invalid option\n");
			break;
		}
	}

	signal(SIGUSR1, sig_handle);

	p = mmap((void *)ADDR_INPUT, nr * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED) {
		pprintf("mmap failed\n");
		err("mmap");
	}
	pprintf("do madvise(MADV_HUGEPAGE)\n");
	ret = madvise(p, nr * HPS, MADV_HUGEPAGE);
	if (ret == -1)
		err("madvise");
	/* fault in */
	memset(p, 'a', nr * HPS);
	signal(SIGUSR1, sig_handle_flag);

	pprintf("before fork\n");
	pause();

	pid = fork();
	if (pid)
		pprintf("pid %d (parent)\n", getpid());
	else
		pprintf("pid %d (child)\n", getpid());
	for (i = 0; i < nr; i++)
		c = p[i*nr];

	pprintf("check shared thp\n");
	pause();

	if (!pid) {
		pprintf("mlock\n");
		if (mlock(p, HPS))
			err("mlock");
		pause();
		return 0;
	}

	pprintf("exited busy loop\n");
	pause();
	return 0;
}
