#!/bin/bash

PAGETYPES=$1
pid=$2
blocksz=0x`cat /sys/devices/system/memory/block_size_bytes`
[ "$blocksz" = "0x" ] && echo "/sys/devices/system/memory/block_size_bytes not found." && exit 1
blockszshift=`ruby -e "p Math.log(${blocksz},2).to_i"`
pfn=`${PAGETYPES} -p $pid -b huge,compound_head=huge,compound_head -Nl | cut -f2 | sed -n -e '2p'`
block=`ruby -e "p 0x${pfn} >> (${blockszshift} - 12)"`
[ ! "$block" ] && echo "memory block not found." >&2 && exit 1
echo offline > /sys/devices/system/memory/memory${block}/state
ret=$?
echo "block ${block} is `cat /sys/devices/system/memory/memory${block}/state`"
exit $ret
