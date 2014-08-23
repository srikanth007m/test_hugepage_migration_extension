#!/bin/bash

. test_core/lib/setup_thp_base.sh

# requires numactl package

NUMNODE=$(numactl -H | grep available | cut -f2 -d' ')
[ "$NUMNODE" -eq 1 ] && echo "no numa node" >&2 && exit 1

TESTALLOCTHP="`dirname $BASH_SOURCE`/test_alloc_thp"
[ ! -x "$TESTALLOC" ] && echo "test_alloc_thp not found." >&2 && exit 1

NUMA_MAPS_RB="`dirname $BASH_SOURCE`/numa_maps.rb"
[ ! -x "$NUMA_MAPS_RB" ] && echo "numa_maps.rb not found." >&2 && exit 1

PAGETYPES=${KERNEL_SRC}/tools/vm/page-types
if [ ! -x "$PAGETYPES" ] ; then
    make -C ${KERNEL_SRC}/tools vm
    if [ $? -ne 0 ] ; then
        echo "page-types not found." >&2
        exit 1
    fi
fi

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
    pkill -9 -f $TESTALLOCTHP
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

control_thp_migration_auto_numa() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before allocating thps")
            # collect all pages to node 1
            for node in $(seq $NUMNODE) ; do
                do_migratepages $pid $[node-1] 1
            done
            $NUMA_MAPS_RB $pid
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            # most of the memory mapped on the process (except thps) is
            # on node 1, which should trigger numa balancin migration.
            $NUMA_MAPS_RB $pid
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            # get_numa_maps ${pid}
            get_pagetypes -p $pid -Nl -a 0x700000000+$[NR_THPS * 512]
            # expecting numa balancing migration
            sleep 3
            $NUMA_MAPS_RB $pid
            get_pagetypes -p $pid -Nl -a 0x700000000+$[NR_THPS * 512]
            kill -SIGUSR1 $pid
            ;;
        "set mempolicy to default")
            $NUMA_MAPS_RB $pid
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

check_numa_maps() {
    count_testcount "CHECK /proc/pid/numa_maps"
    local map1=$(grep "^700000000000" ${TMPF}.numa_maps1 | sed -r 's/.* (N[0-9]*=[0-9]*).*/\1/g')
    local map2=$(grep "^700000000000" ${TMPF}.numa_maps2 | sed -r 's/.* (N[0-9]*=[0-9]*).*/\1/g')
    if [ "$map1" == "$map2" ] ; then
        count_failure "thp is not migrated."
        echo "map1=${map1}, map2=${map2}"
    else
        count_success "thp is migrated."
    fi
}

check_thp_migration_auto_numa() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
    check_numa_maps
}

INIT_NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)

prepare_thp_migration_auto_numa() {
    sysctl vm.nr_hugepages=0
    prepare_test

    default_tuning_parameters
    # numa balancing should be enabled
    echo 1 > /proc/sys/kernel/numa_balancing
    echo 1 > /proc/sys/kernel/numa_balancing_scan_delay_ms
    echo 100 > /proc/sys/kernel/numa_balancing_scan_period_max_ms
    echo 100 > /proc/sys/kernel/numa_balancing_scan_period_min_ms
    echo 1024 > /proc/sys/kernel/numa_balancing_scan_size_mb
}

cleanup_thp_migration_auto_numa() {
    echo $INIT_NUMA_BALANCING > /proc/sys/kernel/numa_balancing
    echo 1000 > /proc/sys/kernel/numa_balancing_scan_delay_ms
    echo 60000 > /proc/sys/kernel/numa_balancing_scan_period_max_ms
    echo 1000 > /proc/sys/kernel/numa_balancing_scan_period_min_ms
    echo 256 > /proc/sys/kernel/numa_balancing_scan_size_mb
    cleanup_test
}
