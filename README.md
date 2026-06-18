
<img width="147" height="40" alt="image" src="https://github.com/user-attachments/assets/986e1cce-3a10-4b40-9bd9-00f8eebf0f36" />

# CÔNG TY CỔ PHẦN PHÁT TRIỂN CÔNG NGHỆ VIỄN THÔNG TIN HỌC SUN VIỆT

# Automation Note
## 1. Installation
### Install Ansible, Dell emc collection, OME.

 1. Ansible
```
    sudo apt update 
    sudo apt install ansible -y
 ```  
 2. Ansible Galaxy colletion
 ```
 ansible-galaxy collection install ansible.utils ansible.windows dellemc.openmanage
 # python support lib
 sudo apt install python3-pip -y
python3 -m pip install omsdk requests --break-system-packages
 ```
3. OME server  
Tải bản OME cho VMware, dùng file ovf tạo máy ảo và cấu hình networking parameter phù hợp.

4. Install Nginx, DHCP
 Trên ubuntu có thể dùng isc-dhcp-server và nginx tải qua atp
 - Cấu hình DHCP: `/etc/default/isc-dhcp-server` chỉ định card mạng cấp dhcp ở file này
 ```
 ...
 # /etc/default/isc-dhcp-server

# Khai báo cho IPv4
INTERFACESv4="eth0"

# Khai báo cho IPv6 (để trống nếu không dùng)
INTERFACESv6=""
```
- File cấu hình cấp phát ip: `/etc/dhcp/dhcpd.conf` 
```
...
#ddns-update-style none;

default-lease-time 600;
max-lease-time 7200;
authoritative;

shared-network ens37 {

    subnet 10.169.98.0 netmask 255.255.255.0 {
    }

    subnet 192.168.1.0 netmask 255.255.255.0 {
        range 192.168.1.100 192.168.1.200;
        option routers 192.168.1.40;
        option domain-name-servers 8.8.8.8;
    }

}
...
``` 
- Cấu hình nginx để chỉ định đường dẫn thư mục trong `/etc/nginx/sites-available/file-name.conf`, ví dụ ở dự án lần này:
```
ubuntu@ubuntu:~$ cat /etc/nginx/sites-available/local-repo.conf
server {
    listen 80;
    server_name _;

    location /DRM/ {
        alias /data/DRM/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        location ~* \.(xml|gz|bin|exe|dUP)$ {
            default_type application/octet-stream;
            if ($request_filename ~* \.xml$) {
                add_header Content-Type "application/xml";
            }
        }
    }

    location /iso/ {
        root /data;

        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;


    }
}
```
Thư mục DRM/ chứa các file firmware và catalog.xml để giúp ome thực hiện upfirm.  
Thư mục iso/ chứa các file iso để install OS

## 2. Luồng hoạt động
<img width="1018" height="661" alt="image" src="https://github.com/user-attachments/assets/8bf22c3f-d18f-4a7e-a5e3-2ffa2bf4e760" />

1. Cấp DHCP cho loạt server, hình thành kết nối giữa máy và các server
2. Chạy các playbooks ansible: 1 - Đổi ip, sau bước đổi ip cần setup lại ip cùng dải ip vừa đổi;2 - Config bios, 3 - Upfirmware: Từ ansible trigger OME server để thực hiện update firmware trên loạt máy chủ dell OME quản lý, các file firmware sẽ kéo từ http server về;  4 - Cài đặt OS: Tạo iso custom để boot và trực tiếp nhận cấu hình theo SN của máy

Mã nguồn: ...

## 3. Chi tiết

### 1. Bypass default passwd (bước này chưa thử nghiệm).
Tải Dell EMC OpenManage DRAC Tools, includes RACADM. Chạy đổi mk theo mẫu sau:
```
for ip in [list ips]; do echo "Đang xử lý $ip...";racadm -r $ip -u root -p calvin set iDRAC.Users.2.Password "MatKhauMoi123!" >/dev/null 2>&1 && echo "Thành công: $ip" || echo "Thất bại: $ip"; done
```
### 2. Config ip theo SN
Tạo 1 file ip mapping trong thư mục gốc project ansible, ví dụ ip_mapping.csv:
```
Serial,hostname,OOB_IP,IP_VLAN47,IP_VLAN48
abcdef,compute09,10.169.98.160,10.174.48.113,172.162.0.222
```
ở phần này chỉ cần Serial và OOB_IP. Script playbook sẽ đặt ip theo SN thiết bị. 
ở dưới là task đặt ip trong playbook 01a_config_ip.yml

```
 - name: 4. Thiết lập Network Attributes và Hostname chuẩn quy hoạch cho iDRAC
      dellemc.openmanage.idrac_attributes:
        idrac_ip: "{{ idrac_ip }}"
        idrac_user: "{{ idrac_user }}"
        idrac_password: "{{ idrac_password }}"
        validate_certs: false

        idrac_attributes:
          NIC.1.DNSRacName: "{{ csv_master.dict[server_tag].hostname }}"
          IPv4.1.Enable: "Enabled"
          IPv4.1.DHCPEnable: "Disabled"
          IPv4Static.1.Address: "{{ csv_master.dict[server_tag].OOB_IP }}"
          IPv4Static.1.Netmask: "255.255.255.0"
          IPv4Static.1.Gateway: "{{ ip_gateway }}"
      when: server_tag in csv_master.dict
      register: config_result
      ignore_errors: true
```

