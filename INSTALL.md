Install
=======

If you intend to run Archvault in a LiveCD environment, *you must increase
the size of the root partition* to avoid running out of [disk space][disk]
on the LiveCD. Using the official Arch Linux ISO, when you see the boot
loader screen, press <kbd>Tab</kbd> and [append the following][gist] to
the kernel line: `copytoram=y copytoram_size=7G cow_spacesize=7G`. Then,
press <kbd>Enter</kbd>.

In order to use Archvault, install [Rakudo Perl 6][rakudo]. Archvault
will automatically resolve all other dependencies.


Installing Rakudo Perl 6
------------------------

After logging in to the Arch Linux installation CD as root:

```sh
# select fastest mirrors
vim /etc/pacman.d/mirrorlist
```

**Install Rakudo Perl 6 from binary repo**:

```sh
# add private repo until official rakudo package in community
cat >> /etc/pacman.conf <<'EOF'
[rakudo]
SigLevel = Optional
Server = https://spider-mario.quantic-telecom.net/archlinux/$repo/$arch
EOF

pacman -Syy git rakudo
```

**Install Rakudo Perl 6 using rakudobrew**:

```sh
pacman -Syy base-devel git --needed
git clone https://github.com/tadzik/rakudobrew ~/.rakudobrew
export PATH="$HOME/.rakudobrew/bin:$PATH"
rakudobrew build moar 2018.05
```

**Install Rakudo Perl 6 from official release tarballs**:

Make non-root user account for installing AUR packages:

```sh
useradd -m -s /bin/bash live
passwd live
echo "live ALL=(ALL) ALL" >> /etc/sudoers
```

Fetch PGP keys for installing AUR packages:

```sh
su live
cd
git clone https://github.com/atweiden/ttyfiles
cd ttyfiles
./fetch-pgp-keys.sh
```

Install AUR packages:

```sh
pacman -Syy base-devel git --needed
git clone https://github.com/atweiden/pkgbuilds --depth 1
cd pkgbuilds
pushd moarvm && makepkg -Acsi && popd
pushd nqp && makepkg -Acsi && popd
pushd rakudo && makepkg -Acsi && popd
```


Running Archvault
-----------------

```sh
git clone https://github.com/atweiden/archvault
cd archvault
export PERL6LIB=lib
bin/archvault --help
```


[disk]: https://bbs.archlinux.org/viewtopic.php?id=210389
[gist]: https://gist.github.com/satreix/c01fd1cb5168e539404b
[rakudo]: https://github.com/rakudo/rakudo
