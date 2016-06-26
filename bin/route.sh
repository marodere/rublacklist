#!/bin/bash
set -e -u -o pipefail

. ${BASH_SOURCE%/*}/common.sh
logfile=${vardir}/log/route.log

function valid_ip() {
	local err=0 glob_err=0
	local ip ip_c

	for ip in $@; do
		err=0
		if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
			OIFS=$IFS
			IFS='.'
			ip_c=($ip)
			IFS=$OIFS
			[[ ${ip_c[0]} -le 255 && ${ip_c[1]} -le 255 \
				&& ${ip_c[2]} -le 255 && ${ip_c[3]} -le 255 ]] && \
				! [[ $ip =~ ^192\.168 ]] && \
				! [[ $ip =~ ^127\. ]] || err=$? 
		else
			err=1
		fi
		glob_err=$(( glob_err + err ))
		if [ ${err} -ne 0 ]; then
			log "[W] suspicious IP \"%s\"" "${ip}"
		fi
	done
	return ${glob_err}
}

function get_new_rt_table() {
	if /bin/ip rule sh | grep vpn0 >/dev/null; then
		printf "vpn1"
	else
		printf "vpn0"
	fi
}

function make_rt_table_active() {
	log "[I] activating rt_table \"%s\"" "${1}"
	(set -x; /bin/ip rule add lookup ${1})
	for current_table in $(/bin/ip rule sh | grep vpn | grep -v ${1} | awk '{ print $NF }' || true); do
		(set -x; /bin/ip rule del lookup ${current_table})
	done
}

function add_route() {
	local addr="$1"
	local gw="$2"
	if ! valid_ip "${addr}" "${gw}"; then
		log "[W] add_route failed"
		return 1
	fi
	/bin/ip route add ${addr} via ${gw} dev ${dev} table ${new_rt_table}
}

function store_gw() {
	log "[I] got fresh route_vpn_gateway=\"%s\" dev=\"%s\"" "${route_vpn_gateway}" "${dev}"
	if ! valid_ip "${route_vpn_gateway}"; then
		log "[E] suspicious route, bailing out"
		return 1
	fi
	printf "%s\n%s" "route_vpn_gateway=${route_vpn_gateway}" "dev=${dev}" > ${gwfile}
}

function get_gw() {
	cat ${gwfile}
}

function add_service_routes() {
	local i=1
	local net gw mask
	while : ; do
		eval "net=\${route_network_${i}:-}"
		eval "mask=\${route_netmask_${i}:-}"
		eval "gw=\${route_gateway_${i}:-}"
		[ -n "${net}" -a -n "${mask}" -a -n "${gw}" ] || break
		valid_ip "${net}" "${mask}" "${gw}"
		(set -x; /bin/route add -net ${net} netmask ${mask} gw ${gw} dev ${dev})
		(( ++i ))
	done
}

function add_nameservers() {
	local i=1
	local opt ns

	(
		printf "forwarders { "
		while : ; do
			eval "opt=\${foreign_option_${i}:-}"
			[ -n "${opt}" ] || break
			if [ "${opt}" != "${opt#dhcp-option DNS *}" ] ; then
				ns=${opt#dhcp-option DNS *}
				valid_ip "${ns}" || { log "[E] suspicious nameserver"; return 1; }
				(set -x; /bin/ip route add "${ns}" via "${route_vpn_gateway}" dev "${dev}")
				printf "%s; " "${ns}"
			fi
			(( ++i ))
		done
		printf "}\n"
	) > ${bind_ns_config}
}

function build_blacklist_routing_table() {
	flock -s -w 30 ${blacklistfile}.lck cat ${blacklistfile} | \
	awk -v 'FS=;' '{ print $NF }' | sed -e 's/,/\n/g' | sort -u | \
	(
		local counter=0
		local failed=0
		while read ip; do
			add_route "${ip}" "${route_vpn_gateway}" && (( ++counter)) || (( ++failed ))
		done
		log "[I] built %d routes (%d errors)" "${counter}" "${failed}"
	)
}

run_with_lock ${vardir}/route.lck

blacklist_mtime=$(stat --printf=%Y ${blacklistfile})

if [ -n "${route_vpn_gateway:-}" ]; then
	# probably running from openvpn
	store_gw
	add_service_routes
	add_nameservers
else
	# probably running from crontab
	read blacklist_processed_mtime < ${blacklistfile}.timestamp.processed || blacklist_processed_mtime=0
	if [ "${blacklist_mtime}" == "${blacklist_processed_mtime}" ]; then
		log "[I] the blacklist has not changed since %d, nothing to do" "${blacklist_processed_mtime}"
		exit 0
	fi
fi

new_rt_table=$(get_new_rt_table)
log "[I] deal with rt_table %s" "${new_rt_table}"

eval $(get_gw)
/bin/ip route flush table ${new_rt_table}
/bin/ip route add ${route_vpn_gateway} dev ${dev} table ${new_rt_table}
build_blacklist_routing_table
make_rt_table_active ${new_rt_table}

printf "%d\n" "${blacklist_mtime}" > ${blacklistfile}.timestamp.processed

log "[I] successfully processed, timestamp of the blacklist is %d" "${blacklist_mtime}"
