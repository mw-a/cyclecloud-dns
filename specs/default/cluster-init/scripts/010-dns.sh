#!/bin/sh
set -e

SERVERS=$(jetpack config dns.servers "")
SEARCH_LIST=$(jetpack config dns.search_list "")

if [ -n "$SEARCH_LIST" -o -n "$SERVERS" ] ; then
	# restore SELinux context broken by cloud-init somehow
	restorecon /etc/sysconfig/network-scripts/ifcfg-*

	[ -z "$SERVERS " ] || \
		nmcli c m "System eth0" ipv4.ignore-auto-dns yes ipv4.dns "$SERVERS"

	[ -z "$SEARCH_LIST " ] || \
		nmcli c m "System eth0" ipv4.dns-search "$SEARCH_LIST"

	# prevent cloud-init from resetting the file on reboot
	chattr +i /etc/sysconfig/network-scripts/ifcfg-eth0
	nmcli c u "System eth0"
fi
