Install
=======

If you intend to run Archvault in a LiveCD environment, *you must
increase the size of the root partition* to avoid running out of
[disk space][disk] on the LiveCD. Using the official Arch Linux ISO,
when you see the boot loader screen, press <kbd>Tab</kbd> and [append
the following][gist] parameter to the kernel line: `copytoram=y
copytoram_size=10G cow_spacesize=10G`. Then, press <kbd>Enter</kbd>.

In order to use Archvault, install [Rakudo Perl 6][rakudo]. Archvault
will automatically resolve all other dependencies.


Installing Rakudo Perl 6
------------------------

After logging in to the Arch Linux installation CD as root:

```sh
# customize
vim /etc/pacman.d/mirrorlist

# add private repo until official rakudo package in community
cat <<'EOF' >> /etc/pacman.conf
[rakudo]
SigLevel = Optional
Server = https://spider-mario.quantic-telecom.net/archlinux/$repo/$arch
EOF

# sync
pacman -Syy

# install perl6
pacman -S rakudo
```


Fetching Archvault
------------------

```sh
# install git
pacman -S git

# clone archvault
git clone https://github.com/atweiden/archvault
```


Running Archvault
-----------------

```sh
cd archvault
export PERL6LIB=lib
bin/archvault --help
```


[disk]: https://bbs.archlinux.org/viewtopic.php?id=210389
[gist]: https://gist.github.com/satreix/c01fd1cb5168e539404b
[rakudo]: https://github.com/rakudo/rakudo
