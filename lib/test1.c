#include <stdio.h>
#include <signal.h>
#include <sys/mman.h>
#include "include.h"
#include <sys/types.h>
#include <unistd.h>
#include <numaif.h>
#include <string.h>
#include <stdlib.h>

int flag = 1;

void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	char *p;
	char *q;
	int i;
	int ret;
	int nr = 2;
	unsigned long oldnodes = 0x1;
	unsigned long newnodes = 0x2;
	int mode;
	unsigned long nodemask;
	int nr_nodes = numa_num_possible_nodes();
	int mapflag = MAP_SHARED;

	if (argc >= 2) {
		if (!strcmp(argv[1], "private"))
			mapflag = MAP_PRIVATE;
	}

	signal(SIGUSR1, sig_handle);
	p = mmap((void *)BASEVADDR, nr * HPS, PROT_READ|PROT_WRITE,
		 mapflag|MAP_ANONYMOUS|MAP_HUGETLB, -1, 0);
	if (p == MAP_FAILED)
		err("mmap");
	for (i = 0; i < nr; i++)
		p[i * HPS] = 'a';
	q = malloc(nr * HPS);
	memset(q, 'a', nr * HPS);
#ifdef DEBUG
	printf("nodes: %d, flag: 0x%lx\n", nr_nodes, MPOL_F_NODE|MPOL_F_ADDR);
	ret = get_mempolicy(&mode, &nodemask, nr_nodes, p,
			    MPOL_F_NODE|MPOL_F_ADDR);
	if (ret == -1)
		err("get_mempolicy");
	printf("mempolicy: mode %d, nodemask 0x%lx\n", mode, nodemask);
#endif
	printf("Waiting signal.\n");
	pause();
#ifdef DEBUG2
	printf("call migrate_pages\n");
	i = migrate_pages(getpid(), nr_nodes, &oldnodes, &newnodes);
#endif
	printf("busy loop to check pageflags\n");
	signal(SIGUSR1, sig_handle_flag);
	while (flag) {
		for (i = 0; i < nr; i++)
			p[i * HPS] = 'a';
	}
#ifdef DEBUG
	printf("nodes: %d, flag: 0x%lx\n", nr_nodes, MPOL_F_NODE|MPOL_F_ADDR);
	ret = get_mempolicy(&mode, &nodemask, nr_nodes, p,
			    MPOL_F_NODE|MPOL_F_ADDR);
	if (ret == -1)
		err("get_mempolicy");
	printf("mempolicy: mode %d, nodemask 0x%lx\n", mode, nodemask);
#endif
	printf("Exit.\n");
	return 0;
}
