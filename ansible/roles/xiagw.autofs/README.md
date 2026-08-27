xiagw.autofs
============

Configure an autofs + NIS + NFS client on Debian/Ubuntu hosts. It installs the
needed packages, programs the automounter maps, registers the NIS domain against
a ypserver, adds NIS to NSS, and enables `pam_mkhomedir` so a user's home under
`/home2` is created on first login.

Role is **Debian-only** and is fully guarded, so it is a no-op on other OS
families (e.g. `RedHat`, `Darwin`).

Requirements
------------

- Target host runs Debian or Ubuntu.
- A reachable NIS server (`ypserver`) and NFS server exporting `/data` and
  `/home2`.

Role Variables
--------------

All variables live in `defaults/main.yml` and can be overridden by inventory or
playbook vars:

| Variable               | Default                | Description                                   |
|------------------------|------------------------|-----------------------------------------------|
| `autofs_nis_domain`    | `smartind.cn`          | NIS domain name registered in `yp.conf`       |
| `autofs_nis_server`    | `git.smartind.cn`      | NIS `ypserver` host (resolvable via `/etc/hosts`) |
| `autofs_nfs_server`    | `192.168.199.190`      | NFS server exporting `/data` and `/home2`     |

Generated files (based on the variables above):

- `/etc/auto.data` → mounts `{{ autofs_nfs_server }}:/data` at `/data`
- `/etc/auto.home` → mounts `{{ autofs_nfs_server }}:/home2/<user>` at `/home2/<user>`
- `/etc/yp.conf` → `domain {{ autofs_nis_domain }} server {{ autofs_nis_server }}`
- `/etc/nsswitch.conf` → `passwd`/`group`/`shadow`/`hosts` gain `nis`
- `/etc/pam.d/common-session` → adds `pam_mkhomedir.so`
- `/etc/auto.master` → static file from `files/auto.master`

Dependencies
------------

None.

Example Playbook
----------------

    - hosts: clients
      become: true
      roles:
        - role: xiagw.autofs
          vars:
            autofs_nis_domain: example.lan
            autofs_nis_server: ypserver.example.lan
            autofs_nfs_server: 192.168.199.190

License
-------

BSD-3-Clause

Author Information
------------------

xiagw / smartind
