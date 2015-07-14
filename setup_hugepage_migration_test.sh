#!/bin/bash

# requires numactl package

NUMNODE=$(numactl -H | grep available | cut -f2 -d' ')

HUGETLBDIR=`grep hugetlbfs /proc/mounts | head -n1 | cut -f2 -d' '`
if [ ! -d "${HUGETLBDIR}" ] ; then
    mount -t hugetlbfs none /dev/hugepages
    if [ $? -ne 0 ] ; then
        echo "hugetlbfs not mounted." >&2 && exit 1
    fi
fi

if [ "${HPSIZE}" -ne 1048576 -a "${HPSIZE}" -ne 2048 ] ; then
    echo "Unsupported hugepage size ${HPSIZE} kB" >&2
    exit 1
fi

check_and_define_tp test_alloc
check_and_define_tp test_mbind
check_and_define_tp test_move_pages
check_and_define_tp hugepage_for_hotremove
check_and_define_tp hog_hugepages
check_and_define_tp madvise_hwpoison_hugepages
check_and_define_tp iterate_hugepage_mmap_fault_munmap
check_and_define_tp iterate_numa_move_pages

# reserve (total - 2) hugepages
reserve_most_hugepages() {
    eval $hog_hugepages -r -m private -n $[HPNUM-2] &
}

allocate_most_hugepages() {
    eval $hog_hugepages -m private -n $[HPNUM-2] &
}

stop_hog_hugepages() {
    pkill -SIGUSR1 -f $hog_hugepages
}

get_numa_maps() { cat /proc/$1/numa_maps; }

do_migratepages() {
    if [ $# -ne 3 ] ; then
        migratepages $1 0 1;
    else
        migratepages "$1" "$2" "$3";
    fi
}

do_memory_hotremove() { bash memory_hotremove.sh ${PAGETYPES} $1; }

reonline_memblocks() {
    local block=""
    local memblocks="$(find /sys/devices/system/memory/ -type d -maxdepth 1 | grep "memory/memory" | sed 's/.*memory//')"
    for mb in $memblocks ; do
        if [ "$(cat /sys/devices/system/memory/memory${mb}/state)" == "offline" ] ; then
            block="$block $mb"
        fi
    done
    echo "offlined memory blocks: $block"
    for mb in $block ; do
        echo "Re-online memory block $mb"
        echo online > /sys/devices/system/memory/memory${mb}/state
    done
}

kill_test_programs() {
    pkill -9 -f $test_alloc
    pkill -9 -f $test_mbind
    pkill -9 -f $test_move_pages
    pkill -9 -f $hugepage_for_hotremove
    pkill -9 -f $hog_hugepages
    pkill -9 -f $madvise_all_hugepages
    pkill -9 -f $iterate_hugepage_mmap_fault_munmap
    pkill -9 -f $iterate_numa_move_pages
    pkill -9 -f "run_background_migration"
    return 0
}

prepare_HM_base() {
    if ! [ "$NUMNODE" -gt 1 ] ; then
        echo "No NUMA system" | tee -a ${OFILE}
        return 1
    fi
    kill_test_programs 2> /dev/null
    hugetlb_empty_check
    get_kernel_message_before
    set_and_check_hugetlb_pool $HPNUM
}

prepare_HM_reserve() {
    prepare_HM_base || return 1
    reserve_most_hugepages
}

prepare_HM_allocate() {
    prepare_HM_base || return 1
    allocate_most_hugepages
}

prepare_HM_reserve_overcommit() {
    prepare_HM_base || return 1
    sysctl -q vm.nr_overcommit_hugepages=$[HPNUM + 10]
    reserve_most_hugepages
}

prepare_HM_allocate_overcommit() {
    prepare_HM_base || return 1
    sysctl -q vm.nr_overcommit_hugepages=$[HPNUM + 10]
    allocate_most_hugepages
}

# memory hotremove could happen even on non numa system, so let's test it.
prepare_memory_hotremove() {
    if ! [ "$NUMNODE" -gt 1 ] ; then
        echo "No NUMA system" | tee -a ${OFILE}
        return 1
    fi
    PIPETIMEOUT=30
    kill_test_programs 2> /dev/null
    hugetlb_empty_check
    get_kernel_message_before
    set_and_check_hugetlb_pool $HPNUM_FOR_HOTREMOVE
}

cleanup_HM_base() {
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
    kill_test_programs 2> /dev/null
    sysctl vm.nr_hugepages=0
    hugetlb_empty_check
}

cleanup_HM_hog_hugepages() {
    stop_hog_hugepages
    cleanup_HM_base
}

cleanup_HM_hog_hugepages_overcommit() {
    stop_hog_hugepages
    sysctl -q vm.nr_overcommit_hugepages=0
    cleanup_HM_base
}

cleanup_memory_hotremove() {
    reonline_memblocks
    cleanup_HM_base
    PIPETIMEOUT=5
}

cleanup_race_gup_and_migration() {
    all_unpoison
    cleanup_HM_base
}

control_migratepages() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "just started")
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
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
            kill -SIGUSR1 $pid
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

