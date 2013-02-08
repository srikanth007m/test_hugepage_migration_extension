#!/bin/bash

SDIR=`dirname $BASH_SOURCE`
VM=""
VMIP=""
PASSWD=""
flagtype=""
pid=""
vfn=""
errortype=""
tailinj=false
double=false
while getopts "T:d:p:a:b:P:v:e:tD" opt ; do
    case $opt in
        T) TSTAMP=$OPTARG ;;
        d) VM=$OPTARG ;;
        p) PASSWD=$OPTARG ;;
        a) VMIP=$OPTARG ;;
        b) flagtype=$OPTARG ;;
        P) pid=$OPTARG ;;
        v) vfn=$OPTARG ;;
        e) errortype=$OPTARG ;;
        t) tailinj=true ;;
        D) double=true ;;
        *) usage ;;
    esac
done

inject_error() {
    local injtype=$1
    local hpa=$2
    local tmpf=`mktemp`

    if [ "$injtype" = "hard-offline" ] ; then
        echo "Hard offlining host pfn $hpa"
        echo ${hpa}000 > /sys/devices/system/memory/hard_offline_page
    elif [ "$injtype" = "soft-offline" ] ; then
        echo "Soft offlining host pfn $hpa"
        echo ${hpa}000 > /sys/devices/system/memory/soft_offline_page
    elif [ "$injtype" = "mce-srao" ] ; then
        echo "Injecting MCE on host pfn $hpa"
        cat <<EOF > ${tmpf}.mce-inject
CPU `cat /proc/self/stat | cut -d' ' -f39` BANK 2
STATUS UNCORRECTED SRAO 0x17a
MCGSTATUS RIPV MCIP
ADDR ${hpa}000
MISC 0x8c
RIP 0x73:0x1eadbabe
EOF
        mce-inject ${tmpf}.mce-inject
    elif [ "$injtype" = "mce-ce" ] ; then
        echo "Injecting Corrected Error on host pfn $hpa"
        cat <<EOF > ${tmpf}.mce-inject
CPU `cat /proc/self/stat | cut -d' ' -f39` BANK 2
STATUS CORRECTED 0xc0
ADDR ${hpa}000
EOF
        mce-inject ${tmpf}.mce-inject
    else
        echo "undefined injection type [$injtype]. Abort"
        return 1
    fi
    rm -rf ${tmpf:?DANGER}*
    return 0
}

if [ "$VM" ] ; then
    # NEED TESTING
    echo "inject to KVM guest"
    [ "$VMIP" -o ! "$passwd" -o ! "$flagtype" ] && echo "need args" && exit 1
    source $SDIR/generic_setup.sh
    source $SDIR/kvm_setup.sh
    run_guest_memeater
    get_gpa $flagtype
    [ ! "$TARGETGPA" ] && echo "Failed to get GPA. Test skipped." && exit 1
    TARGETHPA=`ruby $SDIR/gpa2hpa.rb $VM $TARGETGPA`
    [ ! "$TARGETHPA" ] && echo "Failed to get HPA. Test skipped." && exit 1
    echo "GVA:$TARGETGVA - GPA:$TARGETGPA - HPA:$TARGETHPA"
    echo -n "HPA status: " ; $PAGETYPES -a $TARGETHPA -Nlr | grep -v offset
    echo -n "GPA status: " ; ssh $VMIP $GUESTPAGETYPES -a $TARGETGPA -Nlr | grep -v offset
    inject_error mce-srao $TARGETHPA 2>&1
elif [ "$pid" ] ; then
    # [ ! "$pid" ] && echo "-P <PID> should be given." && exit 1
    [ ! "$vfn" ] && echo "-v <VFN> should be given." && exit 1
    [[ ! "$errortype" =~ (mce-srao|hard-offline|soft-offline) ]] && \
        echo "-e <ERRORTYPE> should be given." && exit 1
    [ "${tailinj}" = "true" ] && vfn=$[vfn+1]
    echo "Injecting MCE to local process (pid:$pid) at vfn:$vfn"
    PAGETYPES=`dirname $BASH_SOURCE`/page-types
    TARGETHPA=0x`$PAGETYPES -p $pid -a $vfn -Nrl | grep -v offset | cut -f2`
    $PAGETYPES -p $pid -a $vfn -Nrl
    echo "inject_error $errortype $TARGETHPA 2>&1"
    inject_error $errortype $TARGETHPA 2>&1
    [ "$double" = true ] && inject_error $errortype $TARGETHPA 2>&1
else
    [ ! "$vfn" ] && echo "-v <VFN> should be given." && exit 1
    [[ ! "$errortype" =~ (mce-srao|hard-offline|soft-offline) ]] && \
        echo "-e <ERRORTYPE> should be given." && exit 1
    [ "${tailinj}" = "true" ] && vfn=$[vfn+1]
    echo "Injecting MCE to physical address pfn:$vfn"
    PAGETYPES=`dirname $BASH_SOURCE`/page-types
    $PAGETYPES -a $vfn -Nrl
    echo "inject_error $errortype $vfn 2>&1"
    inject_error $errortype $vfn 2>&1
    [ "$double" = true ] && inject_error $errortype $vfn 2>&1
fi
