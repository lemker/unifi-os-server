#!/bin/bash
# Resource tuning for UniFi OS Server.
#
# Everything here works through systemd drop-ins, environment files and the
# services' own config directories. No UniFi binaries or packaged files are
# modified, and every file is regenerated on each start, so turning an option
# off (or UOS_TUNING=false) restores the stock behaviour on the next restart.
#
#   UOS_TUNING                    master switch (default: false, opt in)
#   UOS_JVM_MAX_HEAP_MB           UniFi Network max Java heap. 0 = stock
#                                 (-XX:MaxRAMPercentage=70, i.e. 70% of host RAM)
#   UOS_JVM_RETURN_MEMORY         let the JVM hand unused heap and malloc memory
#                                 back to the OS when idle (G1 periodic GC + native
#                                 trim every 5 min, and shrink the heap to ~30% free)
#   UOS_JVM_EXTRA_OPTS            extra JVM flags appended to UniFi Network
#   UOS_DISABLE_UNUSED_MONGODB    turn the stand-alone mongodb.service into a no-op
#                                 (UniFi Network runs its own mongod on 27117)
#   UOS_RABBITMQ_SCHEDULERS       Erlang scheduler threads for RabbitMQ (0 = stock,
#                                 one per CPU)
#   UOS_JOURNAL_MAX_MB            cap for the in-RAM systemd journal (0 = stock)
#   UOS_MASK_HOUSEKEEPING_TIMERS  mask apt-daily/apt-daily-upgrade/e2scrub timers
#   UOS_MALLOC_ARENA_MAX          glibc malloc arenas for all services (0 = stock)

TUNING_DIR=/etc/uos-tuning
TUNING_TAG=90-uos-tuning
TUNING_STATE=/etc/uos-tuning-state

_is_true() { case "${1,,}" in true|1|yes|on) return 0;; *) return 1;; esac; }
_is_pos_int() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; }

