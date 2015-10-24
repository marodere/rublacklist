#!/bin/bash

export LC_ALL=C
export PATH="/bin:/usr/bin"

rootdir=/place/rublacklist
vardir=${rootdir}/var
gwfile=${vardir}/gw.txt
blacklistfile=${vardir}/blacklist.txt
logfile=${vardir}/log/route.log
update_flag=${vardir}/blacklist_updated

bind_ns_config="/etc/bind/named.conf.forwarders.vpn"

teelogcmd="cat"
if [ -t 0 ]; then
	teelogcmd="tee /dev/stderr"
fi

function log() {
	local d=$(date '+%Y-%m-%d %H:%M:%S %Z')
	(
		printf "%s > " "$d"
		printf "$@"
		printf "\n"
	) >&2
}

function run_with_lock() {
	local script_lockfile="$1"
	if [ -n "${SCRIPT_WRAPPED:-}" ]; then
		unset SCRIPT_WRAPPED
		log "[I] started"
	else
		SCRIPT_WRAPPED=da exec flock -x -n ${script_lockfile} "$0" "$@" 2>> ${logfile}
		# should never happen
		exit 1
	fi
}
