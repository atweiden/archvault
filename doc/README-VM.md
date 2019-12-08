# Virtualization Instructions

## VirtualBox 5.2.8

### Pre-Setup

**On host machine**:

- If your computer is low on memory, close all other programs besides
  VirtualBox
- Determine the fastest pacman mirrors for your location

### Setup

**On host machine**:

- Install VirtualBox and VirtualBox Extension Pack from Oracle
  - `brew cask install virtualbox virtualbox-extension-pack`
- Launch VirtualBox
- Change default Machine Folder
  - VirtualBox->Preferences->Default Machine Folder->`~/Documents/vboxen`
- New
  - Name: arch64
  - Type: Linux
  - Version: Arch Linux (64-bit)
  - Continue
  - Memory Size: 2048 MB
  - Continue
  - Create a virtual hard disk now
  - Create
  - VDI (VirtualBox Disk Image)
  - Continue
  - Dynamically allocated
  - Continue
  - File Size: 16 GB
  - Create
- With *arch64* selected in VirtualBox Manager, click *Settings*
  - Storage
    - Click the CD circle with the (+) sign
      - Choose disk
        - Navigate to official Arch Linux ISO
          - Open
  - Audio
    - Uncheck Enable Audio
  - Click OK
- Enable UEFI (optional)
  - With *arch64* selected in VirtualBox Manager, click *Settings*
    - System
      - Check Enable EFI (special OSes only)
    - Click OK
- With *arch64* selected in VirtualBox Manager, click *Start*

### Bootstrap Archvault

- Follow instructions from *Bootstrap Archvault* section at the bottom
  of this document

### Post-Setup

**On host machine**:

- Configure VirtualBox virtual machine to not use Arch Linux ISO
  - Storage
    - Find the official Arch Linux ISO
      - Right-click
        - Remove Attachment
- With *arch64* selected in VirtualBox Manager, click *Start*
- Follow instructions from *Post-Install* section at the bottom of
  this document

### Configure VirtualBox for Host-Guest SSH

#### Configure Port Forwarding

**On host machine**:

- `VBoxManage modifyvm arch64 --natpf1 "ssh,tcp,,3022,,22"`

#### Try Host-Guest SSH

**On guest machine**:

- Temporarily amend `/etc/ssh/sshd_config` to allow password
  authentication
  - `vim /etc/ssh/sshd_config`
    - `PasswordAuthentication yes`
- Start `sshd`
  - `systemctl start sshd`

**On host machine**:

- `sftp -P 3022 variable@127.0.0.1`
  - succeeds
- `ssh -p 3022 variable@127.0.0.1`
  - fails
    - only sftp is allowed

#### Configure SSH Pubkey Authentication for Host-Guest SSH

**On host machine**:

- Create SSH keypair
  - `mkdir ~/.ssh/vbox-arch64`
  - `ssh-keygen -t ed25519 -b 521 -f ~/.ssh/vbox-arch64/id_ed25519`
- Upload SSH pubkey to guest
  - `sftp -P 3022 variable@127.0.0.1`
    - `put /Users/user/.ssh/vbox-arch64/id_ed25519.pub`
    - `quit`

**On guest machine**:

- Stop `sshd`
  - `systemctl stop sshd`
- Disallow password authentication
  - `vim /etc/ssh/sshd_config`
    - `PasswordAuthentication no`
- Add uploaded SSH pubkey to `/etc/ssh/authorized_keys`
  - For fresh key
    - `mv /srv/ssh/jail/variable/id_ed25519.pub /etc/ssh/authorized_keys/variable`
  - For additional key
    - `cat /srv/ssh/jail/variable/id_ed25519.pub >> /etc/ssh/authorized_keys/variable`
- Start `sshd`
  `systemctl start sshd`

#### Try Passwordless Host-Guest SSH

**On host machine**:

- Try `sftp`
  - `sftp -P 3022 -i ~/.ssh/vbox-arch64/id_ed25519 variable@127.0.0.1`
    - succeeds
- Create shortcut in `~/.ssh/config` to make this easier:

```sshconfig
Host vbox-arch64
    HostName 127.0.0.1
    Port 3022
    IdentityFile ~/.ssh/vbox-arch64/id_ed25519
```

- Try `sftp` with shortcut
  - `sftp variable@vbox-arch64`
    - succeeds

### Configure VirtualBox for Increased Resolution

**On guest machine**:

- `vim /etc/default/grub`
  - Depending on host machine resolution
    - Check About This Mac->Displays
    - Either
      - Append `video=1360x768` to `GRUB_CMDLINE_LINUX`
      - Append `video=1440x900` to `GRUB_CMDLINE_LINUX`
    - Either
      - `GRUB_GFXMODE="1360x768x24"`
      - `GRUB_GFXMODE="1440x900x24"`
- `grub-mkconfig -o /boot/grub/grub.cfg`
- `shutdown now`

**On host machine**:

- Depending on host machine resolution
  - Either
    - `VBoxManage setextradata arch64 "CustomVideoMode1" "1360x768x24"`
    - `VBoxManage setextradata arch64 "CustomVideoMode1" "1440x900x24"`

### Configure VirtualBox for Bridged Networking

**On host machine**:

- With *arch64* selected in VirtualBox Manager, click *Settings*
  - Network->Adapter 1->Bridged Adapter
