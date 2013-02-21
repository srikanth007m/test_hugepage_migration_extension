CC=gcc
CFLAGS=-g # -Wall -Wextra

src=test_alloc.c test_mbind.c test_move_pages.c test_memory_hotremove.c page-types.c hog_hugepages.c
exe=$(src:.c=)
srcdir=.
dstdir=/usr/local/bin
dstexe=$(addprefix $(dstdir)/,$(exe))

OPT=-DDEBUG
LIBOPT=-lnuma # -lcgroup

all: $(exe)
%: %.c
	$(CC) $(CFLAGS) -o $@ $^ $(OPT) $(LIBOPT)

install: $(exe)
	for file in $? ; do \
	  mv $$file $(dstdir) ; \
	done

clean:
	for file in $(exe) ; do \
	  rm $(dstdir)/$$file 2> /dev/null ; \
	  rm $(srcdir)/$$file 2> /dev/null ; \
	done
