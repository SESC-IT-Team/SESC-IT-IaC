# SSH User Management

Create users with SSH keys via Ansible.

## Usage

Add your user to `ansible/ssh/users.yml`:

```yaml
- username: me
  groups: sudo,docker
  shell: /bin/zsh
  ssh_key: "your public key (~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"
  nopasswd_sudo: yes
```

## Run playbook

Commit and push your changes, then ask admin to run the playbook, or run it yourself.

1. Add your server IP to `ansible/inventory.ini`:
```ini
[all]
xxx.xxx.xxx.xxx ansible_user=root
```

2. Run:
```bash
ansible-playbook -i inventory.ini users.yml --ask-pass
```
