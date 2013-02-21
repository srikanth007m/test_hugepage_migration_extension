#!/bin/bash

HPSIZE=1048576 # in kB

. lib/generic_setup.sh
. lib/test_setup.sh

grep "numa=fake=" /proc/cmdline > /dev/null
[ $? -ne 0 ] && echo "no numa node" >&2 && exit 1

do_test "numactl --membind 0 test_alloc -n 1 -m shared -p ${PIPE} -h ${HPSIZE}" migratepages_controller migration_checker
do_test "numactl --membind 0 test_mbind -n 1 -m private -p ${PIPE} -h ${HPSIZE}" mbind_migration_controller migration_checker
do_test "numactl --membind 0 test_move_pages -n 1 -m shared -p ${PIPE} -h ${HPSIZE}" move_pages_controller migration_checker
do_test "test_memory_hotremove -n 1 -m shared -p ${PIPE} -h ${HPSIZE}" memory_hotremove_controller memory_hotremove_checker

show_summary
exit 0
