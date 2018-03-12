## idea: `archvault new [profile]`

- `archvault new amnesia`
  - https://tails.boum.org/contribute/design/memory_erasure/
- `archvault new default`
- `archvault new iso`
- `archvault new secureboot`
- use class name variable interpolation
  - `unit role Archvault::Profile`
  - `Archvault::Profile::Amnesia does Archvault::Profile`
  - `Archvault::Profile::Default does Archvault::Profile`
  - `Archvault::Profile::ISO does Archvault::Profile`
  - `Archvault::Profile::SecureBoot does Archvault::Profile`
  - `Archvault::Profile::{$profile}.new`

## idea: implement improved password digest generation in Config.pm6

add `archvault gen-pass-digest` functionality with this

#### generating password digest

**dovecot**

```sh
doveadm pw -s SHA512-CRYPT -r 1000000 | sed 's/.*}//'
```

```perl6
my Str:D $hash =
    qx<doveadm pw -s SHA512-CRYPT -r 1000000>
    .trim
    .subst(/^'{SHA512-CRYPT}'/, '');
```

**python**

```sh
# python3.6
python -c 'import crypt,getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512)))'

# python3.7 adds ability to specify number of rounds in mksalt
python -c 'import crypt,getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512, 1000000)))'
```

#### configuring system

```sh
echo "${name}:${digest}" | chpasswd -e
```

## other ideas

- add tests
  - qemu
- check for active internet connection
- exception handling
- write progress to TOML file for easier recovery of bootstrap
  - handle being killed by OS because out of memory
    - start section
    - end section
- `archvault open <vaultname> <device>`
  - `archvault open vault /dev/sdb`
- `archvault close <vaultname>`
  - for when the bootstrap fails
  - `umount /mnt/{boot,home,opt,srv,tmp,usr,var,}`;
  - `cryptsetup luksClose $vaultname`
- exit success/failure messages
- make users double-check config settings in `dialog` menu before
  proceeding with installation
- copytoram
- use ntp
  - `timedatectl set-ntp true`
- grubshift
  - https://github.com/oconnor663/arch/blob/master/grubshift.sh
- consider using:
  - https://github.com/kuerbis/Term-Choose-p6
  - https://github.com/wbiker/io-prompt
  - https://github.com/tadzik/Terminal-ANSIColor
