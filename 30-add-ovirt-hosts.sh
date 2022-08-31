#!/bin/bash
#
#
. common_funcs

[[ "$ENGINE" ]] || die "No engine"

echo "Setup default cluster"
echo "Add hosts"
for i in $HOSTS; do
    exists=$(curl_api "/hosts?search=name=$i" | grep host\ href | wc -l)
    [[ "$exists" -eq 0 ]] && {
        echo "Adding $i"
        curl_api /hosts -d "<host><name>$i</name><address>$i</address><ssh><authentication_method>publickey</authentication_method></ssh></host>"
    }
done

echo "Add logical networks"
dc_id=$(curl_api "/datacenters?search=name=Default" | sed -n "s/.*data_center href.*id=\"\(.*\)\">/\1/p")
cluster_id=$(curl_api "/clusters?search=name=Default" | sed -n "s/.*cluster href.*id=\"\(.*\)\">/\1/p")
for net in baremetal provisioning; do
    curl_api /networks -d "<network> <name>$net</name> <data_center id=\"$dc_id\"/> </network>"
    network_id=$(curl_api "/networks?search=name=$net" | sed -n "s/.*network href.*id=\"\(.*\)\">/\1/p")
    curl_api /clusters/$cluster_id/networks -d "<network id=\"$network_id\" />"
done

all=$(cat hosts | wc -l)
echo "Wait for $all hosts to be up"
up_num=0
while [[ "$up_num" -lt "$all" ]]; do
    sleep 60
    up_ids=$(curl_api "/hosts?search=status=up" | sed -n "s/.*host href.*id=\"\(.*\)\">/\1/p")
    up_num=$(command echo $up_ids | wc -w | tr -d " ")
    echo "${up_num}/${all} hosts up"
done

echo "Setup networks"
for i in $up_ids; do
    host_name=$(curl_api "/hosts?search=id=$i" | sed -n "s|.*<name>\(.*\)</name>|\1|p" | head -1)
    external_iface=$(grep ^${host_name} hosts | cut -d, -f2)
    baremetal_iface=$(grep ^${host_name} hosts | cut -d, -f3)
    provisioning_iface=$(grep ^${host_name} hosts | cut -d, -f4)
    sed "s/__EXTERNAL_IFACE__/$external_iface/; s/__BAREMETAL_IFACE__/$baremetal_iface/; s/__PROVISIONING_IFACE__/$provisioning_iface/" setupnetworks.template > setupnetworks
    curl_api /hosts/$i/setupnetworks -d "@setupnetworks"
done

echo "Add data SD"
sd_host_id=$(command echo $up_ids | cut -d" " -f1)
sd_host_name=$(curl_api "/hosts?search=id=$sd_host_id" | sed -n "s|.*<name>\(.*\)</name>|\1|p" | head -1)
curl_api /storagedomains -d "<storage_domain> <name>data</name> <type>data</type> <storage> <type>nfs</type> <address>$ENGINE</address> <path>/srv/data</path> </storage> <host> <name>$sd_host_name</name> </host> </storage_domain>"

echo "Wait for DC to be up"
dc_status=
while [[ "$dc_status" != "up" ]]; do
    sleep 10
    dc_status=$(curl_api "/datacenters?search=name=Default" | sed -n "s|.*<status>\(.*\)</status>|\1|p")
done
