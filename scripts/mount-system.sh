#!/bin/bash

# ----------------------------------------------------------------------------
# mount-system: mount archvault btrfs subvolumes and efi partition
# ----------------------------------------------------------------------------
# instructions
# - modify target partition (`_partition=/dev/sda`) as needed
# - run `cryptsetup luksOpen /dev/sda3 vault` before running this script

# setup
_btrfs_subvolumes=(''
                   'boot'
                   'home'
                   'opt'
                   'srv'
                   'usr'
                   'var'
                   'var-cache-pacman'
                   'var-lib-ex'
                   'var-lib-machines'
                   'var-lib-portables'
                   'var-lib-postgres'
                   'var-log'
                   'var-opt'
                   'var-spool'
                   'var-tmp')
# use lzo compression because grub does not yet support zstd
_compression='lzo'
_mount_options="rw,lazytime,compress=$_compression,space_cache"
_partition='/dev/sda'
_vault_name='vault'

# mount btrfs subvolumes starting with root ('')
for _btrfs_subvolume in "${_btrfs_subvolumes[@]}"; do
  _btrfs_dir="${_btrfs_subvolume//-//}"
  mkdir --parents "/mnt/$_btrfs_dir"
  mount \
    --types btrfs \
    --options "$_mount_options,subvol=@$_btrfs_subvolume" \
    "/dev/mapper/$_vault_name" \
    "/mnt/$_btrfs_dir"
done

# mount uefi boot partition
mkdir --parents /mnt/boot/efi && mount "${_partition}2" /mnt/boot/efi
