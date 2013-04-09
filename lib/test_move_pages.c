#include <stdio.h>
#include <signal.h>
#include <sys/mman.h>
#include "include.h"
#include <sys/types.h>
#include <unistd.h>
#include <asm/unistd.h>
#include <numa.h>
#include <numaif.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int i;
	int nr_hp = 2;
	int nr_p  = nr_hp * HPS / PS;
	int ret;
	char c;
	char *p;
	int mapflag = MAP_ANONYMOUS|MAP_HUGETLB;
	int protflag = PROT_READ|PROT_WRITE;
	unsigned long nr_nodes = numa_max_node() + 1; /* numa_num_possible_nodes(); */
	struct bitmask *all_nodes;
	struct bitmask *old_nodes;
	struct bitmask *new_nodes;
	void **addrs;
	int *status;
	int *nodes;

	while ((c = getopt(argc, argv, "m:p:n:h:N")) != -1) {
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
			nr_hp = strtoul(optarg, NULL, 10);
			nr_p  = nr_hp * HPS / PS;
			break;
		case 'h':
			HPS = strtoul(optarg, NULL, 10) * 1024;
			/* todo: arch independent */
			if (HPS != 2097152 && HPS != 1073741824)
				errmsg("Invalid hugepage size\n");
			break;
		case 'N':
			mapflag &= ~MAP_HUGETLB;
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
	addrs  = malloc(sizeof(char *) * nr_p + 1);
	status = malloc(sizeof(char *) * nr_p + 1);
	nodes  = malloc(sizeof(char *) * nr_p + 1);
	signal(SIGUSR1, sig_handle);
	p = mmap((void *)ADDR_INPUT, nr_hp * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED)
		err("mmap");
	/* fault in */
	memset(p, 'a', nr_hp * HPS);
	pprintf("before move_pages\n");
	pause();
	numa_sched_setaffinity(0, all_nodes);
	for (i = 0; i < nr_p; i++) {
		addrs[i] = p + i * PS;
		nodes[i] = 1;
		status[i] = 0;
	}
	ret = numa_move_pages(0, nr_p, addrs, nodes, status, MPOL_MF_MOVE_ALL);
	if (ret == -1)
		err("move_pages");
	signal(SIGUSR1, sig_handle_flag);
	pprintf("entering busy loop\n");
	while (flag)
		memset(p, 'a', nr_hp * HPS);
	pprintf("exited busy loop\n");
	pause();
	return 0;
}
