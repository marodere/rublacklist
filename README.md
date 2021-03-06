rublacklist
======

maintain routing table based on RKN registry
* * *
`fetch_blacklist.sh` is the script that simply fetches RKN registry from rublacklist.net. Run it at least once before trying to use the next script.
* * *
`route.sh` is the script that builds routing table based on list of ip addresses. It *should* be specified as the "route-up" openvpn parameter but also it can be executed alone (manually, by cron, etc) For the first time it *should* be executed from openvpn to parse nameservers and gateway from envinroment and store it for further use.
* * *
I use three routing tables: `vpn`, `vpn0` and `vpn1`. I use "ip rule add/del" to switch between `vpn{0,1}`. Table `vpn` always have a default route via vpn. To use the script as is you *should* define them like this:

    echo "1000    vpn" >> /etc/iproute2/rt_tables
    echo "1001    vpn0" >> /etc/iproute2/rt_tables
    echo "1002    vpn1" >> /etc/iproute2/rt_tables

* * *
`fetch_blacklist.sh` can work under any user that have an appropriate file permissions `route.sh` *should* be executed as root to perform `ip(8)` calls.
