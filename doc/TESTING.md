Testing Archvault
=================

VMWare Fusion 10.1.1
--------------------

### Pre-Setup

- If your computer is low on memory, close all other programs besides
  VMWare Fusion
- Determine the fastest pacman mirrors for your location

### Setup

- Select File->New
- Drag and drop the official Arch Linux ISO into window from MacOS Finder
- Select Linux->Other Linux 4.x or later kernel 64-bit
- Select Legacy BIOS
- Select Customize Settings
  - Processors and Memory
    - 1 processor core
    - Memory: 2048 MB
  - Isolation
    - uncheck Enable Drag and Drop
    - uncheck Enable Copy and Paste

### Bootstrap Archvault

- Press Play
- Press <kbd>Tab</kbd> when you see the boot loader screen
  - Append `copytoram=y copytoram_size=7G cow_spacesize=7G` to the
    kernel line
  - Press <kbd>Enter</kbd>
- Allow time for the LiveCD to boot up
- Configure pacman mirrorlist
  - `vim /etc/pacman.d/mirrorlist`
- Configure pacman.conf
  - `vim /etc/pacman.conf`
  - Uncomment `Color`
  - Uncomment `TotalDownload`
  - Add `ILoveCandy` on new line beneathe `CheckSpace`
  - Add spidermario's private Rakudo Perl 6 binary repo:

```dosini
[rakudo]
SigLevel = Optional
Server = https://spider-mario.quantic-telecom.net/archlinux/$repo/$arch
```

- Sync pacman mirrors
  - `pacman -Syy`
- Install Git and Rakudo Perl 6
  - `pacman -S git rakudo`
- Clone Archvault sources
  - `git clone https://github.com/atweiden/archvault --depth 1`
- Run Archvault
  - `cd archvault`
  - `export PERL6LIB=lib`
  - `bin/archvault --help`
  - `bin/archvault new`
- Follow the prompts as needed, let Archvault finish to completion
- Shutdown the LiveCD
  - `shutdown now`

### Boot New Machine

- Configure VMWare Fusion virtual machine to not use Arch Linux ISO
  - Virtual Machine->Settings->CD/DVD (IDE)
    - Uncheck Connect CD/DVD Drive
- Configure VMWare Fusion virtual machine to pass battery status to guest
  - Virtual Machine->Settings->Advanced
    - Check Pass power status to VM
- Press Play
- Enter vault password
- Login as admin user
  - root login will fail due to `/etc/securetty` config
- Get online
  - `sudo systemctl start dhcpcd`
  - `sudo systemctl enable dhcpcd`
- Synchronize time
  - `sudo systemctl start systemd-timesyncd`
  - `sudo systemctl enable systemd-timesyncd`
  - `sudo timedatectl set-ntp true`
  - `timedatectl status`
- Get pkgs
  - `sudo pacman -S colordiff git ripgrep pacmatic the_silver_searcher`
  - `sudo pacman -S mlocate moreutils tree`
  - `sudo pacman -S ccrypt pwgen socat tor torsocks`
- Get AUR pkgs
  - `git clone https://aur.archlinux.org/clonepkg.git`
  - `cd clonepkg && makepkg -Acsi --noconfirm`
  - `clonepkg keymap-us-capslock-backspace tty-no-cursor-blink`
  - `clonepkg fzf-git fzf-extras pacnew_scripts pkgcacheclean`
  - `clonepkg cower downgrade icdiff pacaur repacman2 subrepo`
- Get dotfiles
  - `git clone https://github.com/atweiden/ttyfiles ~/.ttyfiles`
  - `cd ~/.ttyfiles`
  - `./bootstrap.sh`
  - `./fetch-gpg-keys.sh`
- Try sftp
  - `ssh-keygen -t ed25519 -b 521`
  - `sudo cp ~/.ssh/id_ed25519.pub /etc/ssh/authorized_keys/variable`
  - `sudo chmod 644 /etc/ssh/authorized_keys/variable`
  - `sudo systemctl start sshd`
  - `sftp $user-name-ssh@127.0.0.1`
