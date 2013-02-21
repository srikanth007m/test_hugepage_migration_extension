#!/bin/bash

range=`cat /sys/devices/system/node/online`
nodes=
if [[ ! "$range" =~ - ]] ; then
    nodes=$range
else
    nodes=`seq $(echo ${range} | tr '-' ' ') | tr '\n' ' '`
fi
grep "^HugePage" /proc/meminfo
for node in $nodes ; do
    grep " Huge" /sys/devices/system/node/node${node}/meminfo
done