control_mbind_migration() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before mbind")
            get_numa_maps ${pid} > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            get_numa_maps ${pid} > ${TMPF}.numa_maps2
            kill -SIGUSR1 $pid
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

control_move_pages() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before move_pages")
            get_numa_maps ${pid} > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            get_numa_maps ${pid} > ${TMPF}.numa_maps2
            kill -SIGUSR1 $pid
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

control_memory_hotremove() {
    local pid="$1"
    local line="$2"

    echo_log "$line"
    case "$line" in
        "before memory_hotremove"* )
            echo $line | sed "s/before memory_hotremove: *//" > ${TMPF}.preferred_memblk
            echo_log "preferred memory block: $targetmemblk"
            $PAGETYPES -rNl -p ${pid} -b huge,compound_head=huge,compound_head > ${TMPF}.pagetypes1
            get_numa_maps ${pid} | tee -a $OFILE > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            echo_log "do memory hotplug ($(cat ${TMPF}.preferred_memblk))"
            echo_log "echo offline > /sys/devices/system/memory/memory$(cat ${TMPF}.preferred_memblk)/state"
            echo offline > /sys/devices/system/memory/memory$(cat ${TMPF}.preferred_memblk)/state
            if [ $? -ne 0 ] ; then
                set_return_code MEMHOTREMOVE_FAILED
                echo_log "do_memory_hotremove failed."
            fi
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            $PAGETYPES -rNl -p ${pid} -b huge,compound_head=huge,compound_head > ${TMPF}.pagetypes2
            get_numa_maps ${pid} | tee -a $OFILE  > ${TMPF}.numa_maps2
            kill -SIGUSR1 $pid
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_hugepage_migration() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
    check_numa_maps
}

check_hugepage_migration_fail() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

check_memory_hotremove_migration() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
    check_pagetypes
}

check_numa_maps() {
    count_testcount "CHECK /proc/pid/numa_maps"
    local map1=$(grep " huge " ${TMPF}.numa_maps1 | sed -r 's/.* (N[0-9]*=[0-9]*).*/\1/g')
    local map2=$(grep " huge " ${TMPF}.numa_maps2 | sed -r 's/.* (N[0-9]*=[0-9]*).*/\1/g')
    if [ "$map1" == "$map2" ] ; then
        count_failure "hugepage is not migrated."
        echo "map1=${map1}, map2=${map2}"
    else
        count_success "hugepage is migrated."
    fi
}

check_pagetypes() {
    count_testcount "CHECK page-types output"
    diff -u ${TMPF}.pagetypes1 ${TMPF}.pagetypes2 > ${TMPF}.pagetypes3 2> /dev/null
    if [ -s ${TMPF}.pagetypes3 ] ; then
        count_success "hugepage is migrated."
    else
        count_failure "hugepage is not migrated."
    fi
}

control_race_move_pages_and_map_fault_unmap() {
    for i in $(seq 5) ; do
        $iterate_hugepage_mmap_fault_munmap 10 &
        local pidhuge=$!
        $iterate_numa_move_pages 10 $pidhuge &
        local pidmove=$!
        sleep 7
        kill -SIGUSR1 $pidhuge $pidmove 2> /dev/null
    done
    set_return_code EXIT
}

check_race_move_pages_and_map_fault_unmap() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

control_race_migratepages_and_map_fault_unmap() {
    for i in $(seq 5) ; do
        $iterate_hugepage_mmap_fault_munmap 10 &
        local pid=$!
        for j in $(seq 100) ; do
            do_migratepages ${pid} 0 1
            do_migratepages ${pid} 1 0
        done
        kill -SIGUSR1 $pid 2> /dev/null
    done
    set_return_code EXIT
}

check_race_migratepages_and_map_fault_unmap() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

BG_MIGRATION_PID=
control_race_gup_and_migration() {
    local pid="$1"
    local line="$2"

    echo_log "$line"
    case "$line" in
        "need unpoison")
            $PAGETYPES -b hwpoison,huge,compound_head=hwpoison,huge,compound_head -x -N
            kill -SIGUSR2 $pid
            ;;
        "start background migration")
            run_background_migration $pid &
            BG_MIGRATION_PID=$!
            kill -SIGUSR2 $pid
            ;;
        "exit")
            kill -SIGUSR1 $pid
            kill -SIGKILL "$BG_MIGRATION_PID"
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

run_background_migration() {
    local tp_pid=$1
    while true ; do
        echo migratepages $tp_pid 0 1 >> $TMPF.run_background_migration
        migratepages $tp_pid 0 1 2> /dev/null
        get_numa_maps $tp_pid    2> /dev/null | grep " huge " >> $TMPF.run_background_migration
        grep HugeP /proc/meminfo >> $TMPF.run_background_migration
        echo migratepages $tp_pid 1 0 >> $TMPF.run_background_migration
        migratepages $tp_pid 1 0 2> /dev/null
        get_numa_maps $tp_pid    2> /dev/null | grep " huge " >> $TMPF.run_background_migration
        grep HugeP /proc/meminfo >> $TMPF.run_background_migration
    done
}

check_race_gup_and_migration() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
    # cat $TMPF.run_background_migration
}
