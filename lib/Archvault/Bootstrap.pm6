use v6;
use Archvault::Config;
use Archvault::Types;
unit class Archvault::Bootstrap;

has Archvault::Config:D $.config is required;

method bootstrap(::?CLASS:D: --> Nil)
{
    # verify root permissions
    $*USER == 0 or die('root privileges required');
    self!setup;
    self!mkdisk;
    self!pacstrap-base;
    self!configure-users;
    self!genfstab;
    self!set-hostname;
    self!configure-dhcpcd;
    self!configure-dnscrypt-proxy;
    self!set-nameservers;
    self!set-locale;
    self!set-keymap;
    self!set-timezone;
    self!set-hwclock;
    self!configure-tmpfiles;
    self!configure-pacman;
    self!configure-system-sleep;
    self!configure-modprobe;
    self!generate-initramfs;
    self!configure-io-schedulers;
    self!install-bootloader;
    self!configure-sysctl;
    self!configure-systemd;
    self!configure-hidepid;
    self!configure-securetty;
    self!configure-nftables;
    self!configure-openssh;
    self!configure-x11;
    self!enable-systemd-services;
    self!disable-btrfs-cow;
    self!augment if $.config.augment;
    self!unmount;
}

method !setup(--> Nil)
{
    # initialize pacman-keys
    run(qw<haveged -w 1024>);
    run(qw<pacman-key --init>);
    run(qw<pacman-key --populate archlinux>);
    run(qw<pkill haveged>);

    # fetch dependencies needed prior to pacstrap
    my Str:D @deps = qw<
        arch-install-scripts
        base-devel
        btrfs-progs
        expect
        gptfdisk
        kbd
        nftables
    >;
    run(qw<pacman -Sy --needed --noconfirm>, @deps);

    # use readable font
    run(qw<setfont Lat2-Terminus16>);

    # optionally run reflector
    reflector() if $.config.reflector;
}

sub reflector(--> Nil)
{
    run(qw<pacman -Sy --needed --noconfirm reflector>);

    # rank mirrors
    say('Running reflector to optimize pacman mirrors');
    rename('/etc/pacman.d/mirrorlist', '/etc/pacman.d/mirrorlist.bak');
    run(qw<
        reflector
        --threads 5
        --protocol https
        --fastest 7
        --number 7
        --save /etc/pacman.d/mirrorlist
    >);
}

# secure disk configuration
method !mkdisk(--> Nil)
{
    # partition disk
    self!sgdisk;

    # create vault
    self!mkvault;

    # create and mount btrfs volumes
    self!mkbtrfs;

    # create boot partition
    self!mkbootpart;
}

# partition disk with gdisk
method !sgdisk(--> Nil)
{
    my Str:D $partition = $.config.partition;

    # erase existing partition table
    # create 2MB EF02 BIOS boot sector
    # create 128MB sized partition for /boot
    # create max sized partition for LUKS encrypted volume
    run(qw<
        sgdisk
        --zap-all
        --clear
        --mbrtogpt
        --new=1:0:+2M
        --typecode=1:EF02
        --new=2:0:+128M
        --typecode=2:8300
        --new=3:0:0
        --typecode=3:8300
    >, $partition);
}

# create vault with cryptsetup
method !mkvault(--> Nil)
{
    # target partition for vault
    my Str:D $partition-vault = $.config.partition ~ '3';
    my VaultName:D $vault-name = $.config.vault-name;
    my VaultPass $vault-pass = $.config.vault-pass;

    # load kernel modules for cryptsetup
    run(qw<modprobe dm_mod dm-crypt>);

    mkvault-cryptsetup(:$partition-vault, :$vault-name, :$vault-pass);
}

# LUKS encrypted volume password was given
multi sub mkvault-cryptsetup(
    Str:D :$partition-vault where *.so,
    VaultName:D :$vault-name where *.so,
    VaultPass:D :$vault-pass where *.so
    --> Nil
)
{
    my Str:D $cryptsetup-luks-format-cmdline =
        build-cryptsetup-luks-format-cmdline(
            :non-interactive,
            $partition-vault,
            $vault-pass
        );

    my Str:D $cryptsetup-luks-open-cmdline =
        build-cryptsetup-luks-open-cmdline(
            :non-interactive,
            $partition-vault,
            $vault-name,
            $vault-pass
        );

    # make LUKS encrypted volume without prompt for vault password
    shell($cryptsetup-luks-format-cmdline);

    # open vault without prompt for vault password
    shell($cryptsetup-luks-open-cmdline);
}

