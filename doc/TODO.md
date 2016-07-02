- stuff that should be done with holo:
  - sudoers
  - hostname
  - DNSCrypt
  - locale
  - keymap
  - hwclock
  - tmpfiles.d
  - sleep.conf
  - modprobe.conf
  - mkinitcpio.conf
  - sysctl.conf
  - hidepid
  - securetty
  - iptables
  - ssh
  - power mgt
  - pkg suites
- stuff that should be done with holovault:
  - in general, anything that can't be customized in a file with autoconf
    style `@vars@` or LibraryMake style `%vars%`
    - timezone: pure symlink
    - chattrify
    - gpg key imports
- unresolved:
  - AUR pkgs?
  - vimplugs?
  - dotfiles?
  - hologram-base-disk-type-ssd?
  - hologram-base-graphics-nvidia?
  - hologram-base-graphics-radeon?
  - hologram-base-processor-intel?

- idea: add tests
- idea: check for active internet connection
- idea: exception handling
- idea: exceptions dump config to TOML file for easier recovery of bootstrap
- idea: Holovault parses Holo TOML definitions to learn AUR pkg
  dependencies
  - or use `mksrcinfo` and parse `.SRCINFO`
- idea: exit success/failure messages
- idea: make users double-check config settings in `dialog` menu before
  proceeding with installation
- idea: copytoram

- consider using:
  - https://github.com/kuerbis/Term-Choose-p6
  - https://github.com/wbiker/io-prompt
  - https://github.com/tadzik/Terminal-ANSIColor
