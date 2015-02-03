#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

check_and_define_tp hugepage_pingpong
TESTFILE=${WDIR}/testfile

kill_test_programs() {
    pkill -9 -f $hugepage_pingpong
}

prepare_test() {
    kill_test_programs
    hugetlb_empty_check
    get_kernel_message_before
    sysctl vm.nr_hugepages=$HPNUM
}

cleanup_test() {
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
    kill_test_programs
    ipcs -s -t | cut -f1 -d' ' | egrep '[0-9]' | xargs ipcrm sem > /dev/null 2>&1
    sysctl vm.nr_hugepages=0
    hugetlb_empty_check
}

check_test() {
    check_kernel_message -v "failed"
    check_kernel_message_nobug
    check_return_code "${EXPECTED_RETURN_CODE}"
}

control_hugepage_pingpong() {
    echo "start hugepage_pingpong" | tee -a ${OFILE}
    $hugepage_pingpong -n 10 -t 0xff > ${TMPF}.fuz.out 2>&1 &
    local pid=$!
    echo "pid $pid"
    sleep 10
    pkill -SIGUSR1 $pid
    set_return_code EXIT
}

control_hugepage_pingpong_race() {
    local nr_proc=$PINGPONG_NR_PROC
    local nr_hps=$PINGPONG_NR_HPS
    local type=$PINGPONG_ALLOC_TYPES
    local i=
    local pids=""
    echo "start $nr_proc hugepage_pingpong processes" | tee -a ${OFILE}
    for i in $(seq $nr_proc) ; do
        $hugepage_pingpong -n $nr_hps -t $type > ${TMPF}.fuz.out$i 2>&1 &
        pids="$pids $!"
    done
    sleep 10
    kill -SIGUSR1 $pids
    set_return_code EXIT
}

NUMA_MAPS_READER=${TMPF}.read_numa_maps.sh
cat <<EOF > ${NUMA_MAPS_READER}
for pid in \$@ true ; do
    cat /proc/\$pid/numa_maps > /dev/null 2>&1
done
EOF

control_hugepage_pingpong_race_with_numa_maps() {
    local nr_proc=$PINGPONG_NR_PROC
    local nr_hps=$PINGPONG_NR_HPS
    local type=$PINGPONG_ALLOC_TYPES
    [ ! "$nr_proc" ] && echo "you must give PINGPONG_NR_PROC= in recipe" && return 1
    [ ! "$nr_hps" ] && echo "you must give PINGPONG_NR_HPS= in recipe" && return 1
    [ ! "$type" ] && echo "you must give PINGPONG_ALLOC_TYPES= in recipe" && return 1
    local i=0
    local cmd="bash ${NUMA_MAPS_READER}"
    local pids=""
    local reader_pid=
    echo "start $nr_proc hugepage_pingpong processes" | tee -a ${OFILE}
    for i in $(seq $nr_proc) ; do
        $hugepage_pingpong -n $nr_hps -t $type > ${TMPF}.fuz.out$i 2>&1 &
        pids="$pids $!"
    done
    # eval "$cmd $pids" &
    # reader_pid=$!
    sleep 10
    # kill -SIGKILL $reader_pid
    kill -SIGUSR1 $pids
    set_return_code EXIT
}

prepare_hugepage_pingpong() {
    kill_test_programs
    ipcrm --all > /dev/null 2>&1
    rm -rf ${WDIR}/mount/* 2> /dev/null
    umount -f ${WDIR}/mount 2> /dev/null
    hugetlb_empty_check
    get_kernel_message_before
    sysctl vm.nr_hugepages=10 # $HPNUM
    mkdir -p ${WDIR}/mount
    mount -t hugetlbfs none ${WDIR}/mount
}

cleanup_hugepage_pingpong() {
    kill_test_programs
    ipcrm --all > /dev/null 2>&1
    echo "remove hugetlbfs files" | tee -a ${OFILE}
    rm -rf ${WDIR}/mount/*
    echo "umount hugetlbfs" | tee -a ${OFILE}
    umount -f ${WDIR}/mount
    sysctl vm.nr_hugepages=0
    sleep 1
    hugetlb_empty_check
    get_kernel_message_after
    get_kernel_message_diff | tee -a ${OFILE}
}

# inside cheker you must tee output in you own.
check_hugepage_pingpong() {
    check_test
    __check_hugepage_pingpong
}

__check_hugepage_pingpong() {
    echo "check done." | tee -a ${OFILE}
}
