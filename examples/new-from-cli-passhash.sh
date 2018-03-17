#!/bin/bash

# admin, root and ssh password: xyzzy
export PATH="bin:$PATH"
export PERL6LIB='lib'
archvault --username='live'                                                                                                                            \
          --userpasshash='$6$rounds=700000$sleJxKNAgRnG7E8s$Fjg0/vuRz.GgF0FwDE04gP2i6oMq/Y4kodb1RLTbR3SpABVDKGdhCVfLpC5LwCOXDMEU.ylyV40..jrGmI.4N0'    \
          --sshusername='variable'                                                                                                                     \
          --sshuserpasshash='$6$rounds=700000$H0WWMRVAqKMmJVUx$X9NiHaL.cvZ1/nQzUL5fcRP12wvOyrZ/0YV57cFddcTEkVZKbtIBv48EEd4SVu.1D5RWVX43dfTuyudYem0gf0' \
          --rootpasshash='$6$rounds=700000$xDn3UJKNvfOxJ1Ds$YEaaBAvQQgVdtV7jFfVnwmh57Do1awMh8vTBtI1higrZMAXUisX2XKuYbdTcxgQMleWZvK3zkSJQ4F3Jyd5Ln1'    \
          --vaultname='vault'                                                                                                                          \
          --vaultpass='xyzzy'                                                                                                                          \
          --hostname='vault'                                                                                                                           \
          --partition='/dev/sda'                                                                                                                       \
          --processor='intel'                                                                                                                          \
          --graphics='intel'                                                                                                                           \
          --disktype='ssd'                                                                                                                             \
          --locale='en_US'                                                                                                                             \
          --keymap='us'                                                                                                                                \
          --timezone='America/New_York'                                                                                                                \
          new

# vim: set nowrap:
