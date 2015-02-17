#!/bin/bash

# requires numactl package

check_and_define_tp test_alloc

CGROUP_THIS_TEST=cpu,memory,hugetlb:test1

prepare_memcg_consistency() {
    prepare_HM_base || return 1

    cgdelete $CGROUP_THIS_TEST 2> /dev/null
    cgcreate -g $CGROUP_THIS_TEST || return 1
    echo 1 > $MEMCGDIR/test1/memory.move_charge_at_immigrate || return 1
}

cleanup_memcg_consistency() {
    cgdelete $CGROUP_THIS_TEST || return 1
    cleanup_HM_base || return 1
}

control_memcg_consistency() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "just started")
            cgclassify -g $CGROUP_THIS_TEST $pid
            cgget -g $CGROUP_THIS_TEST > $TMPF.memcg0
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            cgget -g $CGROUP_THIS_TEST > $TMPF.memcg1
            echo "do migratepages"
            do_migratepages ${pid}
            if [ $? -ne 0 ] ; then
                set_return_code MIGRATION_FAILED
                echo "do_migratepages failed."
            fi
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            get_numa_maps ${pid}   > ${TMPF}.numa_maps2
            cgget -g $CGROUP_THIS_TEST > $TMPF.memcg2
            kill -SIGUSR1 $pid
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_memcg_consistency() {
    check_system_default

    diff -u $TMPF.memcg0 $TMPF.memcg1
    diff -u $TMPF.memcg1 $TMPF.memcg2
}
