#include <stdlib.h>

void sig_handle(int signo) { return; }
#define PS    4096
#define HPS   512*PS
#define BASEVADDR 0x700000000000
#define err(x) perror(x),exit(EXIT_FAILURE)
#define errmsg(x) fprintf(stderr, x),exit(EXIT_FAILURE)

