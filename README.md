# BTRFS_Snapshots
A script for taking snapshots in a way compatible with Windows previous version (VSS) scheme

I found it tricky to get snapshots on a BTRFS file system taken and passed to SMBD in a way the works with the Windows VSS previous versions system.

As I finally got this working in the end I thought I'd share it to help save someone else's time.

## The script usage

```
Usage:
    sudo btrfs-share-snap.sh <share_path> [-t <tag>] [-c <count>] \
                                          [-m <mintime>] [-d <subdir>] \
                                          [-r] [-v] [-s] [-o]
Where:
  <share_path>                   Required. Location of the root directory of the share to
                                 take a snapshot of.
  -r                             Create a read-only snapshot. Default off
  -v                             Verbose output
  -o                             Only if new. Skips snapshot creation of no files have
                                 changed since the last time this tag was snapshotted
  -h                             Display this message
  -s                             Safe mode. Used with -v this lets you check parameters
                                 and the actions that will be taken but doesn't create
                                 or delete any snapshots.
  -t <tag_name>                  An optional tag to pre-append to the directory name
                                 of the snapshot.
  -c <count>                     The number of snapshots to keep. This is filtered by tag.
                                 Default: 0. Use 0 to disable counting
  -m <mintime>                   The minimum time in seconds that snapshots with the same
                                 tag can be taken. Default: 0. Use 0 to disable
  -d <destination-subdirectory>  The sub-directory, level with the shared directory, that
                                 holds snapshots. Default: .snapshots

The script to take the snapshots is btrfs-share-snap.sh. The default location for snapshots is in a directory at the same level as the sub-volumes (the default is .snapshots which can be changed on the command line.)
```

## Typical disk directory structure

This gives the following typical structure:-
```
.
├── .snapshots
│   ├── Docker
│   │   ├── daily_GMT-2023.07.21-16.47.13
│   │   ├── monthly_GMT-2023.07.21-16.47.14
│   │   └── weekly_GMT-2023.07.21-16.47.13
│   ├── Homes
│   │   ├── daily_GMT-2023.07.21-17.49.13
│   │   ├── monthly_GMT-2023.07.21-17.49.14
│   │   └── weekly_GMT-2023.07.21-17.49.14
│   ├── Images
│   │   ├── daily_GMT-2023.07.21-17.49.14
│   │   ├── monthly_GMT-2023.07.21-17.49.14
│   │   └── weekly_GMT-2023.07.21-17.49.14
│   ├── Media
│   │   ├── daily_GMT-2023.07.21-17.49.14
│   │   ├── monthly_GMT-2023.07.21-17.49.15
│   │   └── weekly_GMT-2023.07.21-17.49.14
│   └── Web
│       ├── daily_GMT-2023.07.21-17.49.15
│       ├── monthly_GMT-2023.07.21-17.49.15
│       └── weekly_GMT-2023.07.21-17.49.15
├── Docker
├── Homes
│   ├── administrator
│   └── user1
│       ├── .bash_history
│       ├── .bash_logout
│       ├── .bashrc
│       ├── .profile
│       └── .ssh
│           └── authorized_keys
├── Images
├── Media
├── Timemachine
└── Web
```

##Getting Samba to present this to Windows VSS
The following snippet goes in /etc/samba/smb.conf

```
[global]
# Samba VFS global defaults
# BEGIN Global defaults for Samba VFS modules
#
    vfs object = recycle shadow_copy2 btrfs fruit cap catia
# Recycle bin defaults
    recycle:repository = /mnt/pool1/%S/.recycle/%U
    recycle:touch = Yes
    recycle:keeptree = Yes
    recycle:versions = Yes
    recycle:noversions = *.tmp,*.temp,*.o,*.obj,*.TMP,*.TEMP
    recycle:exclude = *.tmp,*.temp,*.o,*.obj,*.TMP,*.TEMP
    recycle:excludedir = /.recycle,/tmp,/temp,/TMP,/TEMP

# Shadow copy settings
  #shadow:localtime MUST NOT be set to yes
    #shadow:localtime = yes
  #
    shadow:sort = desc
    shadow:format = GMT-%Y.%m.%d-%H.%M.%S
    shadow:snapprefix = ^[A-Za-z0-9_]\{0,\}$
    shadow:delimiter = GMT-

# Fruit global config
    fruit:aapl = yes
    fruit:nfs_aces = no
    fruit:copyfile = no
    fruit:model = MacSamba
# END Global defaults for Samba VFS modules

[Backup]
    path = /mnt/pool1/Backup
    comment = Backup target
    shadow:snapdir = /mnt/pool1/.snapshots/Backup
    shadow:basedir = /mnt/pool1/Backup
    writeable = yes
    read only = no
    delete readonly = yes
    create mask = 0775
    directory mask = 0775
# Uncomment this line to exclude all files from the recycle bin,
# effectivly disabling it.
#    recycle:exclude = *,*.*,.*,.*.*
```

## Creating the /etc/samba/smb.conf file

This Ansible snippet to generate the shares is:

```
#=============================================================================
{% for s in shared_folders %}
{% if s.smb == 'y' or s.smb == 'h' %}
{% if s.smb == 'h' %}
[homes]
{% else %}
[{{s.name}}]
{% endif %}
    comment = {{s.comment}}
    shadow:snapdir = {{s.loc}}/.snapshots/{{s.name}}
    shadow:basedir = {{s.loc}}/{{s.name}}
    writeable = yes
    read only = no
    delete readonly = yes
{% if s.smb == 'h' %}
    valid users = %S
    create mask = 0700
    directory mask = 0700
    browseable = no
{% else %}
    path = {{s.loc}}/{{s.name}}
    create mask = 0775
    directory mask = 0775
{% endif %}
{% if s.bindays == '0' %}
    recycle:exclude = *,*.*,.*,.*.*  
{% endif %}

{% endif %}
{% endfor %}
```

For clarity the variable definitions for this are:

```
fscfg: {
  pool:  Pool1,
  mpt:   '/mnt/pool1'
}

shared_folders:
  - {name: 'Backup', loc: '{{fscfg.mpt}}', zip: 'none', snap: 'n', bindays: '30', smb: 'y', nfs: 'y', afp: 'n', mode: '0775', comment: 'Backup target'                   }
```

## The Ansible playbook entry

```
#================================================================
- name: Configure timed share snapshots
  template:
    src: bss-cron.sh
    dest: /etc/cron.daily/bss-cron.sh
    owner: root
    group: root
    mode: 0775

- name: Configure timed share snapshots
  template:
    src: empty_recycle_bins.sh
    dest: /etc/cron.daily/empty_recycle_bins.sh
    owner: root
    group: root
    mode: 0755

#================================================================
- name: Copy the snapshot script file with owner and permissions
  ansible.builtin.copy:
    src: ./scripts/btrfs-share-snap.sh
    dest: /usr/local/sbin/btrfs-share-snap.sh
    owner: root
    group: root
    mode: '0755'
```

