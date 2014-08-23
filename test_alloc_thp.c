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
#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	char c;
	char *p;
	char *dummy;
	int mapflag = MAP_ANONYMOUS | MAP_PRIVATE;
	int protflag = PROT_READ|PROT_WRITE;
        unsigned long nr_nodes = numa_max_node() + 1;
        unsigned long nodemask;
	int ret;
	cpu_set_t *cpuset;

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

        if (nr_nodes < 2)
                errmsg("A minimum of 2 nodes is required for this test.\n");

	/*
	 * Dummy memory regions to dominate the virtual space with
	 * memory from node 1, letting thp on node 0 minor.
	 */
	dummy = malloc(10 * nr * HPS);
	if (!dummy)
		err("malloc");
	memset(dummy, 1, 10 * nr *HPS);

	signal(SIGUSR1, sig_handle);
	pprintf("before allocating thps\n");
	pause();

	p = mmap((void *)ADDR_INPUT, nr * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED) {
		pprintf("mmap failed\n");
		err("mmap");
	}
	pprintf("mmap ok\n");

	cpuset = CPU_ALLOC(numa_num_configured_cpus());
	if (!cpuset)
		err("CPU_ALLOC");
	CPU_ZERO(cpuset);
	CPU_SET(0, cpuset);
	pprintf("current CPU %d\n", sched_getcpu());
	ret = sched_setaffinity(0,
				CPU_ALLOC_SIZE(numa_num_configured_cpus()),
				cpuset);
	if (ret == -1)
		err("sched_setaffinity");
	pprintf("current CPU %d\n", sched_getcpu());

	/* nodemask = 1; /\* set only on node 0. *\/ */
	/* ret = mbind(p, nr * HPS, MPOL_BIND, &nodemask, */
	/* 	    nr_nodes, MPOL_MF_MOVE_ALL); */
	/* if (ret == -1) */
	/* 	err("mbind"); */
	pprintf("do madvise(MADV_HUGEPAGE)\n");
	ret = madvise(p, nr * HPS, MADV_HUGEPAGE);
	if (ret == -1)
		err("madvise");
	/* fault in */
	memset(p, 'a', nr * HPS);
	/* pprintf("set mempolicy to default\n"); */
	/* pause(); */
	/* ret = mbind(p, nr * HPS, MPOL_DEFAULT, NULL, */
	/* 	    0, MPOL_MF_MOVE_ALL); */
	/* if (ret == -1) */
	/* 	err("mbind"); */
	signal(SIGUSR1, sig_handle_flag);

	CPU_ZERO(cpuset);
	CPU_SET(1, cpuset);
	pprintf("current CPU %d\n", sched_getcpu());
	ret = sched_setaffinity(0,
				CPU_ALLOC_SIZE(numa_num_configured_cpus()),
				cpuset);
	if (ret == -1)
		err("sched_setaffinity");
	pprintf("current CPU %d\n", sched_getcpu());

	pprintf("entering busy loop\n");
	while (flag) {
		memset(dummy, 1, 10 * nr *HPS);
		memset(p, 'a', nr * HPS);
	}
	pprintf("exited busy loop\n");
	pause();
	return 0;
}
