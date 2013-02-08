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

int flag = 1;

void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	char *p;
	int i;
	int ret;
	int nr_hp = 2;
	int nr_p  = nr_hp * HPS / PS;
	struct bitmask *all_nodes;
	struct bitmask *old_nodes;
	struct bitmask *new_nodes;
	unsigned long nr_nodes = numa_max_node() + 1; /* numa_num_possible_nodes(); */
	int mapflag = MAP_ANONYMOUS;
	int protflag = PROT_READ|PROT_WRITE;

	/* printf("nr_nodes %d\n", nr_nodes); */
	char c;
	while ((c = getopt(argc, argv, "m:h")) != -1) {
		switch(c) {
		case 'm':
			if (!strcmp(optarg, "private"))
				mapflag |= MAP_PRIVATE;
			else if (!strcmp(optarg, "shared"))
				mapflag |= MAP_SHARED;
			break;
		case 'h':
			mapflag |= MAP_HUGETLB;
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
	p = mmap((void *)BASEVADDR, nr_hp * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED)
		err("mmap");
	for (i = 0; i < nr_p; i++)
		p[i * PS] = 'a';

	printf("Waiting signal.\n");
	pause();

	numa_sched_setaffinity(0, all_nodes);

	printf("busy loop to check pageflags\n");
	signal(SIGUSR1, sig_handle_flag);
	while (flag) {
		sleep(1);
		for (i = 0; i < nr_p; i++)
			p[i * PS] = 'a';
	}

	printf("Exit.\n");
	return 0;
}