# LUKS encrypted volume password not given
multi sub mkvault-cryptsetup(
    Str:D :$partition-vault where *.so,
    VaultName:D :$vault-name where *.so,
    VaultPass :vault-pass($)
    --> Nil
)
{
    my Str:D $cryptsetup-luks-format-cmdline =
        build-cryptsetup-luks-format-cmdline(
            :interactive,
            $partition-vault
        );

    my Str:D $cryptsetup-luks-open-cmdline =
        build-cryptsetup-luks-open-cmdline(
            :interactive,
            $partition-vault,
            $vault-name
        );

    # create LUKS encrypted volume, prompt user for vault password
    loop-cryptsetup-cmdline-proc(
        'Creating LUKS vault...',
        $cryptsetup-luks-format-cmdline
    );

    # open LUKS encrypted volume, prompt user for vault password
    loop-cryptsetup-cmdline-proc(
        'Opening LUKS vault...',
        $cryptsetup-luks-open-cmdline
    );
}

multi sub build-cryptsetup-luks-format-cmdline(
    Str:D $partition-vault where *.so,
    Bool:D :interactive($) where *.so
    --> Str:D
)
{
    my Str:D $spawn-cryptsetup-luks-format = qqw<
        spawn cryptsetup
        --cipher aes-xts-plain64
        --key-size 512
        --hash sha512
        --iter-time 5000
        --use-random
        --verify-passphrase
        luksFormat $partition-vault
    >.join(' ');
    my Str:D $expect-are-you-sure-send-yes =
        'expect "Are you sure*" { send "YES\r" }';
    my Str:D $interact = 'interact';
    my Str:D $catch-wait-result = 'catch wait result';
    my Str:D $exit-lindex-result = 'exit [lindex $result 3]';

    my Str:D @cryptsetup-luks-format-cmdline =
        $spawn-cryptsetup-luks-format,
        $expect-are-you-sure-send-yes,
        $interact,
        $catch-wait-result,
        $exit-lindex-result;

    my Str:D $cryptsetup-luks-format-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-format-cmdline);
        expect -c '%s;
                   %s;
                   %s;
                   %s;
                   %s'
        EOF
}

multi sub build-cryptsetup-luks-format-cmdline(
    Str:D $partition-vault where *.so,
    VaultPass:D $vault-pass where *.so,
    Bool:D :non-interactive($) where *.so
    --> Str:D
)
{
    my Str:D $spawn-cryptsetup-luks-format = qqw<
        spawn cryptsetup
        --cipher aes-xts-plain64
        --key-size 512
        --hash sha512
        --iter-time 5000
        --use-random
        --verify-passphrase
        luksFormat $partition-vault
    >.join(' ');
    my Str:D $expect-are-you-sure-send-yes =
                'expect "Are you sure*" { send "YES\r" }';
    my Str:D $expect-enter-send-vault-pass =
        sprintf('expect "Enter*" { send "%s\r" }', $vault-pass);
    my Str:D $expect-verify-send-vault-pass =
        sprintf('expect "Verify*" { send "%s\r" }', $vault-pass);
    my Str:D $expect-eof =
                'expect eof';

    my Str:D @cryptsetup-luks-format-cmdline =
        $spawn-cryptsetup-luks-format,
        $expect-are-you-sure-send-yes,
        $expect-enter-send-vault-pass,
        $expect-verify-send-vault-pass,
        $expect-eof;

    my Str:D $cryptsetup-luks-format-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-format-cmdline);
        expect <<'EOS'
          %s
          %s
          %s
          %s
          %s
        EOS);
        EOF
}

multi sub build-cryptsetup-luks-open-cmdline(
    Str:D $partition-vault where *.so,
    VaultName:D $vault-name where *.so,
    Bool:D :interactive($) where *.so
    --> Str:D
)
{
    my Str:D $cryptsetup-luks-open-cmdline =
        "cryptsetup luksOpen $partition-vault $vault-name";
}

