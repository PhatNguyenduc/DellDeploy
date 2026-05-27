Thứ tự:
- Modify các thông tin trong host.ini và group_vars/all.yml 
Chạy lần lượt các playbook 00-04

**02_update_firmware_online.yml** luồng dự phòng nếu có internet -> chạy cái này, dell online các firm, package sẽ chuẩn hơn.
**04_deploy_os_ansible_modules.yml** tốt hơn do là ansible module đảm bảo tính idempotency. Nếu module lỗi hay deprecate hoặc lỗi k xác định, reboot idrac máy đó và thử lại, nếu vẫn k được có thể thử chạy thẳng **04_deploy_os.yml** bằng redfish để xem mã lỗi http dễ debug hơn.

cmd:
```
ansible-playbook playbooks/name_playbook -vvv
```
