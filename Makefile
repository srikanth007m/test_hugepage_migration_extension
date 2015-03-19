src=test_alloc.c test_mbind.c test_move_pages.c test_memory_hotremove.c hog_hugepages.c iterate_numa_move_pages.c iterate_hugepage_mmap_fault_munmap.c hugepage_for_hotremove.c test_alloc_thp.c test_mlock_on_shared_thp.c test_mprotect_on_shared_thp.c madvise_hwpoison_hugepages.c hugepage_pingpong.c
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
	@test -d "test_core" || git clone https://github.com/Naoya-Horiguchi/test_core
	@true

test: all
	@bash run-test.sh -v -r hugepage_migration.rc -n hugepage_migration_test $(TESTCASE_FILTER)

test1g: all
	@bash run-test-1g.sh

clean:
	@for file in $(exe) ; do \
	  rm "$(srcdir)/$$file" 2> /dev/null ; \
	  true ; \
	done

cleanup: clean
	@rm -rf work/*
	@rm -rf results/*
	@true