multi sub build-cryptsetup-luks-open-cmdline(
    Str:D $partition-vault where *.so,
    VaultName:D $vault-name where *.so,
    VaultPass:D $vault-pass where *.so,
    Bool:D :non-interactive($) where *.so
    --> Str:D
)
{
    my Str:D $spawn-cryptsetup-luks-open =
        "spawn cryptsetup luksOpen $partition-vault $vault-name";
    my Str:D $expect-enter-send-vault-pass =
        sprintf('expect "Enter*" { send "%s\r" }', $vault-pass);
    my Str:D $expect-eof = 'expect eof';

    my Str:D @cryptsetup-luks-open-cmdline =
        $spawn-cryptsetup-luks-open,
        $expect-enter-send-vault-pass,
        $expect-eof;

    my Str:D $cryptsetup-luks-open-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-open-cmdline);
        expect <<'EOS'
          %s
          %s
          %s
        EOS
        EOF
}

sub loop-cryptsetup-cmdline-proc(
    Str:D $message where *.so,
    Str:D $cryptsetup-cmdline where *.so
    --> Nil
)
{
    loop
    {
        say($message);
        my Proc:D $cryptsetup = shell($cryptsetup-cmdline);

        # loop until passphrases match
        # - returns exit code 0 if success
        # - returns exit code 1 if SIGINT
        # - returns exit code 2 if wrong password
        last if $cryptsetup.exitcode == 0;
    }
}

# create and mount btrfs volumes on open vault
method !mkbtrfs(--> Nil)
{
    my DiskType:D $disk-type = $.config.disk-type;
    my VaultName:D $vault-name = $.config.vault-name;

    # create btrfs filesystem on opened vault
    run(qqw<mkfs.btrfs /dev/mapper/$vault-name>);

    # set mount options
    my Str:D $mount-options = 'rw,lazytime,compress=zstd,space_cache';
    $mount-options ~= ',ssd' if $disk-type eq 'SSD';

    # mount main btrfs filesystem on open vault
    mkdir('/mnt2');
    run(qqw<mount -t btrfs -o $mount-options /dev/mapper/$vault-name /mnt2>);

    # btrfs subvolumes, starting with root / ('')
    my Str:D @btrfs-dirs = '', 'home', 'opt', 'srv', 'tmp', 'usr', 'var';

    # create btrfs subvolumes
    chdir('/mnt2');
    @btrfs-dirs.map(-> $btrfs-dir {
        run(qqw<btrfs subvolume create @$btrfs-dir>);
    });
    chdir('/');

    # mount btrfs subvolumes
    @btrfs-dirs.map(-> $btrfs-dir {
        mkdir("/mnt/$btrfs-dir");
        run(qqw<
            mount
            -t btrfs
            -o $mount-options,subvol=@$btrfs-dir
            /dev/mapper/$vault-name
            /mnt/$btrfs-dir
        >);
    });

    # unmount /mnt2 and remove
    run(qw<umount /mnt2>);
    rmdir('/mnt2');
}

# create and mount boot partition
method !mkbootpart(--> Nil)
{
    # target partition for boot
    my Str:D $partition-boot = $.config.partition ~ '2';

    # create ext2 boot partition
    run(qqw<mkfs.ext2 $partition-boot>);

    # mount ext2 boot partition in /mnt/boot
    mkdir('/mnt/boot');
    run(qqw<mount $partition-boot /mnt/boot>);
}

# bootstrap initial chroot with pacstrap
method !pacstrap-base(--> Nil)
{
    my Processor:D $processor = $.config.processor;

    # base packages
    my Str:D @packages-base = qw<
        acpi
        arch-install-scripts
        asp
        base
        base-devel
        bash-completion
        btrfs-progs
        ca-certificates
        cronie
        dhclient
        dialog
        dnscrypt-proxy
        ed
        ethtool
        expect
        gptfdisk
        grub-bios
        haveged
        iproute2
        iw
        kbd
        kexec-tools
        net-tools
        nftables
        openresolv
        openssh
        reflector
        rsync
        sshpass
        systemd-swap
        tmux
        unzip
        wget
        wireless_tools
        wpa_actiond
        wpa_supplicant
        zip
        zsh
    >;

    # https://www.archlinux.org/news/changes-to-intel-microcodeupdates/
    push(@packages-base, 'intel-ucode') if $processor eq 'intel';

    # download and install packages with pacman in chroot
    run(qw<pacstrap /mnt>, @packages-base);
}

