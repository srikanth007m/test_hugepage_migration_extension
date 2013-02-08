exp_sendsignal() { echo "system \"kill -s 10 [exp_pid]\""; }
exp_pagetypes()  {
    local file=$1
    shift 1
    echo "system \"${PAGETYPES} -p [exp_pid] -r $@ > $file\""
}
exp_numa_maps()  {
    local file=$1
    echo "system \"cat /proc/[exp_pid]/numa_maps > $file\""
}
exp_mceinject()  { echo "system \"${MCEINJECT} -P [exp_pid] -v ${BASEVFN} $@\""; }
exp_getmeminfo() { echo "system \"cat /proc/meminfo > $1\""; }
exp_waitexit() {
    echo -n "expect \"Exit.\" { puts \"\"; } "
    echo "eof { catch wait result ; puts \"Exited abnormally.\"; exit [ lindex $result 1 ]; }"
    echo "interact"
}
exp_numamigrate() { echo "system \"migratepages [exp_pid] $1 $2\""; }

prepare_test() {
    echo "----- prepare_test -----"
    cat /proc/meminfo > ${TMPF}.meminfobefore
    dmesg > ${TMPF}.dmesgbefore
}

teardown_test() {
    echo "----- teardown_test -----"
    cat /proc/meminfo > ${TMPF}.meminfoafter2
    dmesg > ${TMPF}.dmesgafter
}

migratepages_test() {
    [ ! -e ${LDIR}/test1 ] && echo "${LDIR}/test1 not found." && exit 1
    cat <<EOF > ${TMPF}.exp
spawn numactl --membind 0 ${LDIR}/test1 $1

expect "Waiting signal." {
    `exp_pagetypes ${TMPF}.pagetype1 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps1`
    `exp_getmeminfo ${TMPF}.meminfoafter1`
    `exp_sendsignal`
    sleep 1
    `exp_numamigrate 0 1`
    `exp_pagetypes ${TMPF}.pagetype2 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps2`
    sleep 1
    `exp_sendsignal`
}

`exp_waitexit`
EOF
    expect ${TMPF}.exp
}

mbind_migration_test() {
    [ ! -e ${LDIR}/test2 ] && echo "${LDIR}/test2 not found." && exit 1
    cat <<EOF > ${TMPF}.exp
spawn numactl --membind 0 ${LDIR}/test2 -h -m $1

expect "Waiting signal." {
    `exp_pagetypes ${TMPF}.pagetype1 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps1`
    `exp_getmeminfo ${TMPF}.meminfoafter1`
    `exp_sendsignal`
    sleep 1
    `exp_pagetypes ${TMPF}.pagetype2 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps2`
    sleep 1
    `exp_sendsignal`
}

`exp_waitexit`
EOF
    expect ${TMPF}.exp
}

move_pages_test() {
    [ ! -e ${LDIR}/test_move_pages ] && echo "${LDIR}/test_move_pages not found." && exit 1
    cat <<EOF > ${TMPF}.exp
spawn numactl --membind 0 ${LDIR}/test_move_pages -h -m $1

expect "Waiting signal." {
    `exp_pagetypes ${TMPF}.pagetype1 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps1`
    `exp_getmeminfo ${TMPF}.meminfoafter1`
    `exp_sendsignal`
    sleep 1
    `exp_pagetypes ${TMPF}.pagetype2 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps2`
    sleep 1
    `exp_sendsignal`
}

`exp_waitexit`
EOF
    expect ${TMPF}.exp
}

exp_memory_offline() { echo "system \"bash ${LDIR}/get_memblock_hugepage.sh ${PAGETYPES} [exp_pid] > ${TMPF}.offlinecheck\""; }
memory_offline_test() {

    [ ! -e ${LDIR}/test_memory_offline ] && echo "${LDIR}/test_memory_offline not found." && exit 1
    cat <<EOF > ${TMPF}.exp
spawn ${LDIR}/test_memory_offline -h -m $1

expect "Waiting signal." {
    `exp_pagetypes ${TMPF}.pagetype1 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps1`
    `exp_getmeminfo ${TMPF}.meminfoafter1`
    `exp_sendsignal`
    sleep 1
    `exp_memory_offline`
    `exp_pagetypes ${TMPF}.pagetype2 -Nl -b huge`
    `exp_numa_maps ${TMPF}.numa_maps2`
    sleep 1
    `exp_sendsignal`
}

`exp_waitexit`
EOF
    expect ${TMPF}.exp
}

_do_test() {
    echo "######## TEST ${FUNCNAME} / $@  ########"
    prepare_test
    $@
    teardown_test
    check_dmesg
    check_numa_maps
    echo "--- cat ${TMPF}.pagetype1"
    cat ${TMPF}.pagetype1
    echo "--- cat ${TMPF}.pagetype2"
    cat ${TMPF}.pagetype2
    echo "--- grep "HugePage" ${TMPF}.meminfobefore"
    grep "HugePage" ${TMPF}.meminfobefore
    echo "--- grep "HugePage" ${TMPF}.meminfoafter1"
    grep "HugePage" ${TMPF}.meminfoafter1
    echo "--- grep "HugePage" ${TMPF}.meminfoafter2"
    grep "HugePage" ${TMPF}.meminfoafter2
}

_do_test_offline() {
    echo "######## TEST ${FUNCNAME} / $@  ########"
    prepare_test
    $@
    teardown_test
    check_dmesg
    check_offlined
    echo "--- cat ${TMPF}.pagetype1"
    cat ${TMPF}.pagetype1
    echo "--- cat ${TMPF}.pagetype2"
    cat ${TMPF}.pagetype2
}

do_test() {
    if [ "$1" = "memory_offline_test" ] ; then
        _do_test_offline $@ >> $OUTFILE
    else
        _do_test $@ >> $OUTFILE
    fi
}

check_numa_maps() {
    echo "####### numa_maps diff on hugepage #######"
    diff -u ${TMPF}.numa_maps1 ${TMPF}.numa_maps2 > ${TMPF}.numa_mapsdiff
    grep " huge " ${TMPF}.numa_mapsdiff
    echo "##########################"
    count_testcount
    grep "^\+7000" ${TMPF}.numa_mapsdiff > /dev/null
    if [ $? -eq 0 ] ; then
        count_success
        echo "PASS: hugepage is migrated."
    else
        count_failure
        echo "FAIL: hugepage migration didn't happend."
    fi
}

check_dmesg() {
    echo "####### dmesg diff #######"
    diff ${TMPF}.dmesgbefore ${TMPF}.dmesgafter | grep -v '^< ' | \
        tee ${TMPF}.dmesgdiff
    echo "##########################"
    count_testcount
    grep -i -e "bug" -e "warning" ${TMPF}.dmesgdiff > /dev/null
    if [ $? -eq 0 ] ; then
        count_failure
        echo "FAIL: some bug/warning in kernel message."
    else
        count_success
        echo "PASS: no bug/warning in kernel message."
    fi
}

check_offlined() {
    count_testcount
    grep offline ${TMPF}.offlinecheck > /dev/null
    if [ $? -eq 0 ] ; then
        count_success
        echo "PASS: offlined."
    else
        count_failure
        echo "FAIL: `cat ${TMPF}.offlinecheck`."
    fi
}
