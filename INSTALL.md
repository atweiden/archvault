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

### Install Rakudo Perl 6 from binary repo

```sh
# add private repo until official rakudo package in community
cat >> /etc/pacman.conf <<'EOF'
[perl6]
SigLevel = PackageOptional
Server = https://github.com/atweiden/pkgbuilds/releases/download/latest
EOF

pacman -Syy git rakudo
```

### Install Rakudo Perl 6 using rakudobrew

```sh
pacman -Syy base-devel git --needed
git clone https://github.com/tadzik/rakudobrew ~/.rakudobrew
export PATH="$HOME/.rakudobrew/bin:$PATH"
rakudobrew build moar 2018.05
```

### Install Rakudo Perl 6 from official release tarballs

Make non-root user account for installing AUR packages:

```sh
useradd -m -s /bin/bash live
passwd live
echo "live ALL=(ALL) ALL" >> /etc/sudoers
```

Switch to non-root user account:

```sh
su live
cd
```

Fetch scripts for fetching PGP keys with Curl:

```sh
curl \
  -L \
  -o '#1-#2.#3' \
  https://github.com/atweiden/{ttyfiles}/archive/{master}.{tar.gz}
tar xvzf ttyfiles-master.tar.gz
cd ttyfiles-master
```

Fetch scripts for fetching PGP keys with Git:

```sh
pacman -S git
git clone https://github.com/atweiden/ttyfiles
cd ttyfiles
```

Fetch PGP keys for installing AUR packages:

```sh
./fetch-pgp-keys.sh
```

Fetch PKGBUILDs with Curl:

```sh
curl \
  -L \
  -o '#1-#2.#3' \
  https://github.com/atweiden/{pkgbuilds}/archive/{master}.{tar.gz}
tar xvzf pkgbuilds-master.tar.gz
cd pkgbuilds-master
```

Fetch PKGBUILDs with Git:

```sh
git clone https://github.com/atweiden/pkgbuilds --depth 1
cd pkgbuilds
```

Install AUR packages:

```sh
pacman -Syy base-devel --needed
pushd moarvm && makepkg -Acsi && popd
pushd nqp && makepkg -Acsi && popd
pushd rakudo && makepkg -Acsi && popd
```


Running Archvault
-----------------

Fetch Archvault sources with Curl:

```sh
# official release tarball
VERSION=1.6.0
curl \
  -L \
  -O \
  https://github.com/atweiden/archvault/releases/download/$VERSION/archvault-$VERSION.tar.gz
tar xvzf archvault-$VERSION.tar.gz
cd archvault-$VERSION

# latest snapshot
curl \
  -L \
  -o '#1-#2.#3' \
  https://github.com/atweiden/{archvault}/archive/{master}.{tar.gz}
tar xvzf archvault-master.tar.gz
cd archvault-master
```

Fetch Archvault sources with Git:

```sh
git clone https://github.com/atweiden/archvault
cd archvault
```

Run Archvault (as root):

```sh
export PATH="$(realpath bin):$PATH"
export PERL6LIB="$(realpath lib)"
archvault --help
```


[disk]: https://bbs.archlinux.org/viewtopic.php?id=210389
[gist]: https://gist.github.com/satreix/c01fd1cb5168e539404b
[rakudo]: https://github.com/rakudo/rakudo
