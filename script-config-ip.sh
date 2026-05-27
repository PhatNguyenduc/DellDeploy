#!/bin/bash

TARGET=""

MAPPING_FILE="${TARGET}/opt/ip_mapping.csv"
DNS_SERVER="8.8.8.8"

if [ ! -f "$MAPPING_FILE" ]; then
    echo "Error: File $MAPPING_FILE not found!"
    exit 1
fi

SERIAL=$(dmidecode -s system-serial-number | tr -d ' \n')
if [ -z "$SERIAL" ] || [ "$SERIAL" == "NotSpecified" ]; then
    echo "Error: Unable to retrieve system serial number!"
    exit 1
fi
echo "Serial: $SERIAL"

MATCH_LINE=$(grep -i "^$SERIAL," "$MAPPING_FILE")

if [ -z "$MATCH_LINE" ]; then
    echo "Not found Serial $SERIAL in mapping file. Skipping static IP config."
    exit 0
fi

IP_ADDRESS=$(echo "$MATCH_LINE" | cut -d',' -f2 | tr -d ' \r\n')
HOSTNAME=$(echo "$MATCH_LINE" | cut -d',' -f3 | tr -d ' \r\n')

if [[ ! "$IP_ADDRESS" == */* ]]; then
    IP_ADDRESS="$IP_ADDRESS/24"
fi

IP_NO_CIDR="${IP_ADDRESS%/*}"
SUBNET=$(echo "$IP_NO_CIDR" | cut -d'.' -f1-3)
GATEWAY="${SUBNET}.1"

echo "Applying: Hostname=$HOSTNAME | IP=$IP_ADDRESS | Gateway=$GATEWAY"

hostnamectl set-hostname "$HOSTNAME"
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
else
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi

NETPLAN_FILE=$(ls ${TARGET}/etc/netplan/*.yml ${TARGET}/etc/netplan/*.yaml 2>/dev/null | head -n 1)

if [ -z "$NETPLAN_FILE" ]; then
    NETPLAN_FILE="${TARGET}/etc/netplan/50-cloud-init.yml"
fi

BACKUP_FILE="${NETPLAN_FILE%.*}.backup.yml"

if [ -f "$NETPLAN_FILE" ]; then
    cp "$NETPLAN_FILE" "$BACKUP_FILE"

    INTERFACE=$(grep -oP '^\s*bond\d+:' "$BACKUP_FILE" | head -n 1 | tr -d ' :')

    if [ -z "$INTERFACE" ]; then
        echo "Error: No bond interface found in Netplan configuration!"
        exit 1
    fi
    echo "Target Bond Interface: $INTERFACE"

    awk -v iface="$INTERFACE" -v ip="$IP_ADDRESS" -v gw="$GATEWAY" -v dns="$DNS_SERVER" '
    $1 == iface":" {
        print $0

        ind_key = "            "
        ind_val = "              "

        print ind_key "dhcp4: false"
        print ind_key "addresses:"
        print ind_val "- " ip
        print ind_key "routes:"
        print ind_val "- to: default"
        print ind_val "  via: " gw
        print ind_key "nameservers:"
        print ind_key "  addresses:"
        print ind_val "- " dns
        next
    }
    {print}
    ' "$BACKUP_FILE" > "$NETPLAN_FILE"

    chmod 600 "$NETPLAN_FILE"
    echo "Netplan file modified successfully!"

    netplan apply
else
    echo "Error: Netplan configuration file not found at ${NETPLAN_FILE}!"
    exit 1
fi