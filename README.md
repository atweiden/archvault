Archvault
=========

Bootstrap Arch with FDE


Description
-----------

Bootstraps new Arch Linux system with the official `pacstrap` utility,
resulting in whole system Btrfs on LUKS, including encrypted `/boot`.

Does not create a swap partition, uses
[zswap](https://www.kernel.org/doc/Documentation/vm/zswap.txt) via
[systemd-swap](https://github.com/Nefelim4ag/systemd-swap) instead.

Custom password-protected Grub command line.

Comes with support for both legacy BIOS and UEFI bootloaders, with GPT
partitioning. `/dev/sdX1` is the BIOS boot sector, `/dev/sdX2` is the
EFI system partition, `/dev/sdX3` is the root Btrfs filesystem on LUKS.

Creates the following Btrfs subvolumes:

Subvolume name       | Mounting point
---                  | ---
`@`                  | `/`
`@boot`              | `/boot`
`@home`              | `/home`
`@opt`               | `/opt`
`@srv`               | `/srv`
`@usr`               | `/usr`
`@var`               | `/var`
`@var-cache-pacman`  | `/var/cache/pacman`
`@var-lib-ex`        | `/var/lib/ex`
`@var-lib-machines`  | `/var/lib/machines`
`@var-lib-portables` | `/var/lib/portables`
`@var-lib-postgres`  | `/var/lib/postgres`
`@var-log`           | `/var/log`
`@var-opt`           | `/var/opt`
`@var-spool`         | `/var/spool`
`@var-tmp`           | `/var/tmp`

Disables Btrfs CoW on `/home`, `/srv`, `/var/lib/ex`, `/var/lib/machines`,
`/var/lib/portables`, `/var/lib/postgres`, `/var/log`, `/var/spool` and
`/var/tmp`.

Mounts directories `/srv`, `/tmp`, `/var/lib/ex`, `/var/log`, `/var/spool`
and `/var/tmp` with options `nodev,noexec,nosuid`.

Only installs packages necessary for booting to Linux tty with full
wireless capabilities and SSH support. Configures unprivileged SFTP-only
user enforced with OpenSSH `ChrootDirectory` and `internal-sftp` in
`/etc/ssh/sshd_config`.

Customizes root, admin, guest, and sftp user password. Ten
minute shell timeout, your current shell or user
session will end after ten minutes of inactivity (see:
[resources/etc/profile.d/shell-timeout.sh](resources/etc/profile.d/shell-timeout.sh)).

Nicely configures dnscrypt-proxy. Activates systemd service files for
dnscrypt-proxy, nftables and systemd-swap. Custom `sysctl.conf`.

Use `archvault --augment new` to drop to Bash console before closing
LUKS encrypted vault and unmounting.


Synopsis
--------

### `archvault new`

Bootstrap Archvault.

**Supply options interactively (recommended)**:

```sh
archvault new
```

**Supply options via environment variables**:

```sh
export ARCHVAULT_ADMIN_NAME="live"
export ARCHVAULT_ADMIN_PASS="your admin user's password"
archvault new
```

Archvault recognizes the following environment variables:

```sh
ARCHVAULT_ADMIN_NAME="live"
ARCHVAULT_ADMIN_PASS="your admin user's password"
ARCHVAULT_GUEST_NAME="guest"
ARCHVAULT_GUEST_PASS="your guest user's password"
ARCHVAULT_SFTP_NAME="variable"
ARCHVAULT_SFTP_PASS="your sftp user's password"
ARCHVAULT_GRUB_NAME="grub"
ARCHVAULT_GRUB_PASS="your grub user's password"
ARCHVAULT_ROOT_PASS="your root password"
ARCHVAULT_VAULT_NAME="vault"
ARCHVAULT_VAULT_PASS="your LUKS encrypted volume's password"
ARCHVAULT_HOSTNAME="vault"
ARCHVAULT_PARTITION="/dev/sdb"
ARCHVAULT_PROCESSOR="other"
ARCHVAULT_GRAPHICS="intel"
ARCHVAULT_DISK_TYPE="usb"
ARCHVAULT_LOCALE="en_US"
ARCHVAULT_KEYMAP="us"
ARCHVAULT_TIMEZONE="America/Los_Angeles"
ARCHVAULT_AUGMENT=1
```

**Supply options via cmdline flags**:

```sh
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

### `archvault gen-pass-hash`

Generate a password hash suitable for creating Linux user accounts or
password-protecting the Grub command line.

```sh
archvault gen-pass-hash
Enter new password:
Retype new password:
$6$rounds=700000$sleJxKNAgRnG7E8s$Fjg0/vuRz.GgF0FwDE04gP2i6oMq/Y4kodb1RLTbR3SpABVDKGdhCVfLpC5LwCOXDMEU.ylyV40..jrGmI.4N0

archvault \
  --admin-name='live'                                                                                                                          \
  --admin-pass-hash='$6$rounds=700000$sleJxKNAgRnG7E8s$Fjg0/vuRz.GgF0FwDE04gP2i6oMq/Y4kodb1RLTbR3SpABVDKGdhCVfLpC5LwCOXDMEU.ylyV40..jrGmI.4N0' \
  new
```

### `archvault ls`

List system information including keymaps, locales, timezones, and
partitions.

It's recommended to run `archvault ls <keymaps|locales|timezones>`
before running `archvault new` to ensure Archvault types
`Keymap`, `Locale`, `Timezone` are working properly (see:
[doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md#archvault-type-errors)).

**List keymaps**:

```sh
archvault ls keymaps
```

**List locales**:

```sh
archvault ls locales
```

**List partitions**:

```sh
archvault ls partitions
```

**List timezones**:

```sh
archvault ls timezones
```

### `archvault disable-cow`

Disable the Copy-on-Write attribute for Btrfs directories.

```sh
archvault -r disable-cow dest/
```


Installation
------------

See: [INSTALL.md](INSTALL.md).


Dependencies
------------

Name                 | Provides                                           | Included in Arch ISO¹?
---                  | ---                                                | ---
arch-install-scripts | `arch-chroot`, `genfstab`, `pacstrap`              | Y
btrfs-progs          | Btrfs support                                      | Y
coreutils            | `chmod`, `chown`, `cp`, `rm`                       | Y
cryptsetup           | FDE with LUKS                                      | Y
dosfstools           | create VFAT filesystem for UEFI with `mkfs.vfat`   | Y
e2fsprogs            | `chattr`                                           | Y
efibootmgr           | UEFI support                                       | Y
expect               | interactive command prompt automation              | N
glibc                | libcrypt, locale data in `/usr/share/i18n/locales` | Y
gptfdisk             | GPT disk partitioning with `sgdisk`                | Y
grub                 | FDE on `/boot`, `grub-mkpasswd-pbkdf2`             | Y
haveged              | entropy for `pacman-key`                           | Y
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

<!-- vim: set filetype=markdown foldmethod=marker foldlevel=0 nowrap: -->
