#!/bin/bash

HPSIZE=1048576 # in kB
TESTNAME=hugepage_migration_1g

. lib/setup_generic.sh
. lib/setup_test_core.sh
. lib/setup_test_tools.sh
. lib/setup_hugepage_migration_test.sh

grep "numa=fake=" /proc/cmdline > /dev/null
[ $? -ne 0 ] && echo "no numa node" >&2 && exit 1

ulimit -l unlimited

do_test 'migratepages shared'  "numactl --membind 0 ${TESTALLOC} -m shared   -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
# do_test 'migratepages private' "numactl --membind 0 ${TESTALLOC} -m private  -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

# do_test 'mbind migration shared'  "numactl --membind 0 ${TESTMBIND} -m shared  -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
# do_test 'mbind migration private' "numactl --membind 0 ${TESTMBIND} -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

# do_test 'move_pages migration shared'  "numactl --membind 0 ${TESTMOVEPAGES} -m shared  -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
# do_test 'move_pages migration private' "numactl --membind 0 ${TESTMOVEPAGES} -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

# do_test 'memory hotremove migration shared'  "${TESTHOTREMOVE} -m shared  -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
# do_test 'memory hotremove migration private' "${TESTHOTREMOVE} -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

show_summary
exit 0
