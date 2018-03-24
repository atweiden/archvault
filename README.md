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
          --grubusername="your grub user's name"              \
          --grubuserpass="your grub user's password"          \
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

See: [INSTALL.md](INSTALL.md).


Dependencies
------------

Name                 | Provides                                           | Included in Arch ISO¹?
---                  | ---                                                | ---
arch-install-scripts | `arch-chroot`, `genfstab`, `pacstrap`              | Y
btrfs-progs          | Btrfs setup                                        | Y
coreutils            | `chmod`, `chown`, `cp`, `rm`                       | Y
cryptsetup           | FDE with LUKS                                      | Y
e2fsprogs            | `chattr`                                           | Y
expect               | interactive command prompt automation              | N
findutils            | `find`                                             | Y
gawk                 | `awk`                                              | Y
glibc                | libcrypt, locale data in `/usr/share/i18n/locales` | Y
gptfdisk             | GPT disk partitioning with `sgdisk`                | Y
grub                 | `grub-mkpasswd-pbkdf2`                             | Y
haveged              | `haveged`                                          | Y
kbd                  | keymap data in `/usr/share/kbd/keymaps`            | Y
kmod                 | `modprobe`                                         | Y
openssl              | user password salts                                | Y
pacman               | `makepkg`, `pacman`, `pacman-key`                  | Y
procps-ng            | `pkill`                                            | Y
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
variable values for all configuration options aside from:

- `--augment`
- `--grubusername`
- `--grubuserpass`
- `--grubuserpasshash`
- `--hostname`
- `--reflector`
- `--rootpass`
- `--rootpasshash`
- `--sshusername`
- `--sshuserpass`
- `--sshuserpasshash`
- `--username`
- `--userpass`
- `--userpasshash`
- `--vaultname`
- `--vaultpass`

For these options, console input is read with either `cryptsetup` or
the built-in Perl6 subroutine `prompt()`.

No console input is read for configuration options:

- `--augment`
- `--grubpasshash`
- `--reflector`
- `--rootpasshash`
- `--sshuserpasshash`
- `--userpasshash`

For user input of all other options, the `dialog` program is used.

`reflector` is needed if you provide by cmdline flag or environment
variable a value for the `--reflector` configuration option. The
reflector configuration option is not enabled by default. You are
recommended to select the fastest pacman mirrors for your location
by hand in `/etc/pacman.d/mirrorlist` instead of enabling `reflector`
to save several minutes of time.


Licensing
---------

This is free and unencumbered public domain software. For more
information, see http://unlicense.org/ or the accompanying UNLICENSE file.