_remove_uos_tuning() {
    rm -rf "$TUNING_DIR"
    rm -f /etc/systemd/system/*.service.d/$TUNING_TAG.conf \
          /etc/systemd/system.conf.d/$TUNING_TAG.conf \
          /etc/systemd/journald.conf.d/$TUNING_TAG.conf \
          /etc/rabbitmq/conf.d/$TUNING_TAG.conf
    for t in apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer; do
        [ "$(readlink /etc/systemd/system/$t 2>/dev/null)" = /dev/null ] && rm -f /etc/systemd/system/$t
    done
    # The mongodb.service no-op drop-in is removed above. v1.8.0-tuned.4 masked
    # the unit instead: undo that only if we made it
    if [ -f "$TUNING_STATE/mongodb-masked" ]; then
        [ "$(readlink /etc/systemd/system/mongodb.service 2>/dev/null)" = /dev/null ] && \
            rm -f /etc/systemd/system/mongodb.service
        rm -f "$TUNING_STATE/mongodb-masked"
    fi
    # Older versions disabled it instead of masking it
    if [ -f "$TUNING_STATE/mongodb-disabled" ]; then
        systemctl enable mongodb.service >/dev/null 2>&1 || true
        rm -f "$TUNING_STATE/mongodb-disabled"
    fi
}

_dropin() { # unit, content
    mkdir -p "/etc/systemd/system/$1.d"
    printf '%s\n' "$2" > "/etc/systemd/system/$1.d/$TUNING_TAG.conf"
}

apply_uos_tuning() {
    # Start clean so removed/changed options never leave stale config behind
    _remove_uos_tuning

    if ! _is_true "${UOS_TUNING:-false}"; then
        echo "Resource tuning disabled (UOS_TUNING=${UOS_TUNING})"
        return 0
    fi
    echo "Applying resource tuning..."
    mkdir -p "$TUNING_DIR"

    # --- UniFi Network JVM -------------------------------------------------
    local heap="${UOS_JVM_MAX_HEAP_MB:-0}" extra="${UOS_JVM_EXTRA_OPTS:-}"
    if _is_true "${UOS_JVM_RETURN_MEMORY:-false}"; then
        # Periodic GC + native trim every 5 min. G1 only shrinks the heap when more
        # than MaxHeapFreeRatio of it is free (stock 70%), so lower that too, or the
        # committed heap stays at its high-water mark.
        extra="-XX:G1PeriodicGCInterval=300000 -XX:TrimNativeHeapInterval=300000 -XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=30 $extra"
        extra="${extra% }"
    fi
    if _is_pos_int "$heap" || [ -n "$extra" ]; then
        # Start from the packaged options so required -D flags are kept
        local stock
        stock=$( set +u; . /etc/default/unifi >/dev/null 2>&1; echo "$UNIFI_JVM_OPTS" )
        local opts="$stock"
        if _is_pos_int "$heap"; then
            opts=$(echo "$opts" | sed -E 's/-XX:(Max|Min|Initial)RAMPercentage=[0-9.]+//g; s/-Xm[sx][0-9]+[kKmMgG]?//g')
            # A small initial heap, so the idle heap can shrink below it
            opts="$opts -Xms$(( heap < 128 ? heap : 128 ))M -Xmx${heap}M"
            echo "  UniFi Network max heap: ${heap}MB"
        fi
        if [ -n "$extra" ]; then
            # Only one GC may be selected: drop the stock one if the user picks another
            if echo "$extra" | grep -qE -- '-XX:\+Use[A-Za-z]+GC'; then
                opts=$(echo "$opts" | sed -E 's/-XX:\+Use[A-Za-z]+GC//g')
            fi
            opts="$opts $extra"
            echo "  UniFi Network extra JVM opts: $extra"
        fi
        opts=$(echo "$opts" | tr -s ' ' | sed 's/^ //; s/ $//')
        printf 'UNIFI_JVM_OPTS="%s"\n' "$opts" > "$TUNING_DIR/unifi.env"
        # A later EnvironmentFile= overrides /etc/default/unifi
        _dropin unifi.service "[Service]
EnvironmentFile=-$TUNING_DIR/unifi.env"
    fi

    # --- Stand-alone MongoDB ----------------------------------------------
    # UniFi Network starts its own mongod (port 27117, data in /var/lib/unifi/db)
    # when UNIFI_MONGODB_SERVICE_ENABLED=false, leaving mongodb.service (27017)
    # running with no clients. Disabling it isn't enough: UniFi Network runs
    # "sudo systemctl start mongodb" at startup anyway. Masking breaks UniFi
    # Network, which refuses to start unless one of its "systemctl start"
    # attempts succeeds, so turn the unit into a no-op instead. Only while the
    # stock config still uses the embedded mongod.
    if _is_true "${UOS_DISABLE_UNUSED_MONGODB:-true}"; then
        local svc_enabled
        svc_enabled=$( set +u; . /etc/default/unifi >/dev/null 2>&1
                       echo "${UNIFI_MONGODB_SERVICE_ENABLED:-$(grep -o 'UNIFI_MONGODB_SERVICE_ENABLED=[a-z]*' /lib/systemd/system/unifi.service | head -1 | cut -d= -f2)}" )
        if [ "$svc_enabled" = "false" ] && [ -e /lib/systemd/system/mongodb.service ]; then
            _dropin mongodb.service "[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=
ExecStart=/bin/true"
            echo "  Unused mongodb.service replaced with a no-op (UniFi Network uses its own mongod)"
        fi
    fi

    # --- RabbitMQ ----------------------------------------------------------
    local sched="${UOS_RABBITMQ_SCHEDULERS:-0}"
    if _is_pos_int "$sched"; then
        _dropin rabbitmq-server.service "[Service]
Environment=\"RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS=+S ${sched}:${sched} +SDcpu ${sched}:${sched} +SDio ${sched}\""
        echo "  RabbitMQ Erlang schedulers: $sched"
    fi

    # --- journald (journal lives in /run, i.e. RAM) -------------------------
    local jmax="${UOS_JOURNAL_MAX_MB:-0}"
    if _is_pos_int "$jmax"; then
        mkdir -p /etc/systemd/journald.conf.d
        printf '[Journal]\nRuntimeMaxUse=%sM\nSystemMaxUse=%sM\n' "$jmax" "$jmax" \
            > /etc/systemd/journald.conf.d/$TUNING_TAG.conf
        echo "  journald capped at ${jmax}MB"
    fi

    # --- Housekeeping timers that make no sense in a container --------------
    if _is_true "${UOS_MASK_HOUSEKEEPING_TIMERS:-true}"; then
        for t in apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer; do
            [ -e "/etc/systemd/system/$t" ] || ln -s /dev/null "/etc/systemd/system/$t"
        done
        echo "  apt-daily, apt-daily-upgrade and e2scrub timers masked"
    fi

    # --- glibc malloc arenas ------------------------------------------------
    local arenas="${UOS_MALLOC_ARENA_MAX:-0}"
    if _is_pos_int "$arenas"; then
        mkdir -p /etc/systemd/system.conf.d
        printf '[Manager]\nDefaultEnvironment=MALLOC_ARENA_MAX=%s\n' "$arenas" \
            > /etc/systemd/system.conf.d/$TUNING_TAG.conf
        echo "  MALLOC_ARENA_MAX=$arenas"
    fi


    echo "Resource tuning applied!"
}
