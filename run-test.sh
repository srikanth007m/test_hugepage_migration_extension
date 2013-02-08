#!/bin/bash

. lib/generic_setup.sh
. lib/test_setup.sh

grep "numa=fake=" /proc/cmdline > /dev/null
[ $? -ne 0 ] && echo "no numa node" >&2 && exit 1

do_test migratepages_test shared
do_test migratepages_test private
do_test mbind_migration_test shared
do_test mbind_migration_test private
do_test move_pages_test shared
do_test move_pages_test private
do_test memory_offline_test shared
do_test memory_offline_test private
show_summary
exit 0
