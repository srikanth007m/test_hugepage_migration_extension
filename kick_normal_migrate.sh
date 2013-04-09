#!/bin/bash

HPSIZE=2048 # in kB
TESTNAME=normal_migration

. lib/setup_generic.sh
. lib/setup_test_core.sh
. lib/setup_test_tools.sh
. lib/setup_hugepage_migration_test.sh

grep "numa=fake=" /proc/cmdline > /dev/null
[ $? -ne 0 ] && echo "no numa node" >&2 && exit 1

do_test 'migratepages'  "numactl --membind 0 ${TESTALLOC} -m shared   -p ${PIPE} -h ${HPSIZE} -N" migratepages_controller check_none

do_test 'mbind migration'  "numactl --membind 0 ${TESTMBIND} -m shared  -p ${PIPE} -h ${HPSIZE} -N" mbind_migration_controller check_none

do_test 'move_pages migration'  "numactl --membind 0 ${TESTMOVEPAGES} -m shared  -p ${PIPE} -h ${HPSIZE} -N" move_pages_controller check_none

do_test 'memory hotremove migration'  "${TESTHOTREMOVE} -m shared  -p ${PIPE} -h ${HPSIZE} -N" memory_hotremove_controller check_none
