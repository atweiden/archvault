# Troubleshooting

## Archvault Type Errors

If Archvault fails to compile, it will usually be due to Arch Linux system
upgrades rendering Archvault's types (`Keymap`, `Locale`, `Timezone`)
out of date. This is fairly easy to fix manually:

**`Keymap` type is out of date**

**`Locale` type is out of date**

**`Timezone` type is out of date**

## Archvault Wireless Errors

If Archvault fails to connect to a wireless access point, it's a sure sign
of trouble to come. Rather than trying to make your machine's factory
wireless card work, do yourself a favor and buy a high gain USB adapter
from [SimpleWiFi][SimpleWiFi].

## Booting Archvault From Grub Rescue Shell

If upon booting the Archvault system, you initially enter the wrong
vault password, Grub will drop you into a rescue shell. [Here][here]
is how to recover the system from the Grub rescue shell without rebooting:

**Most systems**

```
grub rescue> ls
(hd0) (hd0,gpt3) (hd0,gpt2) (hd0,gpt1) (proc)
grub rescue> cryptomount hd0,gpt3
Attempting to decrypt master key...
Enter passphrase for hd0,gpt3 (88caa067d343402aabd6b107ab08125a):
Slot 0 opened
grub rescue> insmod normal
grub rescue> normal
```

**VirtualBox UEFI systems**

```
grub rescue> ls
(proc) (hd0) (hd1) (hd1,gpt3) (hd1,gpt2) (hd1,gpt1)
grub rescue> cryptomount hd1,gpt3
Attempting to decrypt master key...
Enter passphrase for hd1,gpt3 (88caa067d343402aabd6b107ab08125a):
Slot 0 opened
grub rescue> insmod normal
grub rescue> normal
```

## Booting Archvault Takes a Really Long Time

It takes a really long time for [Grub][Grub] to decrypt the `/boot`
partition.

## Error While Booting: Kernel Panic

This might be due to an error completing the `mkinitcpio -p linux`
command. Re-run `mkinitcpio -p linux` from a LiveCD after mounting
the system:

```sh
cryptsetup luksOpen /dev/sda3 vault
# see: https://github.com/atweiden/scripts/blob/master/mnt-btrfs.sh
curl -o mnt-btrfs.sh http://ix.io/1iMQ
chmod +x mnt-btrfs.sh
./mnt-btrfs.sh
arch-chroot /mnt pacman -Syu
arch-chroot /mnt mkinitcpio -p linux
```

## Error While Loading Shared Libraries

If during Archvault installation, the system complains about missing
shared libraries, out of date packages are most likely to blame. For
example:

```
/usr/bin/systemd-sysusers: error while loading shared libraries: libjson-c.so.4: cannot open shared object file: No such file or directory
```

The package that provides `libjson-c.so.4` is out of date or missing. To
fix this, update or install pkg `json-c`:

```
pacman -S json-c
```

Or if all else fails, run `pacman -Syu`.

If you're using an outdated Arch Linux installation medium, retry with
the newest version. It's best practice to always use the newest version
of the official Arch Linux installation medium.

## Monitor Resolution Issues

One way to work around monitor resolution issues is to use Vim.

Open vim:

```
vim
```

Create a horizontal split:

```vim
:sp
```

Switch to the bottom split:

- <kbd>Ctrl-w</kbd> <kbd>j</kbd>

Create a vertical split:

```vim
:vsp
```

Switch to the bottom right split, which we'll use as our *main split*:

- <kbd>Ctrl-w</kbd> <kbd>l</kbd>

Create a vertical split within the *main split*:

```vim
:vsp
```

Maximize the *main split* vertically and horizontally:

- <kbd>Ctrl-w</kbd> <kbd>_</kbd>
- <kbd>Ctrl-w</kbd> <kbd>|</kbd>

Center the *main split*:

- <kbd>Ctrl-w</kbd> <kbd>h</kbd>
- <kbd>Ctrl-w</kbd> <kbd>l</kbd>
- <kbd>Ctrl-w</kbd> <kbd>l</kbd>

Navigate back to the *main split*:

- <kbd>Ctrl-w</kbd> <kbd>h</kbd>

Open a terminal:

```vim
:terminal
```

Re-maximize the *main split* vertically:

- <kbd>Ctrl-w</kbd> <kbd>_</kbd>


[Grub]: https://www.reddit.com/r/archlinux/comments/6ahvnk/grub_decryption_really_slow/dhew32m/
[here]: https://unix.stackexchange.com/questions/318745/grub2-encryption-reprompt/321825#321825
[SimpleWiFi]: https://www.simplewifi.com/collections/usb-adapters/products/usb-adapter
