#include <stdio.h>
#include <sys/mman.h>
#include <string.h>

#define ADDR_INPUT	0x700000000000UL
#define HPS		0x200000

int main(int argc, char *argv[]) {
	int nr_hp = strtol(argv[1], NULL, 0);
	char *p;

	while (1) {
		p = mmap((void *)ADDR_INPUT, nr_hp * HPS, PROT_READ | PROT_WRITE,
			 MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
		if (p != (void *)ADDR_INPUT) {
			perror("mmap");
			break;
		}
		memset(p, 0, nr_hp * HPS);
		munmap(p, nr_hp * HPS);
	}
}
