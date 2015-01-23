#include <stdio.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <asm/unistd.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>
#include <numa.h>
#include <numaif.h>
#include <sys/time.h>
#include "test_core/lib/include.h"
#include "test_core/lib/hugepage.h"

/*
 * on x86_64
 *  PMD_SHIFT 21   0x000000200000
 *  PUD_SHIFT 30   0x000040000000
 *  PGD_SHIFT 39   0x008000000000
 */

#define ADDR_INPUT 0x700000000000

int flag = 1;

void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int i;
	int nr = 2;
	int ret;
	int fd = -1;
	char c;
	int hugetlbfd1;
	int hugetlbfd2;
	char *hugetlbfile1 = "work/mount/testfile1";
	char *hugetlbfile2 = "work/mount/testfile2";
	unsigned long memsize = 2*1024*1024;
	int mapflag = MAP_ANONYMOUS;
	unsigned long address = ADDR_INPUT;
	char *phugetlbanon;
	char *phugetlbfile1;
	char *phugetlbfile2;
	char *phugetlbshmem;
	unsigned long nr_nodes = numa_max_node() + 1; /* numa_num_possible_nodes(); */
	char cmd[256];
	int HPS = 2097152;
	struct timeval tv;
	struct bitmask *nodes;
	unsigned long type = 0xffff;

	while ((c = getopt(argc, argv, "p:vn:t:")) != -1) {
		switch(c) {
		case 'p':
			testpipe = optarg;
			{
				struct stat stat;
				lstat(testpipe, &stat);
				if (!S_ISFIFO(stat.st_mode))
					errmsg("Given file is not fifo.\n");
			}
			break;
		case 'v':
			verbose = 1;
			break;
		case 'n':
			nr = strtoul(optarg, NULL, 10);
			memsize = nr * HPS;
			break;
		case 't':
			type = strtoul(optarg, NULL, 0);
			break;
		default:
			errmsg("invalid option\n");
			break;
		}
	}

	if (nr_nodes < 2)
		errmsg("A minimum of 2 nodes is required for this test.\n");

	gettimeofday(&tv, NULL);
	srandom(tv.tv_usec);
	nodes = numa_bitmask_alloc(nr_nodes);

	if (type & (1 << 0)) {
		mapflag = MAP_PRIVATE|MAP_ANONYMOUS|MAP_HUGETLB;
		phugetlbanon = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag,
					    -1, 0);
		memset(phugetlbanon, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 1)) {
		hugetlbfd1 = open(hugetlbfile1, O_CREAT|O_RDWR, 0755);
		if (hugetlbfd1 == -1)
			errmsg("open hugetlbfs");
		mapflag = MAP_SHARED;
		phugetlbfile1 = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag,
					     hugetlbfd1, 0);
		memset(phugetlbfile1, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 2)) {
		hugetlbfd2 = open(hugetlbfile2, O_CREAT|O_RDWR, 0755);
		if (hugetlbfd2 == -1)
			errmsg("open hugetlbfs");
		mapflag = MAP_PRIVATE;
		phugetlbfile2 = checked_mmap((void *)address, memsize, MMAP_PROT, mapflag,
					     hugetlbfd2, 0);
		memset(phugetlbfile2, 'a', memsize);
		address += memsize;
	}
	if (type & (1 << 3)) {
		phugetlbshmem = alloc_shm_hugepage(memsize);
		memset(phugetlbshmem, 'a', memsize);
		address += memsize;
	}

	signal(SIGUSR1, sig_handle_flag);

	pprintf("entering busy loop\n");
	while (flag) {
		sprintf(cmd, "migratepages %d %d %d", getpid(), random() % nr_nodes, random() % nr_nodes);
		pprintf("%s\n", cmd);
		system(cmd);
		usleep(1000);
		if (type & (1 << 0)) memset(phugetlbanon, 'a', memsize);
		if (type & (1 << 1)) memset(phugetlbfile1, 'a', memsize);
		if (type & (1 << 2)) memset(phugetlbfile2, 'a', memsize);
		if (type & (1 << 3)) memset(phugetlbshmem, 'a', memsize);
		sprintf(cmd, "migratepages %d %d %d", getpid(), random() % nr_nodes, random() % nr_nodes);
		pprintf("%s\n", cmd);
		system(cmd);
		usleep(1000);
		if (type & (1 << 0)) memset(phugetlbanon, 'a', memsize);
		if (type & (1 << 1)) memset(phugetlbfile1, 'a', memsize);
		if (type & (1 << 2)) memset(phugetlbfile2, 'a', memsize);
		if (type & (1 << 3)) memset(phugetlbshmem, 'a', memsize);
	}
	if (type & (1 << 0)) munmap(phugetlbanon, memsize);
	if (type & (1 << 1)) munmap(phugetlbfile1, memsize);
	if (type & (1 << 2)) munmap(phugetlbfile2, memsize);
	if (type & (1 << 3)) munmap(phugetlbshmem, memsize);
	return 0;
}
