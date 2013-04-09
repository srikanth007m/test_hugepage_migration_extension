#!/bin/bash

get_console_output() {
    echo "####### DMESG #######"
    diff ${TMPF}.dmesgbeforeinject ${TMPF}.dmesgafterinject | grep -v '^< ' | \
        tee ${TMPF}.dmesgafterinjectdiff
    echo "####### DMESG END #######"
}

check_console_output() {
    [ "$1" = -v ] && local inverse=true && shift
    local word="$1"
    if [ "$word" ] ; then
        count_testcount
        grep "$word" ${TMPF}.dmesgafterinjectdiff > /dev/null 2>&1
        if [ $? -eq 0 ] ; then
            if [ "$inverse" ] ; then
                count_failure "host kernel message shows unexpected word '$word'."
            else
                count_success "host kernel message shows expected word '$word'."
            fi
        else
            if [ "$inverse" ] ; then
                count_success "host kernel message does not show unexpected word '$word'."
            else
                count_failure "host kernel message does not show expected word '$word'."
            fi
        fi
    fi
}

check_dmesg_no_warning() {
    count_testcount
    grep -e " BUG: " -e " WARNING: " ${TMPF}.dmesgafterinjectdiff > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        count_failure "Kernel 'BUG:'/'WARNING:' message"
    else
        count_success "No Kernel 'BUG:'/'WARNING:' message"
    fi
}

PIPE=${TMPF}.pipe
mkfifo ${PIPE} 2> /dev/null
[ ! -p ${PIPE} ] && echo "Fail to create pipe." >&2 && exit 1
chmod a+x ${PIPE}
PIPETIMEOUT=5

# do_test <test command> <test controller> <result checker>
do_test() {
    local title="$1"
    local cmd="$2"
    local controller="$3"
    local checker="$4"
    local line=
    local result=PASS

    echo "---test start ($title)---------------------------------------------------------" | tee /dev/kmsg
    echo "$FUNCNAME '$title' $cmd $controller $checker"

    prepare_test "$title"

    # Keep pipe open to hold the data on buffer after the writer program
    # is terminated.
    exec {fd}<>${PIPE}
    eval "( $cmd ) &"
    local pid=$!
    while true ; do
        if read -t${PIPETIMEOUT} line <> ${PIPE} ; then
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

    cleanup_test "$title"

    eval $checker "$result"
    echo "---test done ($title)------------------------------------------------"
}

# do_test_async <prepare> <cleanup> <test controller> <result checker>
do_test_async() {
    local title="$1"
    local controller="$2"
    local checker="$3"
    local result=PASS

    echo "---test start ($title)---------------------------------------------------------"
    echo "$FUNCNAME '$title' $controller $checker"

    prepare_test "$title"
    eval $controller
    cleanup_test "$title"
    eval $checker
    echo "---test done ($title)------------------------------------------------"
}
