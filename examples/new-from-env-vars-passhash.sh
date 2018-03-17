#!/bin/bash

# admin, root and ssh password: xyzzy
export PATH="bin:$PATH"
export PERL6LIB='lib'
export ARCHVAULT_USERNAME='live'
export ARCHVAULT_USERPASSHASH='$6$rounds=700000$sleJxKNAgRnG7E8s$Fjg0/vuRz.GgF0FwDE04gP2i6oMq/Y4kodb1RLTbR3SpABVDKGdhCVfLpC5LwCOXDMEU.ylyV40..jrGmI.4N0'
export ARCHVAULT_SSHUSERNAME='variable'
export ARCHVAULT_SSHUSERPASSHASH='$6$rounds=700000$H0WWMRVAqKMmJVUx$X9NiHaL.cvZ1/nQzUL5fcRP12wvOyrZ/0YV57cFddcTEkVZKbtIBv48EEd4SVu.1D5RWVX43dfTuyudYem0gf0'
export ARCHVAULT_ROOTPASSHASH='$6$rounds=700000$xDn3UJKNvfOxJ1Ds$YEaaBAvQQgVdtV7jFfVnwmh57Do1awMh8vTBtI1higrZMAXUisX2XKuYbdTcxgQMleWZvK3zkSJQ4F3Jyd5Ln1'
export ARCHVAULT_VAULTNAME='vault'
export ARCHVAULT_VAULTPASS='xyzzy'
export ARCHVAULT_HOSTNAME='vault'
export ARCHVAULT_PARTITION='/dev/sda'
export ARCHVAULT_PROCESSOR='intel'
export ARCHVAULT_GRAPHICS='intel'
export ARCHVAULT_DISKTYPE='ssd'
export ARCHVAULT_LOCALE='en_US'
export ARCHVAULT_KEYMAP='us'
export ARCHVAULT_TIMEZONE='America/New_York'
archvault new

# vim: set nowrap:
