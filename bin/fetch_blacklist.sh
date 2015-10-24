#!/bin/bash
set -e -u -o pipefail

. ${BASH_SOURCE%/*}/common.sh

function write_blacklist() {
	local old_md5 new_md5
	old_md5=$(md5sum ${blacklistfile} | awk '{ print $1 }')
	log "[I] fetching new blacklist"
	wget -O ${blacklistfile}.new http://reestr.rublacklist.net/api/ips
	new_md5=$(md5sum ${blacklistfile}.new | awk '{ print $1 }')
	if [ "${old_md5}" != "${new_md5}" ]; then
		mv -f ${blacklistfile}.new ${blacklistfile}
		log "[I] new blacklist: \"%s\"" "$(ls -l ${blacklistfile})"
	else
		log "[I] the list has not changed"
		rm -f ${blacklistfile}.new
	fi
}

run_with_lock ${vardir}/fetch_blacklist.lck

write_blacklist
