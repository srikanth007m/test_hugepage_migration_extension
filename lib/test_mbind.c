#include <stdio.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <asm/unistd.h>
#include <numa.h>
#include <numaif.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>
#include "include.h"

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	int ret;
	char c;
	char *p;
	int mapflag = MAP_ANONYMOUS;
	int protflag = PROT_READ|PROT_WRITE;
	unsigned long nr_nodes = numa_max_node() + 1; /* numa_num_possible_nodes(); */
	struct bitmask *all_nodes;
	struct bitmask *old_nodes;
	struct bitmask *new_nodes;

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
		case 'h':
			mapflag |= MAP_HUGETLB;
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

	if (nr_nodes < 2)
		errmsg("A minimum of 2 nodes is required for this test.\n");

	all_nodes = numa_bitmask_alloc(nr_nodes);
	old_nodes = numa_bitmask_alloc(nr_nodes);
	new_nodes = numa_bitmask_alloc(nr_nodes);
	numa_bitmask_setbit(all_nodes, 0);
	numa_bitmask_setbit(all_nodes, 1);
	numa_bitmask_setbit(old_nodes, 0);
	numa_bitmask_setbit(new_nodes, 1);
	numa_sched_setaffinity(0, old_nodes);
	signal(SIGUSR1, sig_handle);
	p = mmap((void *)ADDR_INPUT, nr * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED)
		err("mmap");
	/* fault in */
	memset(p, 'a', nr * HPS);
	pprintf("before mbind\n");
	pause();
	numa_sched_setaffinity(0, all_nodes);
	ret = mbind(p, nr * HPS, MPOL_BIND, new_nodes->maskp,
		    new_nodes->size + 1, MPOL_MF_MOVE|MPOL_MF_STRICT);
	if (ret == -1)
		err("mbind");
	signal(SIGUSR1, sig_handle_flag);
	pprintf("entering busy loop\n");
	while (flag)
		memset(p, 'a', nr * HPS);
	pprintf("exited busy loop\n");
	pause();
	return 0;
}
