#!/bin/bash

if [[ "$0" =~ "$BASH_SOURCE" ]] ; then
    echo "$BASH_SOURCE should be included from another script, not directly called."
    exit 1
fi

PAGETYPES=`dirname $BASH_SOURCE`/page-types
GUESTPAGETYPES=/usr/local/bin/page-types
BASEVFN=0x700000000
