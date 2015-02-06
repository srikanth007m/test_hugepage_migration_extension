#!/bin/bash

# requires numactl package

NUMNODE=$(numactl -H | grep available | cut -f2 -d' ')
[ "$NUMNODE" -eq 1 ] && echo "no numa node" >&2 && exit 1

check_and_define_tp test_alloc_thp
check_and_define_tp test_mlock_on_shared_thp
check_and_define_tp test_mprotect_on_shared_thp
check_and_define_tp numa_maps

get_numa_maps() { cat /proc/$1/numa_maps; }

kill_test_programs() {
    pkill -9 -f $TESTALLOCTHP
    return 0
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
            $numa_maps $pid
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            # most of the memory mapped on the process (except thps) is
            # on node 1, which should trigger numa balancin migration.
            $numa_maps $pid
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            # get_numa_maps ${pid}
            $PAGETYPES -p $pid -Nl -a 0x700000000+$[NR_THPS * 512]
            # expecting numa balancing migration
            sleep 1
            $numa_maps $pid
            $PAGETYPES -p $pid -Nl -a 0x700000000+$[NR_THPS * 512]
            kill -SIGUSR1 $pid
            ;;
        "set mempolicy to default")
            $numa_maps $pid
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

control_mlock_on_shared_thp() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before fork")
            echo "pid: $pid" | tee -a ${OFILE}
            $PAGETYPES -p $pid -Nl -a 0x700000000+$[NR_THPS * 512] \
                | sed 's/^/  /' | tee -a ${OFILE}
            kill -SIGUSR1 $pid
            ;;
        "check shared thp")
            for ppid in $(pgrep -f $TESTMLOCKONSHAREDTHP) ; do
                echo "pid: $ppid ---" | tee -a ${OFILE}
                $PAGETYPES -p $ppid -Nl -a 0x700000000+$[NR_THPS * 512] \
                    | sed 's/^/  /' | tee -a ${OFILE}
            done
            for ppid in $(pgrep -f $TESTMLOCKONSHAREDTHP) ; do
                kill -SIGUSR1 $ppid
            done
            ;;
        "exited busy loop")
            for ppid in $(pgrep -f $TESTMLOCKONSHAREDTHP) ; do
                echo "pid: $ppid ---" | tee -a ${OFILE}
                $PAGETYPES -p $ppid -Nl -a 0x700000000+$[NR_THPS * 512] \
                    | sed 's/^/  /' | tee -a ${OFILE}
            done
            for ppid in $(pgrep -f $TESTMLOCKONSHAREDTHP) ; do
                kill -SIGUSR1 $ppid
            done
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_mlock_on_shared_thp() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

prepare_mlock_on_shared_thp() {
    sysctl vm.nr_hugepages=0
    prepare_test
}

cleanup_mlock_on_shared_thp() {
    cleanup_test
}

get_vma_protection() {
    local pid=$1
    grep -A 2 700000000000 /proc/$pid/maps
}

CHECKED=

control_mprotect_on_shared_thp() {
    local pid="$1"
    local line="$2"

    echo "$line" | tee -a ${OFILE}
    case "$line" in
        "before fork")
            echo "pid: $pid" | tee -a ${OFILE}
            $PAGETYPES -p $pid -Nl -a 0x700000000+$[NR_THPS * 512] \
                | sed 's/^/  /' | tee -a ${OFILE}
            get_vma_protection $pid
            kill -SIGUSR1 $pid
            ;;
        "just before mprotect")
            if [ "$CHECKED" != true ] ; then
                sleep 0.1
                CHECKED=true
                for ppid in $(pgrep -f $TESTMPROTECTONSHAREDTHP) ; do
                    echo "pid: $ppid ---" | tee -a ${OFILE}
                    $PAGETYPES -p $ppid -Nl -a 0x700000000+$[NR_THPS * 512] \
                        | sed 's/^/  /' | tee -a ${OFILE}
                    get_vma_protection $ppid
                done
                kill -SIGUSR1 $pid
            fi
            ;;
        "mprotect done")
            sleep 0.1
            for ppid in $(pgrep -f $TESTMPROTECTONSHAREDTHP) ; do
                echo "pid: $ppid ---" | tee -a ${OFILE}
                $PAGETYPES -p $ppid -Nl -a 0x700000000+$[NR_THPS * 512] \
                    | sed 's/^/  /' | tee -a ${OFILE}
                get_vma_protection $ppid
            done
            for ppid in $(pgrep -f $TESTMPROTECTONSHAREDTHP) ; do
                if [ "$ppid" = "$pid" ] ; then
                    kill -SIGUSR1 $ppid
                else
                    kill -9 $ppid
                fi
            done
            set_return_code EXIT
            return 0
            ;;
        *)
            ;;
    esac
    return 1
}

check_mprotect_on_shared_thp() {
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

prepare_mprotect_on_shared_thp() {
    sysctl vm.nr_hugepages=0
    prepare_test
}

cleanup_mprotect_on_shared_thp() {
    cleanup_test
}
