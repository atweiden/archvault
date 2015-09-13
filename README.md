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

- Rakudo Perl 6: `holovault` runtime
- arch-install-scripts: `arch-chroot`, `genfstab`, `pacstrap`
- base-devel: building AUR packages
- btrfs-progs: Btrfs setup
- expect: interactive command prompt automation
- findutils: `find`
- glibc: locale data in `/usr/share/i18n/locales`
- holo: provisioning with holograms
- gptfdisk: GPT disk partitioning
- kbd: keymap data in `/usr/share/kbd/keymaps`
- openssl: user password salts
- reflector: https-only mirrors
- tzdata: timezone data in `/usr/share/zoneinfo/zone.tab`
- util-linux: `hwclock`, `lsblk`, `mkfs`, `mount`, `umount`


Optional Dependencies
---------------------

- dialog: ncurses user input menu


Licensing
---------

This is free and unencumbered public domain software. For more
information, see http://unlicense.org/ or the accompanying UNLICENSE file.
