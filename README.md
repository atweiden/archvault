Archvault
=========

Bootstrap Arch with FDE


Synopsis
--------

```bash
archvault --admin-name="live"                                  \
          --admin-pass="your admin user's password"            \
          --guest-name="guest"                                 \
          --guest-pass="your guest user's password"            \
          --sftp-name="variable"                               \
          --sftp-pass="your sftp user's password"              \
          --grub-name="grub"                                   \
          --grub-pass="your grub user's password"              \
          --root-pass="your root password"                     \
          --vault-name="vault"                                 \
          --vault-pass="your LUKS encrypted volume's password" \
          --hostname="vault"                                   \
          --partition="/dev/sdb"                               \
          --processor="other"                                  \
          --graphics="intel"                                   \
          --disk-type="usb"                                    \
          --locale="en_US"                                     \
          --keymap="us"                                        \
          --timezone="America/Los_Angeles"                     \
          --augment                                            \
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
glibc                | libcrypt, locale data in `/usr/share/i18n/locales` | Y
gptfdisk             | GPT disk partitioning with `sgdisk`                | Y
grub                 | `grub-mkpasswd-pbkdf2`                             | Y
haveged              | `haveged`                                          | Y
kbd                  | keymap data in `/usr/share/kbd/keymaps`, `setfont` | Y
kmod                 | `modprobe`                                         | Y
openssl              | user password salts                                | Y
pacman               | `makepkg`, `pacman`, `pacman-key`                  | Y
procps-ng            | `pkill`                                            | Y
rakudo               | `archvault` Perl6 runtime                          | N
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

- `--admin-name`
- `--admin-pass`
- `--admin-pass-hash`
- `--augment`
- `--grub-name`
- `--grub-pass`
- `--grub-pass-hash`
- `--guest-name`
- `--guest-pass`
- `--guest-pass-hash`
- `--hostname`
- `--reflector`
- `--root-pass`
- `--root-pass-hash`
- `--sftp-name`
- `--sftp-pass`
- `--sftp-pass-hash`
- `--vault-name`
- `--vault-pass`

For these options, console input is read with either `cryptsetup` or
the built-in Perl6 subroutine `prompt()`.

No console input is read for configuration options:

- `--admin-pass-hash`
- `--augment`
- `--grub-pass-hash`
- `--guest-pass-hash`
- `--reflector`
- `--root-pass-hash`
- `--sftp-pass-hash`

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
