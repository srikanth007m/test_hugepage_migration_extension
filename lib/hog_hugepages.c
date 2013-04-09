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
	char c;
	char *p;
	int just_reserve = 0;
	int target_node = -1; /* -1 means 'all nodes' */
	struct bitmask *all_nodes;
	struct bitmask *old_nodes;
	unsigned long nr_nodes = numa_max_node() + 1; /* numa_num_possible_nodes(); */
	int mapflag = MAP_ANONYMOUS|MAP_HUGETLB;
	int protflag = PROT_READ|PROT_WRITE;

	while ((c = getopt(argc, argv, "m:p:n:N:r")) != -1) {
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
		case 'N':
			target_node = strtoul(optarg, NULL, 10);
			break;
		case 'r':
			just_reserve = 1;
			break;
		}
	}

	if (nr_nodes < 2)
		errmsg("A minimum of 2 nodes is required for this test.\n");

	all_nodes = numa_bitmask_alloc(nr_nodes);
	old_nodes = numa_bitmask_alloc(nr_nodes);
	for (i = 0; i < nr_nodes; i++)
		numa_bitmask_setbit(all_nodes, i);
	if (target_node == -1)
		for (i = 0; i < nr_nodes; i++)
			numa_bitmask_setbit(old_nodes, i);
	else
		numa_bitmask_setbit(old_nodes, target_node);
	numa_sched_setaffinity(0, old_nodes);
	signal(SIGUSR1, sig_handle);
	p = checked_mmap((void *)ADDR_INPUT, nr * HPS, protflag, mapflag, -1, 0);
	if (just_reserve) {
		pprintf("Waiting signal.\n");
		pause();
	} else {
		numa_sched_setaffinity(0, all_nodes);
		pprintf("busy loop to check pageflags\n");
		memset(p, 'a', nr * HPS);
		signal(SIGUSR1, sig_handle_flag);
		while (flag) {
			sleep(1);
			memset(p, 'a', nr * HPS);
		}
	}
	pprintf("hog_hugepages exit\n");
	pause();
	return 0;
}
