#include <stdio.h>
#include <string.h>
#include "include.h"

int main(int argc, char *argv[]) {
	int ret;
	char buf[BUFLEN];
	int size = 0;
	PS = getpagesize();
	HPS = get_hugepagesize();
	printf("PS %d, HPS %d\n", PS, HPS);

	FILE *f = fopen("/proc/meminfo", "r");
	while (fgets(buf, BUFLEN, f)) {
		if (sscanf(buf, "Hugepagesize: %li ", &size)) {
			printf("%d\n", size);
		}
	}

	printf("%lx\n", HPS);
	return 0;
}
