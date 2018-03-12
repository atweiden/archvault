#!/bin/bash

export PATH="bin:$PATH"
export PERL6LIB="lib"
archvault --username="live"                                   \
          --userpass="your trusted admin user's password"     \
          --sshusername="variable"                            \
          --sshuserpass="your untrusted ssh user's password"  \
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
