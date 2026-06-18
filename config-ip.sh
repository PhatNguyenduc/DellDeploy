#!/bin/bash

MAPPING_FILE="/opt/ip_mapping.csv"

if [ ! -f "$MAPPING_FILE" ]; then
    echo "Error: File $MAPPING_FILE not found!"
    exit 1
fi

# Thu thập mã Serial Number chuẩn (Service Tag)
SERIAL=$(dmidecode -s system-serial-number | tr -d ' \n')
if [ -z "$SERIAL" ] || [ "$SERIAL" == "NotSpecified" ]; then
    echo "Error: Unable to retrieve system serial number!"
    exit 1
fi
echo "Current System Serial: $SERIAL"

# Tìm dòng mapping tương ứng (không phân biệt hoa thường)
MATCH_LINE=$(grep -i "^$SERIAL," "$MAPPING_FILE")

if [ -z "$MATCH_LINE" ]; then
    echo "Warning: Serial $SERIAL not found in mapping file. Skipping configuration."
    exit 0
fi

# Khai thác dữ liệu từ các cột trong file CSV
HOSTNAME=$(echo "$MATCH_LINE" | cut -d',' -f2 | tr -d ' \r\n')
HOSTNAME=${HOSTNAME,,}
OOB_IP=$(echo "$MATCH_LINE" | cut -d',' -f3 | tr -d ' \r\n')
IP_VLAN47=$(echo "$MATCH_LINE" | cut -d',' -f4 | tr -d ' \r\n')
IP_VLAN48=$(echo "$MATCH_LINE" | cut -d',' -f5 | tr -d ' \r\n')

echo "Applying Profile: Hostname=$HOSTNAME"
echo "VLAN 47 IP: $IP_VLAN47 | VLAN 48 IP: $IP_VLAN48"

# Đổi Hostname hệ thống và cập nhật file hosts
hostnamectl set-hostname "$HOSTNAME"
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
else
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi

cat << LOG_EOF > /etc/infrastructure_info.txt
HostName:    $HOSTNAME
Serial No:   $SERIAL
iDRAC OOB:   $OOB_IP
VLAN 47 IP:  $IP_VLAN47 (Gateway: 10.171.48.1)
VLAN 48 IP:  $IP_VLAN48 (Gateway: None)
Config Date: $(date)
=========================================
LOG_EOF

cat << NETPLAN_EOF > /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    eno12399np0:
      mtu: 9000
    eno12409np1:
      mtu: 9000
    enp160s0f0np0:
      mtu: 9000
    enp160s0f1np1:
      mtu: 9000
    enp55s0f0np0:
      mtu: 9000
    enp55s0f1np1:
      mtu: 9000
  bonds:
    bond1:
      mtu: 9000
      interfaces:
        - enp55s0f0np0
        - enp160s0f0np0
      parameters:
        lacp-rate: fast
        mode: 802.3ad
        transmit-hash-policy: layer3+4
    bond2:
      mtu: 9000
      interfaces:
        - enp55s0f1np1
        - eno12399np0
      parameters:
        lacp-rate: fast
        mode: 802.3ad
        transmit-hash-policy: layer3+4
    bond3:
      mtu: 9000
      interfaces:
        - enp160s0f1np1
        - eno12409np1
      parameters:
        lacp-rate: fast
        mode: 802.3ad
        transmit-hash-policy: layer3+4
  vlans:
    bond1.47:
      id: 47
      link: bond1
      mtu: 9000
      addresses:
        - ${IP_VLAN47}/22
      routes:
        - to: default
          via: 10.171.48.1
    bond1.48:
      id: 48
      link: bond1
      mtu: 9000
      addresses:
        - ${IP_VLAN48}/20
NETPLAN_EOF

# Khóa quyền bảo mật file Netplan và thực thi áp cấu hình mạng mới
chmod 600 /etc/netplan/50-cloud-init.yaml
echo "Netplan template generated successfully!"

netplan apply
echo "Network configuration applied successfully!"