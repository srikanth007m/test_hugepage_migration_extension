#!/bin/bash

# requires numactl package

NUMNODE=$(numactl -H | grep available | cut -f2 -d' ')
[ "$NUMNODE" -eq 1 ] && echo "no numa node" >&2 && exit 1

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

MEMTOTAL=$(grep MemTotal: /proc/meminfo | awk '{print $2}')
HPNUM=$[MEMTOTAL/HPSIZE/2]

TESTALLOC="`dirname $BASH_SOURCE`/test_alloc"
[ ! -x "$TESTALLOC" ] && echo "test_alloc not found." >&2 && exit 1
TESTMBIND="`dirname $BASH_SOURCE`/test_mbind"
[ ! -x "$TESTMBIND" ] && echo "test_mbind not found." >&2 && exit 1
TESTMOVEPAGES="`dirname $BASH_SOURCE`/test_move_pages"
[ ! -x "$TESTMOVEPAGES" ] && echo "test_move_pages not found." >&2 && exit 1
TESTHOTREMOVE="`dirname $BASH_SOURCE`/hugepage_for_hotremove"
[ ! -x "$TESTHOTREMOVE" ] && echo "hugepage_for_hotremove not found." >&2 && exit 1
HOGHUGEPAGES="`dirname $BASH_SOURCE`/hog_hugepages"
[ ! -x "$HOGHUGEPAGES" ] && echo "hoge_hugepages not found." >&2 && exit 1
MADVISE_ALL="`dirname $BASH_SOURCE`/madvise_all_hugepages"
[ ! -x "$MADVISE_ALL" ] && echo "madvise_all_hugepages not found." >&2 && exit 1

sysctl vm.nr_hugepages=$HPNUM
NRHUGEPAGE=`cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages`
if [ "${NRHUGEPAGE}" -ne $HPNUM ] ; then
    echo "Set vm.nr_hugepages=100, but current size is $NRHUGEPAGE," >&2
    echo "it could make later tests fail." >&2
fi

# reserve (total - 2) hugepages
reserve_most_hugepages() {
    local hp_total=$(cat /sys/kernel/mm/hugepages/hugepages-${HPSIZE}kB/nr_hugepages)
    eval ${HOGHUGEPAGES} -r -m private -n $[hp_total-2] &
}

allocate_most_hugepages() {
    local hp_total=$(cat /sys/kernel/mm/hugepages/hugepages-${HPSIZE}kB/nr_hugepages)
    eval ${HOGHUGEPAGES} -m private -n $[hp_total-2] &
}

stop_hog_hugepages() {
    pkill -SIGUSR1 -f hog_hugepages
}

