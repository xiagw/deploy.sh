# Set up xray client/server on Debian/Ubuntu
1. Install `ansible-galaxy install git+https://github.com/xiruizhao/ansible-role-xray.git`
2. Examples
```yaml
---
- hosts: all
  become: yes
  roles:
    - role: ansible-role-xray
      xray_server_addr: example.com
      xray_generate_client_config: true
      certbot_admin_email: admin@example.com
```
