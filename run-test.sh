#!/bin/bash

HPSIZE=2048 # in kB

. lib/generic_setup.sh
. lib/test_setup.sh

grep "numa=fake=" /proc/cmdline > /dev/null
[ $? -ne 0 ] && echo "no numa node" >&2 && exit 1

do_test "numactl --membind 0 test_alloc -m shared  -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test "numactl --membind 0 test_alloc -m private -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

do_test "numactl --membind 0 test_mbind -m shared  -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test "numactl --membind 0 test_mbind -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

do_test "numactl --membind 0 test_move_pages -m shared  -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test "numactl --membind 0 test_move_pages -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

do_test "test_memory_hotremove -m shared  -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
do_test "test_memory_hotremove -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

# In each testcase test program tries to migrate 2 hugepages.
# Now reserve (not allocate) (free hugepages - 2) hugepages to make allocating
# the destination hugepages fail.
trap 'pkill -f hog_hugepages' SIGINT
reserve_most_hugepages &

do_test "numactl --membind 0 test_alloc -m shared -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test "numactl --membind 0 test_alloc -m private -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

do_test "numactl --membind 0 test_mbind -m shared -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test "numactl --membind 0 test_mbind -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

do_test "numactl --membind 0 test_move_pages -m shared -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test "numactl --membind 0 test_move_pages -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

do_test "test_memory_hotremove -m shared -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
do_test "test_memory_hotremove -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

pkill -f hog_hugepages

# In this testcases *allocate* (not just reserve) (free hugepages - 2) hugepages
trap 'pkill -f hog_hugepages' SIGINT
allocate_most_hugepages &

do_test "numactl --membind 0 test_alloc -m shared -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test "numactl --membind 0 test_alloc -m private -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker

do_test "numactl --membind 0 test_mbind -m shared -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test "numactl --membind 0 test_mbind -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker

do_test "numactl --membind 0 test_move_pages -m shared -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test "numactl --membind 0 test_move_pages -m private -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker

do_test "test_memory_hotremove -m shared -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker
do_test "test_memory_hotremove -m private -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

pkill -f hog_hugepages

show_summary
exit 0