- With *arch64* selected in VirtualBox Manager, click *Start*

**On guest machine**:

Get connected:

```sh
ip link set <interface> up
dhcpcd <interface>
localip
```

You can now connect to the VirtualBox guest's `localip`, e.g.

```sh
ssh -vvv -N -T -i "$HOME/.ssh/vbox-arch64/id_ed25519" -D 9999 variable@192.168.3.121
```

## VMWare Fusion 10.1.1

### Pre-Setup

**On host machine**:

- If your computer is low on memory, close all other programs besides
  VMWare Fusion
- Determine the fastest pacman mirrors for your location

### Setup

**On host machine**:

- Install VMWare Fusion
- Launch VMWare Fusion
- Select File->New
- Drag and drop the official Arch Linux ISO into window from MacOS Finder
- Select Linux->Other Linux 4.x or later kernel 64-bit
- Select Legacy BIOS or UEFI
- Select Customize Settings
  - Processors and Memory
    - 1 processor core
    - Memory: 2048 MB
  - Isolation
    - uncheck Enable Drag and Drop
    - uncheck Enable Copy and Paste
- Press Play

### Bootstrap Archvault

- Follow instructions from *Bootstrap Archvault* section at the bottom
  of this document

### Post-Setup

**On host machine**:

- Configure VMWare Fusion virtual machine to not use Arch Linux ISO
  - Virtual Machine->Settings->CD/DVD (IDE)
    - Uncheck Connect CD/DVD Drive
- Configure VMWare Fusion virtual machine to pass battery status to guest
  - Virtual Machine->Settings->Advanced
    - Check Pass power status to VM
- Press Play
- Follow instructions from *Post-Install* section at the bottom of
  this document

### Configure VMWare Fusion for Host-Guest SSH

#### Configure Port Forwarding

**On guest machine**:

- Get IP address of VM
  - `ifconfig`
    - Note the `inet-addr`
      - Assume for sake of example it is `192.168.198.10`
- Shut down VM
  - `shutdown now`

**On host machine**:

- Edit `nat.conf`
  - `vim /Library/Preferences/VMware\ Fusion/vmnet8/nat.conf`

```dosini
[incomingtcp]
3022 = 192.168.198.10:22
```

The rest of the instructions are the same as with VirtualBox.

## Bootstrap Archvault

**On guest machine**:

- Press <kbd>Tab</kbd> when you see the boot loader screen, or
  <kbd>e</kbd> for UEFI machines
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
  - Add private Rakudo Perl 6 binary repo:

```dosini
[perl6]
SigLevel = PackageOptional
Server = https://github.com/atweiden/pkgbuilds/releases/download/latest
```

- Sync pacman mirrors
  - `pacman -Syy`
- Install Rakudo Perl 6
  - `pacman -S rakudo`
- Fetch Archvault sources
  - with Curl:
    - `curl -L -o '#1-#2.#3' https://github.com/atweiden/{archvault}/archive/{master}.{tar.gz}`
    - `tar xvzf archvault-master.tar.gz`
    - `cd archvault-master`
  - with Git:
    - `pacman -S git`
    - `git clone https://github.com/atweiden/archvault`
    - `cd archvault`
- Run Archvault
  - `export PATH="$(realpath bin):$PATH"`
  - `export PERL6LIB="$(realpath lib)"`
  - `archvault --help`
  - `archvault new`
- Follow the prompts as needed, let Archvault finish to completion
- Shutdown the LiveCD
  - `shutdown now`

## Post-Install

**On guest machine**:

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
  - `sudo pacman -Syy`
  - `sudo pacman -S colordiff ripgrep rlwrap sdcv the_silver_searcher tree`
  - `sudo pacman -S arch-wiki-docs arch-wiki-lite asp git mlocate pacmatic`
  - `sudo pacman -S fzf moreutils pwgen qrencode socat tor torsocks`
- Get AUR pkgs
  - `git clone https://aur.archlinux.org/clonepkg.git`
  - `cd clonepkg && makepkg -Acsi --noconfirm`
  - `clonepkg keymap-us-capslock-backspace tty-no-cursor-blink`
  - `clonepkg ccrypt fzf-extras ix pacnew_scripts pkgcacheclean`
  - `clonepkg diffr downgrade icdiff quixand repacman2 subrepo yay`
- Get console font
  - `clonepkg tamsyn-console-font`
  - `setfont Tamsyn10x20r`
  - `vim /etc/vconsole.conf`
    - `FONT=Tamsyn10x20r`
- Get Stardict dictionary/thesaurus
  - http://download.huzheng.org/bigdict/
    - /usr/share/stardict/dic
- Get dotfiles
  - `git clone https://github.com/atweiden/ttyfiles ~/.ttyfiles`
  - `cd ~/.ttyfiles`
  - `./bootstrap.sh`
  - `./fetch-pgp-keys.sh`
- Start systemd user services
  - This will only work after a reboot:
    - `userctl start kill-ssh-sessions`
    - `userctl enable kill-ssh-sessions`
- Try `sftp`
  - `ssh-keygen -t ed25519 -b 521`
  - `sudo cp ~/.ssh/id_ed25519.pub /etc/ssh/authorized_keys/variable`
  - `sudo systemctl start sshd`
  - `sftp variable@127.0.0.1`
