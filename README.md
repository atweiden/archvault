Archvault
=========

Bootstrap Arch with FDE


Synopsis
--------

```bash
archvault --username="live"                                   \
          --userpass="your admin user's password"             \
          --sshusername="variable"                            \
          --sshuserpass="your ssh user's password"            \
          --rootpass="your root password"                     \
          --vaultname="vault"                                 \
          --vaultpass="your LUKS encrypted volume's password" \
          --hostname="vault"                                  \
          --partition="/dev/sdb"                              \
          --processor="other"                                 \
          --graphics="intel"                                  \
          --disktype="usb"                                    \
          --locale="en_US"                                    \
          --keymap="us"                                       \
          --timezone="America/Los_Angeles"                    \
          --augment                                           \
          new
```


Installation
------------

See [INSTALL.md](doc/INSTALL.md).


Dependencies
------------

Name                 | Provides                                           | Included in Arch ISO¹?
---                  | ---                                                | ---
arch-install-scripts | `arch-chroot`, `genfstab`, `pacstrap`              | Y
btrfs-progs          | Btrfs setup                                        | Y
cryptsetup           | FDE with LUKS                                      | Y
expect               | interactive command prompt automation              | N
findutils            | `find`                                             | Y
gawk                 | `awk`                                              | Y
glibc                | libcrypt, locale data in `/usr/share/i18n/locales` | Y
gptfdisk             | GPT disk partitioning with `sgdisk`                | Y
kbd                  | keymap data in `/usr/share/kbd/keymaps`            | Y
kmod                 | `modprobe`                                         | Y
openssl              | user password salts                                | Y
pacman               | `makepkg`, `pacman`                                | Y
rakudo               | `archvault` Perl6 runtime                          | N
sed                  | `sed`                                              | Y
tzdata               | timezone data in `/usr/share/zoneinfo/zone.tab`    | Y
util-linux           | `hwclock`, `lsblk`, `mkfs`, `mount`, `umount`      | Y

¹: the [official installation medium](https://www.archlinux.org/download/)


Optional Dependencies
---------------------

Name      | Provides                | Included in Arch ISO?
---       | ---                     | ---
dialog    | ncurses user input menu | Y
reflector | optimize pacman mirrors | N

`dialog` is needed if you do not provide by cmdline flag or environment
variable values for all configuration options aside from `--hostname`,
`--username`, `--userpass`, `--userpasshash`, `--sshusername`,
`--sshuserpass`,`--sshuserpasshash`, `--rootpass`, `--rootpasshash`,
`--vaultname`, `--vaultpass`, `--augment` and `--reflector`. For these
options, console input is read with either the built-in Perl6 subroutine
`prompt()` or a program like `cryptsetup`. In the case of `--augment`,
`--reflector`, `--userpasshash`, `--sshuserpasshash` and `--rootpasshash`
no console input is read. For user input of all other options, the
`dialog` program is used.

`reflector` is needed if you provide by cmdline flag or environment
variable a value for the `--reflector` configuration option. The
reflector option is not enabled by default. You are recommended to edit
`/etc/pacman.d/mirrorlist` by hand instead to save several minutes
of time.


Licensing
---------

This is free and unencumbered public domain software. For more
information, see http://unlicense.org/ or the accompanying UNLICENSE file.
