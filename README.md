Holovault
=========

Holo-provisioned Arch with FDE


Usage
-----

```bash
holovault --holograms="skreltoi amnesia"        \
          --username="live"                     \
          --userpass="your new user's password" \
          --rootpass="your root password"       \
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
          install
```


Dependencies
------------

Name                 | Provides                                        | Included in Arch ISO¹?
---                  | ---                                             | ---
arch-install-scripts | `arch-chroot`, `genfstab`, `pacstrap`           | Y
base-devel           | building AUR packages                           | N
btrfs-progs          | Btrfs setup                                     | Y
cryptsetup           | FDE with LUKS                                   | Y
expect               | interactive command prompt automation           | N
findutils            | `find`                                          | Y
glibc                | locale data in `/usr/share/i18n/locales`        | Y
gptfdisk             | GPT disk partitioning with `sgdisk`             | Y
kbd                  | keymap data in `/usr/share/kbd/keymaps`         | Y
kmod                 | `modprobe`                                      | Y
openssl              | user password salts                             | Y
pacman               | `makepkg`, `pacman`                             | Y
rakudo               | `holovault` Perl 6 runtime                      | N
reflector            | https-only mirrors                              | N
tzdata               | timezone data in `/usr/share/zoneinfo/zone.tab` | Y
util-linux           | `hwclock`, `lsblk`, `mkfs`, `mount`, `umount`   | Y

¹: the [official installation medium](https://www.archlinux.org/download/)


Optional Dependencies
---------------------

Name   | Provides                | Included in Arch ISO?
---    | ---                     | ---
dialog | ncurses user input menu | Y

Dialog is needed if you do not provide by cmdline flag or environment
variable values for all configuration options aside from hostname,
username, userpass, rootpass, and vaultname. For user input of all other
options, the `dialog` program is used.


Licensing
---------

This is free and unencumbered public domain software. For more
information, see http://unlicense.org/ or the accompanying UNLICENSE file.
