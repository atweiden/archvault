Archvault
=========

Bootstrap Arch with FDE


Synopsis
--------

```bash
archvault --username="live"                     \
          --sshusername="variable"              \
          --vaultname="luckbox"                 \
          --vaultpass="your vault password"     \
          --hostname="luckbox"                  \
          --partition="/dev/sdb"                \
          --processor="other"                   \
          --graphics="intel"                    \
          --disktype="usb"                      \
          --locale="en_US"                      \
          --keymap="us"                         \
          --timezone="America/Los_Angeles"      \
          --augment                             \
          new
```


Installation
------------

See [INSTALL.md](doc/INSTALL.md).


Dependencies
------------

Name                 | Provides                                        | Included in Arch ISO¹?
---                  | ---                                             | ---
arch-install-scripts | `arch-chroot`, `genfstab`, `pacstrap`           | Y
base-devel           | building AUR packages                           | N
btrfs-progs          | Btrfs setup                                     | Y
cryptsetup           | FDE with LUKS                                   | Y
dialog               | ncurses user input menu                         | Y
expect               | interactive command prompt automation           | N
findutils            | `find`                                          | Y
gawk                 | `awk`                                           | Y
glibc                | locale data in `/usr/share/i18n/locales`        | Y
gptfdisk             | GPT disk partitioning with `sgdisk`             | Y
kbd                  | keymap data in `/usr/share/kbd/keymaps`         | Y
kmod                 | `modprobe`                                      | Y
pacman               | `makepkg`, `pacman`                             | Y
rakudo               | `archvault` Perl6 runtime                       | N
sed                  | `sed`                                           | Y
shadow               | `passwd`                                        | Y
tzdata               | timezone data in `/usr/share/zoneinfo/zone.tab` | Y
util-linux           | `hwclock`, `lsblk`, `mkfs`, `mount`, `umount`   | Y

¹: the [official installation medium](https://www.archlinux.org/download/)


Optional Dependencies
---------------------

Name      | Provides                | Included in Arch ISO?
---       | ---                     | ---
reflector | optimize pacman mirrors | N

`reflector` is needed if you pass the `--reflector` cmdline flag to
Archvault. You are recommended to edit `/etc/pacman.d/mirrorlist`
instead to save several minutes of time. The reflector option is not
enabled by default.


Licensing
---------

This is free and unencumbered public domain software. For more
information, see http://unlicense.org/ or the accompanying UNLICENSE file.
