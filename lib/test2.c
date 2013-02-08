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
	int nr = 2;
	struct bitmask *all_nodes;
	struct bitmask *old_nodes;
	struct bitmask *new_nodes;
	void **addrs;
	int *status;
	int *nodes;
	int mode;
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
#ifdef DEBUG2
	addrs  = malloc(sizeof(char *) * nr*512);
	status = malloc(sizeof(char *) * nr*512);
	nodes  = malloc(sizeof(char *) * nr*512);
#endif
	signal(SIGUSR1, sig_handle);
	p = mmap((void *)BASEVADDR, nr * HPS, protflag, mapflag, -1, 0);
	if (p == MAP_FAILED)
		err("mmap");
	for (i = 0; i < nr; i++)
		p[i * HPS] = 'a';

	printf("Waiting signal.\n");
	pause();

	numa_sched_setaffinity(0, all_nodes);

	ret = mbind(p, nr * HPS, MPOL_BIND, new_nodes->maskp,
		    new_nodes->size + 1, MPOL_MF_MOVE|MPOL_MF_STRICT);
	if (ret == -1)
		err("mbind");

	printf("busy loop to check pageflags\n");
	signal(SIGUSR1, sig_handle_flag);
	while (flag) {
		for (i = 0; i < nr; i++)
			p[i * HPS] = 'a';
	}

	printf("Exit.\n");
	return 0;
}