# secure user configuration
method !configure-users(--> Nil)
{
    self!configure-users-privileged;
    self!configure-users-unprivileged if $.config.add-users;
}

method !configure-users-privileged(--> Nil)
{
    say('Setting root password...');
    loop-mkpasswd('root');

    my UserName:D $user-name = $.config.user-name;
    say("Creating new privileged user named $user-name...");
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -s /bin/bash
        -g users
        -G audio,games,log,lp,network,optical,power,scanner,storage,video,wheel
        $user-name
    >);

    say("Setting password for the privileged user named $user-name...");
    loop-mkpasswd($user-name);

    say("Giving sudo privileges to the user named $user-name...");
    my Str:D $sudoers = qq:to/EOF/;
    $user-name ALL=(ALL) ALL
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/reboot
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/shutdown
    EOF
    spurt('/mnt/etc/sudoers', "\n" ~ $sudoers, :append);
}

method !configure-users-unprivileged(--> Nil)
{
    # NOTE: does not handle duplicate usernames
    $.config.user.sort.map(-> $user-name {
        say("Creating new unprivileged user named $user-name...");
        run(qqw<
            arch-chroot
            /mnt
            useradd
            -m
            -s /bin/bash
            -g users
            $user-name
        >);

        say("Setting password for the user named $user-name...");
        loop-mkpasswd($user-name);
    });
}

# modify user password on disk
sub loop-mkpasswd(Str:D $user-name --> Nil)
{
    loop
    {
        my Proc:D $passwd = shell("arch-chroot /mnt passwd $user-name");
        last if $passwd.exitcode == 0;
    }
}

method !genfstab(--> Nil)
{
    shell('genfstab -U -p /mnt >> /mnt/etc/fstab');
}

method !set-hostname(--> Nil)
{
    my HostName:D $host-name = $.config.host-name;
    spurt('/mnt/etc/hostname', $host-name ~ "\n");
}

method !configure-dhcpcd(--> Nil)
{
    my Str:D $dhcpcd = q:to/EOF/;
    # Set vendor-class-id to empty string
    vendorclassid
    EOF
    spurt('/mnt/etc/dhcpcd.conf', "\n" ~ $dhcpcd, :append);
}

method !configure-dnscrypt-proxy(--> Nil)
{
    # create dnscrypt user/group
    run(qw<arch-chroot /mnt groupadd dnscrypt>);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -d /usr/share/dnscrypt-proxy
        -g dnscrypt
        -s /bin/nologin
        dnscrypt
    >);

    # User {{{

    my Str:D $sed-cmd =
          q{s,}
        ~ q{^# User.*}
        ~ q{,}
        ~ q{User dnscrypt}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/dnscrypt-proxy.conf");

    # end User }}}

    $sed-cmd = '';

    # EphemeralKeys {{{

    $sed-cmd =
          q{s,}
        ~ q{EphemeralKeys off}
        ~ q{,}
        ~ q{EphemeralKeys on}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/dnscrypt-proxy.conf");

    # end EphemeralKeys }}}
}

method !set-nameservers(--> Nil)
{
    copy(%?RESOURCES<etc/resolv.conf.head>, '/mnt/etc/resolv.conf.head');
}

