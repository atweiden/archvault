#!/bin/bash

export PATH="bin:$PATH"
export PERL6LIB="lib"
export ARCHVAULT_USERNAME="live"
export ARCHVAULT_USERPASS="your admin user's password"
export ARCHVAULT_SSHUSERNAME="variable"
export ARCHVAULT_SSHUSERPASS="your ssh user's password"
export ARCHVAULT_ROOTPASS="your root password"
export ARCHVAULT_VAULTNAME="vault"
export ARCHVAULT_VAULTPASS="your LUKS encrypted volume's password"
export ARCHVAULT_HOSTNAME="vault"
export ARCHVAULT_PARTITION="/dev/sdb"
export ARCHVAULT_PROCESSOR="other"
export ARCHVAULT_GRAPHICS="intel"
export ARCHVAULT_DISKTYPE="usb"
export ARCHVAULT_LOCALE="en_US"
export ARCHVAULT_KEYMAP="us"
export ARCHVAULT_TIMEZONE="America/Los_Angeles"
export ARCHVAULT_AUGMENT=1
archvault new
