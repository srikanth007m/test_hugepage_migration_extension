#!/bin/bash

TESTCOUNT=0
SUCCESS=0
FAILURE=0

count_testcount() { TESTCOUNT=$((TESTCOUNT+1)); [ $# -gt 0 ] && echo $@; }
count_success()   { SUCCESS=$((SUCCESS+1));     [ $# -gt 0 ] && echo $@; }
count_failure()   { FAILURE=$((FAILURE+1));     [ $# -gt 0 ] && echo $@; }
show_summary() {
    echo "$TESTNAME:" | tee -a $OUTFILE
    echo "$TESTCOUNT test(s) ran, $SUCCESS passed, $FAILURE failed." | tee -a $OUTFILE
}

WDIR=$PWD/work
[ ! -d "$WDIR" ] && mkdir -p $WDIR
TMPF=`mktemp --tmpdir=$WDIR`

LDIR=$PWD/lib
export PATH=${PATH}:${LDIR}
PAGETYPES=$LDIR/page-types
all_unpoison() { $PAGETYPES -b hwpoison,compound_tail=hwpoison -x -N; }
all_unpoison
MCEINJECT=$LDIR/mceinj.sh

BASEVFN=0x700000000

TESTNAME=`echo $0 | sed -e 's/.*run-\(.*\).sh/\1/'`
if [ ! "$TSTAMP" ] ; then
    # echo "timestamp not given ($TSTAMP)"
    TSTAMP=`date +%y%m%d_%H%M`
fi
OUTDIR=$PWD/results/$TSTAMP
[ ! -d "$OUTDIR" ] && mkdir -p $OUTDIR
OUTFILE=$OUTDIR/$TESTNAME
