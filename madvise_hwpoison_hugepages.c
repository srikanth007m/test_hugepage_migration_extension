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
#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int i;
	int ret;
	int nr = 2;
	char c;
	char *p;
	int mapflag = MAP_ANONYMOUS;
	int protflag = PROT_READ|PROT_WRITE;
        unsigned long nr_nodes = numa_max_node() + 1;
        struct bitmask *new_nodes;
        unsigned long nodemask;
	int do_unpoison = 0;
	int loop = 3;

	while ((c = getopt(argc, argv, "vp:m:n:ul:h:")) != -1) {
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
		case 'm':
			if (!strcmp(optarg, "private"))
				mapflag |= MAP_PRIVATE;
			else if (!strcmp(optarg, "shared"))
				mapflag |= MAP_SHARED;
			else
				errmsg("invalid optarg for -m\n");
			break;
		case 'n':
			nr = strtoul(optarg, NULL, 10);
			break;
		case 'u':
			do_unpoison = 1;
			break;
		case 'l':
			loop = strtoul(optarg, NULL, 10);
			break;
		case 'h':
			HPS = strtoul(optarg, NULL, 10) * 1024;
			mapflag |= MAP_HUGETLB;
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

        new_nodes = numa_bitmask_alloc(nr_nodes);
        numa_bitmask_setbit(new_nodes, 1);

        nodemask = 1; /* only node 0 allowed */
        if (set_mempolicy(MPOL_BIND, &nodemask, nr_nodes) == -1)
                err("set_mempolicy");

	signal(SIGUSR2, sig_handle);
	pprintf("start background migration\n");
	pause();

	signal(SIGUSR1, sig_handle_flag);
	pprintf("hugepages prepared\n");

	while (flag) {
		p = checked_mmap((void *)ADDR_INPUT, nr * HPS, protflag, mapflag, -1, 0);
		/* fault in */
		memset(p, 'a', nr * HPS);
		for (i = 0; i < nr; i++) {
			ret = madvise(p + i * HPS, 4096, MADV_HWPOISON);
			if (ret) {
				perror("madvise");
				pprintf("madvise returned %d\n", ret);
			}
		}
		if (do_unpoison) {
			pprintf("need unpoison\n");
			pause();
		}
		checked_munmap(p, nr * HPS);
		if (loop-- <= 0)
			break;
	}
	pprintf("exit\n");
	pause();
	return 0;
}