### 3. Config bios & Update firmware

Phần config bios đơn giản, chỉ cần tra các attribute theo yêu cầu và xác minh nó hoạt động. Phần Update firmware thực hiện như sau:
1. Truy cập giao diện OME, login.
2. Vào Monitor --> Discovery --> Create để tạo job discovery iDRAC.
<img width="1827" height="912" alt="image" src="https://github.com/user-attachments/assets/c7d40196-c54d-43f1-b40e-fb908e77bc19" />
Chọn server dell iDRAC, nhập range ip, user/pass của iDRAC, chọn Finish
<img width="1821" height="951" alt="image" src="https://github.com/user-attachments/assets/dccfbb6f-4d54-4618-b11a-40c5f5a90263" />
3. Chờ Discovery job hoàn thành, và chờ On-boarding job tự động, sẽ nhìn thấy danh sách device ta quản lý:
<img width="1801" height="860" alt="image" src="https://github.com/user-attachments/assets/49133234-a0c0-4a3e-80eb-87b9502ec9b1" />

phải health check là xanh, ảnh trên minh hoạ danh sách thiết bị.

4. Chạy playbook update firmware. 
Luồng thực hiện diễn ra gồm khởi tạo catalog firmware: ở bước này nó sẽ đọc danh sách file ta up lên  /DRM/ trên Nginx server, tên catalog phải chính xác tuyệt đối với name nhập trong playbook. Sau đó, Firmware baseline được tạo, mặc định áp dụng cho tất cả thiết bị quản lý, cuối cùng là ra lệnh ome update firmware ngay mà k schedual time. (Mục này đọc playbook 02_update_firmware.yml)

> Lưu ý: Mỗi lần chạy update firmware cho 1 nhóm thiết bị mới truy cập giao diện OME xoá baseline và catalog cũ đi do nếu để tên giống thì nó dùng luôn baseline cũ và nhóm thiết bị cũ. Hoặc phải đổi tên firmware và catalog trong playbook (ví dụ đánh version)

<img width="1847" height="910" alt="image" src="https://github.com/user-attachments/assets/281fd820-5196-4f45-9f48-12b797f5426b" />
<img width="750" height="162" alt="image" src="https://github.com/user-attachments/assets/fef35cd1-443e-49ad-a3ed-4bb6c633d9cd" />
hoặc đổi tên mỗi lần chạy:
<img width="750" height="162" alt="image" src="https://github.com/user-attachments/assets/fef35cd1-443e-49ad-a3ed-4bb6c633d9cd" />

### 4. Config RAID 1
phần này tham khảo playbook 03_config_raid.yml. Lưu ý cần thu thập đúng thông tin thiết bị trước khi tạo RAID, có thể tạo playbook phụ để thu thập thông tin. Với dự án đang thực hiện R660 đã có sẵn RAID 1 nên k cần chạy. 

### 5. Deploy OS

1. Tạo iso custom
Tài liệu automation: 
Tham khảo tài liệu Automation để làm rõ chi tiết tạo custom-iso, khái quát quá trình như sau:
- Tải iso và unzip iso ubuntu
- Thêm file vào thư mục /nocloud/ trong iso. 
- Các file gồm user-data, meta-data, script, csv. user-data mô tả hệ điều hành được cấu hình thế nào, meta-data là file bắt buộc, rỗng, nó là require của ubuntu để tạo custom iso. File script thực hiện điều chỉnh các thông số mong muốn của thiết bị theo Serial Number, các thông số của loạt thiết bị được lưu trong file csv, script được thực hiện chỉ định trong file user-data với block user-data: run-cmd: ... Quá trình thực hiện diễn ra sau cloud-init và có reboot nên không cần chạy các lệnh restart kèm theo.
- Zip lại thành 1 iso , gọi là custom iso.
2. Chạy playbook 04_deploy_os.yml.
Các bước của playbook này gồm: Gỡ đĩa iso đang kẹt (nếu có), mount iso từ http server, thực hiện chỉ định boot từ đĩa vừa mount. 

## Các lưu ý

1. Chuẩn bị nhiều file host.ini : host1.ini , host2.ini. host1 chứa các ip trong dhcp server để thực hiện đổi ip theo SN. host2 đã chứa các ip đúng quy hoạch để đỡ mất thời gian trong quá trình thực hiện

2. Các ip biến không đặt tiền tố http:// do khi chạy module ansible đã chỉ định loại kết nối nên nó sẽ bị duplicate http://http:// dẫn đến lỗi.
<img width="352" height="118" alt="image" src="https://github.com/user-attachments/assets/6441a4e3-8288-4227-885f-2dc23cbe1f6a" />

3. Check các tên file đảm bảo giống nhau trong playbook và http.
4. Lệnh run trong root project-ansible
```
ansible-playbook -i inventory/host_x.ini playbooks/playbook_x.yml
```
trong đó -i sẽ chỉ định file host.ini được thực hiện sau đó là chỉ định playbook. Có thể thêm -v, -vvv để debug.
