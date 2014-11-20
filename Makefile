src=test_alloc.c test_mbind.c test_move_pages.c test_memory_hotremove.c hog_hugepages.c movepages.c hugepage.c hugepage_for_hotremove.c test_alloc_thp.c test_mlock_on_shared_thp.c test_mprotect_on_shared_thp.c
exe=$(src:.c=)
srcdir=.
dstdir=/usr/local/bin
dstexe=$(addprefix $(dstdir)/,$(exe))

OPT=-DDEBUG
LIBOPT=-lpthread -lnuma # -lcgroup

all: get_test_core $(exe)

%: %.c
	$(CC) $(CFLAGS) -o $@ $^ $(OPT) $(LIBOPT)

get_test_core:
	git clone https://github.com/Naoya-Horiguchi/test_core || true
	@true

test: all
	@bash run-test.sh -v -r hugepage_migration.rc -n hugepage_migration_test $(TESTCASE_FILTER)

test1g: all
	@bash run-test-1g.sh

install: $(exe)
	for file in $? ; do \
	  mv $$file $(dstdir) ; \
	done

clean:
	for file in $(exe) ; do \
	  rm $(dstdir)/$$file 2> /dev/null ; \
	  rm $(srcdir)/$$file 2> /dev/null ; \
	done
	@make clean -C lib

cleanup: clean
	@rm -rf work/*
	@rm -rf results/*
