#!/bin/bash

HPSIZE=2048 # in kB
TESTNAME=hugepage_migration

. lib/setup_generic.sh
. lib/setup_test_core.sh
. lib/setup_test_tools.sh
. lib/setup_hugepage_migration_test.sh

grep "numa=fake=" /proc/cmdline > /dev/null
[ $? -ne 0 ] && echo "no numa node" >&2 && exit 1

do_test 'migratepages shared'  "numactl --membind 0 ${TESTALLOC} -m shared   -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test 'migratepages private' "numactl --membind 0 ${TESTALLOC} -m private  -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

do_test 'mbind migration shared'  "numactl --membind 0 ${TESTMBIND} -m shared  -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test 'mbind migration private' "numactl --membind 0 ${TESTMBIND} -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

do_test 'move_pages migration shared'  "numactl --membind 0 ${TESTMOVEPAGES} -m shared  -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test 'move_pages migration private' "numactl --membind 0 ${TESTMOVEPAGES} -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

do_test 'memory hotremove migration shared'  "${TESTHOTREMOVE} -m shared  -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
do_test 'memory hotremove migration private' "${TESTHOTREMOVE} -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

# In each testcase test program tries to migrate 2 hugepages.
# Now reserve (not allocate) (free hugepages - 2) hugepages to make allocating
# the destination hugepages fail.
trap 'pkill -f hog_hugepages' SIGINT
reserve_most_hugepages &

do_test 'migratepages shared'  "numactl --membind 0 ${TESTALLOC} -m shared   -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test 'migratepages private' "numactl --membind 0 ${TESTALLOC} -m private  -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

do_test 'mbind migration shared'  "numactl --membind 0 ${TESTMBIND} -m shared  -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test 'mbind migration private' "numactl --membind 0 ${TESTMBIND} -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

do_test 'move_pages migration shared'  "numactl --membind 0 ${TESTMOVEPAGES} -m shared  -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test 'move_pages migration private' "numactl --membind 0 ${TESTMOVEPAGES} -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

do_test 'memory hotremove migration shared'  "${TESTHOTREMOVE} -m shared  -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
do_test 'memory hotremove migration private' "${TESTHOTREMOVE} -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

pkill -f hog_hugepages

# In this testcases *allocate* (not just reserve) (free hugepages - 2) hugepages
trap 'pkill -f hog_hugepages' SIGINT
allocate_most_hugepages &

do_test 'migratepages shared'  "numactl --membind 0 ${TESTALLOC} -m shared   -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test 'migratepages private' "numactl --membind 0 ${TESTALLOC} -m private  -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

do_test 'mbind migration shared'  "numactl --membind 0 ${TESTMBIND} -m shared  -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test 'mbind migration private' "numactl --membind 0 ${TESTMBIND} -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

do_test 'move_pages migration shared'  "numactl --membind 0 ${TESTMOVEPAGES} -m shared  -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test 'move_pages migration private' "numactl --membind 0 ${TESTMOVEPAGES} -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

do_test 'memory hotremove migration shared'  "${TESTHOTREMOVE} -m shared  -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
do_test 'memory hotremove migration private' "${TESTHOTREMOVE} -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

pkill -f hog_hugepages

show_summary
exit 0