get_pagetypes() { ${PAGETYPES} $@; }
get_numa_maps() { cat /proc/$1/numa_maps; }
do_migratepages() {
    if [ $# -ne 3 ] ; then
        migratepages $1 0 1;
    else
        migratepages "$1" "$2" "$3";
    fi
}
do_memory_hotremove() { bash memory_hotremove.sh ${PAGETYPES} $1; }
show_offline_memblocks() {
    local block=""
    local memblocks="$(find /sys/devices/system/memory/ -type d -maxdepth 1 | grep "memory/memory" | sed 's/.*memory//')"
    for mb in $memblocks ; do
        if [ "$(cat /sys/devices/system/memory/memory${mb}/state)" == "offline" ] ; then
            block="$block $mb"
        fi
    done
    echo "offlined memory blocks: $block"
    if [ "$1" == "online" ] ; then
        for mb in $block ; do
            echo "Re-online memory block $mb"
            echo online > /sys/devices/system/memory/memory${mb}/state
        done
    fi
}

kill_test_programs() {
    pkill -9 -f $TESTALLOC
    pkill -9 -f $TESTMBIND
    pkill -9 -f $TESTMOVEPAGES
    pkill -9 -f $TESTHOTREMOVE
}

prepare_test() {
    kill_test_programs
    get_kernel_message_before
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
    kill_test_programs
}

control_migratepages() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
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
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
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

control_move_pages() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before move_pages")
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
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

control_memory_hotremove_migration() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before memory_hotremove"* )
            echo $line | sed "s/before memory_hotremove: *//" > ${TMPF}.preferred_memblk
            echo "preferred memory block: $targetmemblk" | tee -a ${OFILE}
            get_pagetypes -p ${pid}
            get_pagetypes -rNl -p ${pid} -b huge,compound_head=huge,compound_head > ${TMPF}.pagetypes1
            get_numa_maps ${pid} > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            echo "do memory hotplug ($(cat ${TMPF}.preferred_memblk))"
            # do_memory_hotremove ${pid} > ${TMPF}.hotremove
            grep HugeP /proc/meminfo
            cat /sys/devices/system/node/node*/hugepages/hugepages-2048kB/free_hugepages
            echo "echo offline > /sys/devices/system/memory/memory$(cat ${TMPF}.preferred_memblk)/state"
            echo offline > /sys/devices/system/memory/memory$(cat ${TMPF}.preferred_memblk)/state
            if [ $? -ne 0 ] ; then
                set_return_code MEMHOTREMOVE_FAILED
                echo "do_memory_hotremove failed."
            fi
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            get_pagetypes -p ${pid}
            get_pagetypes -rNl -p ${pid} -b huge,compound_head=huge,compound_head > ${TMPF}.pagetypes2
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

prepare_memory_hotremove_migration() {
    prepare_test
    sysctl vm.nr_hugepages=0
    sysctl vm.nr_hugepages=$HPNUM
}

cleanup_memory_hotremove_migration() {
    show_offline_memblocks online
    cleanup_test
}

prepare_test_reserve_hugepages() {
    reserve_most_hugepages
    prepare_test
}

prepare_test_allocate_hugepages() {
    allocate_most_hugepages
    prepare_test
}

cleanup_test_hog_hugepages() {
    cleanup_test
    stop_hog_hugepages
}

control_race_move_pages_and_map_fault_unmap() {
    for i in $(seq 5) ; do
        ./hugepage 10 &
        local pidhuge=$!
        ./movepages 10 $pidhuge &
        local pidmove=$!
        sleep 7
        kill -SIGUSR1 $pidhuge $pidmove 2> /dev/null
    done
    set_return_code EXIT
}

prepare_race_move_pages_and_map_fault_unmap() {
    prepare_test
}

cleanup_race_move_pages_and_map_fault_unmap() {
    pkill -9 hugepage
    pkill -9 movepages
    cleanup_test
}

check_race_move_pages_and_map_fault_unmap() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

control_race_migratepages_and_map_fault_unmap() {
    for i in $(seq 5) ; do
        ./hugepage 10 &
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

prepare_test_reserve_hugepages_overcommit() {
    sysctl -q vm.nr_overcommit_hugepages=$[HPNUM + 10]
    reserve_most_hugepages
    prepare_test
}

prepare_test_allocate_hugepages_overcommit() {
    sysctl -q vm.nr_overcommit_hugepages=$[HPNUM + 10]
    allocate_most_hugepages
    prepare_test
}

cleanup_test_hog_hugepages_overcommit() {
    cleanup_test
    stop_hog_hugepages
    sysctl -q vm.nr_overcommit_hugepages=0
}

BG_MIGRATION_PID=
control_race_gup_and_migration() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
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
        migratepages $tp_pid 0 1 2> /dev/null
        get_numa_maps $tp_pid    2> /dev/null | grep " huge "
        migratepages $tp_pid 1 0 2> /dev/null
        get_numa_maps $tp_pid    2> /dev/null | grep " huge "
    done
}

prepare_race_gup_and_migration() {
    sysctl vm.nr_hugepages=0
    sysctl vm.nr_hugepages=$HPNUM
    prepare_test
}

cleanup_race_gup_and_migration() {
    $PAGETYPES -b hwpoison,huge,compound_head=hwpoison,huge,compound_head -x -N
    kill -9 $BG_MIGRATION_PID
    cleanup_test
}

check_race_gup_and_migration() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}
