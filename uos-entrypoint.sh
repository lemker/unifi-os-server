#!/bin/bash
if [ -f /usr/lib/libuos-mount-wrapper.so ]; then
    export LD_PRELOAD=/usr/lib/libuos-mount-wrapper.so
fi
exec /sbin/init
