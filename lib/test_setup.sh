#!/bin/bash

pkill -f hog_hugepages

if [ "${HPSIZE}" -ne 1048576 -a "${HPSIZE}" -ne 2048 ] ; then
    echo "Unsupported hugepage size ${HPSIZE} kB" >&2
    exit 1
fi

MEMTOTAL=$(grep MemTotal: /proc/meminfo | awk '{print $2}')
HPNUM=$[MEMTOTAL/HPSIZE/2]

PIPE=${TMPF}.pipe
mkfifo ${PIPE} 2> /dev/null
[ ! -p ${PIPE} ] && echo "Fail to create pipe." >&2 && exit 1
chmod a+x ${PIPE}
ls -l ${PIPE}

# do_test <test command> <test controller> <result checker>
do_test() {
    local cmd="$1"
    local controller="$2"
    local checker="$3"
    local line=
    local result=PASS

    echo "------------------------------------------------------------"
    echo $FUNCNAME $@

    dmesg > ${TMPF}.dmesg1

    # Keep pipe open to hold the data on buffer after the writer program
    # is terminated.
    exec {fd}<>${PIPE}
    ( $cmd ) &
    local pid=$!
    while true ; do
        if read -t5 line <> ${PIPE} ; then
            echo $line
            $controller $pid "$line"
            if [ $? -eq 0 ] ; then
                break
            fi
        else
            echo "time out, abort test" >&2
            kill -SIGINT $pid
            result=TIMEOUT
            break
        fi
    done

    dmesg > ${TMPF}.dmesg2

    $checker $result
}

get_pagetypes() { ${PAGETYPES} $@; }
get_numa_maps() { cat /proc/$1/numa_maps; }
do_migratepages() { migratepages $1 0 1; }
do_memory_hotremove() { ${LDIR}/memory_hotremove.sh ${PAGETYPES} $1; }

# reserve (total - 2) hugepages
reserve_most_hugepages() {
    local hp_total=$(cat /sys/kernel/mm/hugepages/hugepages-${HPSIZE}kB/nr_hugepages)
    eval ${LDIR}/hog_hugepages -r -m private -n $[hp_total-2]
}

allocate_most_hugepages() {
    local hp_total=$(cat /sys/kernel/mm/hugepages/hugepages-${HPSIZE}kB/nr_hugepages)
    eval ${LDIR}/hog_hugepages -m private -n $[hp_total-2]
}

migratepages_controller() {
    local pid=$1
    local line=$2
    case "$line" in
        "entering busy loop")
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            do_migratepages ${pid}
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            get_numa_maps ${pid}   > ${TMPF}.numa_maps2
            kill -SIGUSR1 $pid
            return 0
            ;;
    esac
    return 1
}

mbind_migration_controller() {
    local pid=$1
    local line=$2
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
            return 0
            ;;
    esac
    return 1
}

move_pages_controller() {
    local pid=$1
    local line=$2
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
            return 0
            ;;
    esac
    return 1
}

memory_hotremove_controller() {
    local pid=$1
    local line=$2
    case "$line" in
        "before memory_hotremove")
            get_pagetypes -rNl -p ${pid} -b huge > ${TMPF}.pagetypes1
            get_numa_maps ${pid}   > ${TMPF}.numa_maps1
            kill -SIGUSR1 $pid
            ;;
        "entering busy loop")
            do_memory_hotremove ${pid} > ${TMPF}.hotremove
            kill -SIGUSR1 $pid
            ;;
        "exited busy loop")
            get_pagetypes -rNl -p ${pid} -b huge > ${TMPF}.pagetypes2
            get_numa_maps ${pid}   > ${TMPF}.numa_maps2
            kill -SIGUSR1 $pid
            return 0
            ;;
    esac
    return 1
}

migration_checker() {
    check_return_value "$1"
    check_numa_maps
}

memory_hotremove_checker() {
    check_return_value "$1"
    check_numa_maps
    check_pagetypes
    check_memory_hotremove
}

check_return_value() {
    count_testcount
    if [ "$1" = PASS ] ; then
        count_success "PASS"
    else
        count_failure "FAIL: $1"
    fi
}

check_numa_maps() {
    count_testcount "/proc/pid/numa_maps check"
    local map1=$(grep " huge " ${TMPF}.numa_maps1 | sed -r 's/.* (N[0-9]*=[0-9]*).*/\1/g')
    local map2=$(grep " huge " ${TMPF}.numa_maps2 | sed -r 's/.* (N[0-9]*=[0-9]*).*/\1/g')
    if [ "$map1" == "$map2" ] ; then
        count_failure "FAIL: hugepage is not migrated."
        echo "map1=${map1}, map2=${map2}"
    else
        count_success "PASS: hugepage is migrated."
    fi
}

check_pagetypes() {
    count_testcount "page-types check"
    diff -u ${TMPF}.pagetypes1 ${TMPF}.pagetypes2 > ${TMPF}.pagetypes3 2> /dev/null
    cat ${TMPF}.pagetypes3
    if [ -s ${TMPF}.pagetypes3 ] ; then
        count_success "PASS: hugepage is migrated."
    else
        count_failure "FAIL: hugepage is not migrated."
    fi
}

check_dmesg() {
    diff ${TMPF}.dmesg1 ${TMPF}.dmesg2 | grep -v '^< ' > ${TMPF}.dmesg3 2> /dev/null
    count_testcount "check dmesg"
    grep -i -e "bug" -e "warning" ${TMPF}.dmesg3 > /dev/null
    if [ $? -eq 0 ] ; then
        count_failure "FAIL: some bug/warning in kernel message."
    else
        count_success "PASS: no bug/warning in kernel message."
    fi
}

check_memory_hotremove() {
    count_testcount
    grep offline ${TMPF}.hotremove > /dev/null
    if [ $? -eq 0 ] ; then
        count_success "PASS: memory block was hotremoved."
    else
        count_failure "FAIL: `cat ${TMPF}.hotremove`."
    fi
}