method !set-locale(--> Nil)
{
    my Locale:D $locale = $.config.locale;
    my Str:D $locale-fallback = $locale.substr(0, 2);

    my Str:D $sed-cmd =
          q{s,}
        ~ qq{^#\\($locale\\.UTF-8 UTF-8\\)}
        ~ q{,}
        ~ q{\1}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/locale.gen");
    run(qw<arch-chroot /mnt locale-gen>);

    my Str:D $locale-conf = qq:to/EOF/;
    LANG=$locale.UTF-8
    LANGUAGE=$locale:$locale-fallback
    LC_TIME=$locale.UTF-8
    EOF
    spurt('/mnt/etc/locale.conf', $locale-conf);
}

method !set-keymap(--> Nil)
{
    my Keymap:D $keymap = $.config.keymap;
    my Str:D $vconsole = qq:to/EOF/;
    KEYMAP=$keymap
    FONT=Lat2-Terminus16
    FONT_MAP=
    EOF
    spurt('/mnt/etc/vconsole.conf', $vconsole);
}

method !set-timezone(--> Nil)
{
    my Timezone:D $timezone = $.config.timezone;
    run(qqw<
        arch-chroot
        /mnt
        ln
        -sf /usr/share/zoneinfo/$timezone
        /etc/localtime
    >);
}

method !set-hwclock(--> Nil)
{
    run(qw<arch-chroot /mnt hwclock --systohc --utc>);
}

method !configure-tmpfiles(--> Nil)
{
    # https://wiki.archlinux.org/index.php/Tmpfs#Disable_automatic_mount
    run(qw<arch-chroot /mnt systemctl mask tmp.mount>);
    copy(%?RESOURCES<etc/tmpfiles.d/tmp.conf>, '/mnt/etc/tmpfiles.d/tmp.conf');
}

method !configure-pacman(--> Nil)
{
    my Str:D $sed-cmd = 's/^#\h*\(CheckSpace\|Color\|TotalDownload\)$/\1/';
    shell("sed -i '$sed-cmd' /mnt/etc/pacman.conf");

    $sed-cmd = '';

    $sed-cmd = '/^CheckSpace.*/a ILoveCandy';
    shell("sed -i '$sed-cmd' /mnt/etc/pacman.conf");

    $sed-cmd = '';

    if $*KERNEL.bits == 64
    {
        $sed-cmd = '/^#\h*\[multilib]/,/^\h*$/s/^#//';
        shell("sed -i '$sed-cmd' /mnt/etc/pacman.conf");
    }
}

method !configure-system-sleep(--> Nil)
{
    copy(%?RESOURCES<etc/systemd/sleep.conf>, '/mnt/etc/systemd/sleep.conf');
}

method !configure-modprobe(--> Nil)
{
    copy(
        %?RESOURCES<etc/modprobe.d/modprobe.conf>,
        '/mnt/etc/modprobe.d/modprobe.conf'
    );
}

method !generate-initramfs(--> Nil)
{
    my DiskType:D $disk-type = $.config.disk-type;
    my Graphics:D $graphics = $.config.graphics;
    my Processor:D $processor = $.config.processor;

    # MODULES {{{

    my Str:D @modules;
    push(@modules, $processor eq 'INTEL' ?? 'crc32c-intel' !! 'crc32c');
    push(@modules, 'i915') if $graphics eq 'INTEL';
    push(@modules, 'nouveau') if $graphics eq 'NVIDIA';
    push(@modules, 'radeon') if $graphics eq 'RADEON';
    # for systemd-swap lz4
    push(@modules, |qw<lz4 lz4_compress>);
    my Str:D $sed-cmd =
          q{s,}
        ~ q{^MODULES.*}
        ~ q{,}
        ~ q{MODULES=(} ~ @modules.join(' ') ~ q{)}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/mkinitcpio.conf");

    # end MODULES }}}

    $sed-cmd = '';

    # HOOKS {{{

    my Str:D @hooks = qw<
        base
        udev
        autodetect
        modconf
        keyboard
        keymap
        encrypt
        btrfs
        filesystems
        shutdown
        usr
    >;
    $disk-type eq 'USB'
        ?? @hooks.splice(2, 0, 'block')
        !! @hooks.splice(4, 0, 'block');
    $sed-cmd =
          q{s,}
        ~ q{^HOOKS.*}
        ~ q{,}
        ~ q{HOOKS=(} ~ @hooks.join(' ') ~ q{)}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/mkinitcpio.conf");

    # end HOOKS }}}

    $sed-cmd = '';

    # FILES {{{

    $sed-cmd = 's,^FILES.*,FILES=(/etc/modprobe.d/modprobe.conf),';
    run(qqw<sed -i $sed-cmd /mnt/etc/mkinitcpio.conf>);

    # end FILES }}}

    run(qw<arch-chroot /mnt mkinitcpio -p linux>);
}

method !configure-io-schedulers(--> Nil)
{
    mkdir('/mnt/etc/udev/rules.d');
    copy(
        %?RESOURCES<etc/udev/rules.d/60-io-schedulers.rules>,
        '/mnt/etc/udev/rules.d/60-io-schedulers.rules'
    );
}

method !install-bootloader(--> Nil)
{
    # GRUB_CMDLINE_LINUX {{{

    my Str:D $partition = $.config.partition;
    my Str:D $partition-vault = $partition ~ '3';
    my VaultName:D $vault-name = $.config.vault-name;
    my Str:D $vault-uuid = qqx<blkid -s UUID -o value $partition-vault>.trim;

    my Str:D $grub-cmdline-linux =
        "cryptdevice=/dev/disk/by-uuid/$vault-uuid:$vault-name"
            ~ ' rootflags=subvol=@';
    $grub-cmdline-linux ~= ' radeon.dpm=1' if $.config.graphics eq 'RADEON';

    my Str:D $sed-cmd =
          q{s,}
        ~ q{^\(GRUB_CMDLINE_LINUX\)=.*}
        ~ q{,}
        ~ q{\1=\"} ~ $grub-cmdline-linux ~ q{\"}
        ~ q{,};

    shell("sed -i '$sed-cmd' /mnt/etc/default/grub");

    # end GRUB_CMDLINE_LINUX }}}

    $sed-cmd = '';

    # GRUB_DEFAULT {{{

    $sed-cmd = 's,^\(GRUB_DEFAULT\)=.*,\1=saved,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);

    # end GRUB_DEFAULT }}}

    $sed-cmd = '';

    # GRUB_SAVEDEFAULT {{{

    $sed-cmd = 's,^#\(GRUB_SAVEDEFAULT\),\1,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);

    # end GRUB_SAVEDEFAULT }}}

    $sed-cmd = '';

    # GRUB_ENABLE_CRYPTODISK {{{

    $sed-cmd = 's,^#\(GRUB_ENABLE_CRYPTODISK\),\1,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);

    # end GRUB_ENABLE_CRYPTODISK }}}

    # GRUB_DISABLE_SUBMENU {{{

    my Str:D $grub-disable-submenu = q:to/EOF/;
    GRUB_DISABLE_SUBMENU=y
    EOF
    spurt('/mnt/etc/default/grub', "\n" ~ $grub-disable-submenu, :append);

    # end GRUB_DISABLE_SUBMENU }}}

    run(qw<
        arch-chroot
        /mnt
        grub-install
        --target=i386-pc
        --recheck
    >, $partition);
    run(qw<
        arch-chroot
        /mnt
        cp
        /usr/share/locale/en@quot/LC_MESSAGES/grub.mo
        /boot/grub/locale/en.mo
    >);
    run(qw<
        arch-chroot
        /mnt
        grub-mkconfig
        -o /boot/grub/grub.cfg
    >);
}

method !configure-sysctl(--> Nil)
{
    my DiskType:D $disk-type = $.config.disk-type;

    copy(%?RESOURCES<etc/sysctl.conf>, '/mnt/etc/sysctl.conf');

    if $disk-type eq 'SSD' || $disk-type eq 'USB'
    {
        my Str:D $sed-cmd =
              q{s,}
            ~ q{^#\(vm.vfs_cache_pressure\).*}
            ~ q{,}
            ~ q{\1 = 50}
            ~ q{,};
        shell("sed -i '$sed-cmd' /mnt/etc/sysctl.conf");

        $sed-cmd = '';

        $sed-cmd =
              q{s,}
            ~ q{^#\(vm.swappiness\).*}
            ~ q{,}
            ~ q{\1 = 1}
            ~ q{,};
        shell("sed -i '$sed-cmd' /mnt/etc/sysctl.conf");
    }

    run(qw<arch-chroot /mnt sysctl --system>);
}

method !configure-systemd(--> Nil)
{
    mkdir('/mnt/etc/systemd/system.conf.d');
    copy(
        %?RESOURCES</etc/systemd/system.conf.d/limits.conf>,
        '/mnt/etc/systemd/system.conf.d/limits.conf'
    );
}

method !configure-hidepid(--> Nil)
{
    mkdir('/mnt/etc/systemd/system/systemd-logind.service.d');
    copy(
        %?RESOURCES</etc/systemd/system/systemd-logind.service.d/hidepid.conf>,
        '/mnt/etc/systemd/system/systemd-logind.service.d/hidepid.conf'
    );

    my Str:D $fstab-hidepid = q:to/EOF/;
    # /proc with hidepid (https://wiki.archlinux.org/index.php/Security#hidepid)
    proc                                      /proc       procfs      hidepid=2,gid=proc                                              0 0
    EOF
    spurt('/mnt/etc/fstab', "\n" ~ $fstab-hidepid, :append);
}

method !configure-securetty(--> Nil)
{
    copy(%?RESOURCES<etc/securetty>, '/mnt/etc/securetty');
    copy(
        %?RESOURCES<etc/profile.d/shell-timeout.sh>,
        '/mnt/etc/profile.d/shell-timeout.sh'
    );
}

method !configure-nftables(--> Nil)
{
    # XXX: customize nftables
    Nil;
}

method !configure-openssh(--> Nil)
{
    my UserName:D $user-name = $.config.user-name;

    copy(%?RESOURCES<etc/ssh/ssh_config>, '/mnt/etc/ssh/ssh_config');
    copy(%?RESOURCES<etc/ssh/sshd_config>, '/mnt/etc/ssh/sshd_config');

    my Str:D $allow-users = qq:to/EOF/;
    AllowUsers $user-name
    EOF
    spurt('/mnt/etc/ssh/sshd_config', "\n" ~ $allow-users, :append);

    # restrict allowed connections to LAN
    copy(%?RESOURCES<etc/hosts.allow>, '/mnt/etc/hosts.allow');

    # filter weak ssh moduli
    shell(q{awk -i inplace '$5 > 2000' /mnt/etc/ssh/moduli});
}

method !configure-x11(--> Nil)
{
    mkdir('/mnt/etc/X11/xorg.conf.d');
    copy(
        %?RESOURCES<etc/X11/xorg.conf.d/20-natural-scrolling.conf>,
        '/mnt/etc/X11/xorg.conf.d/20-natural-scrolling.conf'
    );
    copy(
        %?RESOURCES<etc/X11/xorg.conf.d/99-security.conf>,
        '/mnt/etc/X11/xorg.conf.d/99-security.conf'
    );
}

method !enable-systemd-services(--> Nil)
{
    my Str:D @service = qw<
        cronie
        dnscrypt-proxy
        haveged
        nftables
        systemd-swap
    >;
    @service.map(-> $service {
        run(qqw<arch-chroot /mnt systemctl enable $service>);
    });
}

method !disable-btrfs-cow(--> Nil)
{
    chattrify('/mnt/var/log', 0o755, 'root', 'root');
}

sub chattrify(
    Str:D $directory where *.so,
    # permissions should be octal: https://doc.perl6.org/routine/chmod
    UInt:D $permissions,
    Str:D $user where *.so,
    Str:D $group where *.so
    --> Nil
)
{
    my Str:D $orig-dir = ~$directory.IO.resolve;
    $orig-dir.IO.e && $orig-dir.IO.r && $orig-dir.IO.d
        or die('directory failed exists readable directory test');

    my Str:D $backup-dir = $orig-dir ~ '-old';

    rename($orig-dir, $backup-dir);
    mkdir($orig-dir);
    chmod($permissions, $orig-dir);
    run(qqw<chattr +C $orig-dir>);
    dir($backup-dir).race.map(-> $file {
        run(qqw<cp -dpr --no-preserve=ownership $file $orig-dir>)
    });
    run(qqw<chown -R $user:$group $orig-dir>);
    run(qqw<rm -rf $backup-dir>);
}

# interactive console
method !augment(--> Nil)
{
    # launch fully interactive Bash console, type 'exit' to exit
    shell('expect -c "spawn /bin/bash; interact"');
}

method !unmount(--> Nil)
{
    shell('umount /mnt/{boot,home,opt,srv,tmp,usr,var,}');
    my VaultName:D $vault-name = $.config.vault-name;
    run(qqw<cryptsetup luksClose $vault-name>);
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0 nowrap:
