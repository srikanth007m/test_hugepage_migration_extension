#include <stdio.h>
#include <sys/mman.h>
#include <string.h>
#include <signal.h>

#define ADDR_INPUT	0x700000000000UL
#define HPS		0x200000

int flag = 1;

void sig_handle_flag(int signo) { flag = 0; }

int main(int argc, char *argv[]) {
	int nr_hp = strtol(argv[1], NULL, 0);
	char *p;

	signal(SIGUSR1, sig_handle_flag);
	while (flag) {
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
