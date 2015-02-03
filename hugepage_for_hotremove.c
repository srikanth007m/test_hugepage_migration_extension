#include <stdio.h>
#include <sys/mman.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"
#include "test_core/lib/pfn.h"

#define ADDR_INPUT	0x700000000000UL

/*
 * Memory block size is 128MB (1 << 27) = 32k pages (1 << 15)
 */
#define MEMBLK_ORDER	15
#define MAX_MEMBLK	1024

int flag = 1;

void sig_handle(int signo) { ; }
void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int nr_hp = 2;
	char *p;
	int i;
	unsigned long *pfns;
	int nr_hps_per_memblk[MAX_MEMBLK] = {};
	int max_nr_hps = 0;
	int preferred_memblk = 0;
	int ret;
	char c;
	int mapflag = MAP_ANONYMOUS | MAP_HUGETLB;

	while ((c = getopt(argc, argv, "vp:m:n:")) != -1) {
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
			nr_hp = strtoul(optarg, NULL, 0);
			break;
		default:
			errmsg("invalid option\n");
			break;
		}
	}

	signal(SIGUSR1, sig_handle);
	p = checked_mmap((void *)ADDR_INPUT, nr_hp * HPS, PROT_READ | PROT_WRITE,
			 mapflag, -1, 0);
	memset(p, 0, nr_hp * HPS);
	pfns = malloc(nr_hp * sizeof(unsigned long));
	if (!pfns)
		err("malloc");
	memset(pfns, 0, nr_hp * sizeof(unsigned long));
	for (i = 0; i < MAX_MEMBLK; i++)
		nr_hps_per_memblk[i] = 0;
	for (i = 0; i < nr_hp; i++) {
		pfns[i] = get_my_pfn(&p[i * HPS]);
		nr_hps_per_memblk[pfns[i] >> MEMBLK_ORDER] += 1;
	}
	for (i = 0; i < MAX_MEMBLK; i++) {
		if (verbose && nr_hps_per_memblk[i] > 0)
			printf("memblock %d: hps %d\n", i, nr_hps_per_memblk[i]);
		if (nr_hps_per_memblk[i] > max_nr_hps) {
			max_nr_hps = nr_hps_per_memblk[i];
			preferred_memblk = i;
		}
	}

	/* unmap all hugepages except ones in preferred_memblk */
	for (i = 0; i < nr_hp; i++)
		if (pfns[i] >> MEMBLK_ORDER != preferred_memblk)
			checked_munmap(&p[i * HPS], HPS);

	pprintf("before memory_hotremove: %d\n", preferred_memblk);
	pause();
	signal(SIGUSR1, sig_handle_flag);
	pprintf("entering busy loop\n");
	while (flag)
		for (i = 0; i < nr_hp; i++)
			if (pfns[i] >> MEMBLK_ORDER == preferred_memblk)
				memset(&p[i * HPS], 'a', HPS);
	pprintf("exited busy loop\n");
	pause();
	for (i = 0; i < nr_hp; i++)
		if (pfns[i] >> MEMBLK_ORDER == preferred_memblk)
			checked_munmap(&p[i * HPS], HPS);
	return 0;
}
