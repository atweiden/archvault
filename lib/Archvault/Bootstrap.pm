use v6;
unit module Archvault::Bootstrap;

sub bootstrap() is export
{
    setup();
    mkdisk();
    pacstrap-base();
    configure-users();
    genfstab();
    set-hostname();
    configure-dnscrypt-proxy();
    set-nameservers();
    set-locale();
    set-keymap();
    set-timezone();
    set-hwclock();
    configure-tmpfiles();
    configure-pacman();
    configure-system-sleep();
    configure-modprobe();
    generate-initramfs();
    configure-io-schedulers();
    install-bootloader();
    configure-sysctl();
    configure-hidepid();
    configure-securetty();
    configure-iptables();
    enable-systemd-services();
    disable-btrfs-cow();
    augment() if $Archvault::CONF.augment;
    unmount();
}

sub setup()
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
        iptables
        kbd
        reflector
    >;
    run(qw<pacman -Sy --needed --noconfirm>, @deps);

    # use readable font
    run(qw<setfont Lat2-Terminus16>);

    # rank mirrors
    rename('/etc/pacman.d/mirrorlist', '/etc/pacman.d/mirrorlist.bak');
    run(qw<
        reflector
        --threads 3
        --protocol https
        --fastest 8
        --number 8
        --save /etc/pacman.d/mirrorlist
    >);
}

# secure disk configuration
sub mkdisk()
{
    # partition disk
    sgdisk();

    # create vault
    mkvault();

    # create and mount btrfs volumes
    mkbtrfs();

    # create boot partition
    mkbootpart();
}

# partition disk with gdisk
sub sgdisk(Str:D :$partition = $Archvault::CONF.partition)
{
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
sub mkvault(
    Str:D :$partition = $Archvault::CONF.partition,
    Str:D :$vault-name = $Archvault::CONF.vault-name,
    Str :$vault-pass = $Archvault::CONF.vault-pass
)
{
    # target partition for vault
    my Str:D $partition-vault = $partition ~ '3';

    # load kernel modules for cryptsetup
    run(qw<modprobe dm_mod dm-crypt>);

    mkvault-cryptsetup(:$partition-vault, :$vault-name, :$vault-pass);
}

# LUKS encrypted volume password was given
multi sub mkvault-cryptsetup(
    Str:D :$partition-vault where *.so,
    Str:D :$vault-name where *.so,
    Str:D :$vault-pass where *.so
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
    Str:D :$vault-name where *.so,
    Str :vault-pass($)
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
    Bool:D :interactive($) where *.so,
    Str:D $partition-vault
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
    Bool:D :non-interactive($) where *.so,
    Str:D $partition-vault,
    Str:D $vault-pass
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
    Bool:D :interactive($) where *.so,
    Str:D $partition-vault,
    Str:D $vault-name
    --> Str:D
)
{
    my Str:D $cryptsetup-luks-open-cmdline =
        "cryptsetup luksOpen $partition-vault $vault-name";
}

multi sub build-cryptsetup-luks-open-cmdline(
    Bool:D :non-interactive($) where *.so,
    Str:D $partition-vault,
    Str:D $vault-name,
    Str:D $vault-pass
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

sub loop-cryptsetup-cmdline-proc(Str:D $message, Str:D $cryptsetup-cmdline)
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
sub mkbtrfs(Str:D :$vault-name = $Archvault::CONF.vault-name)
{
    # create btrfs filesystem on opened vault
    run(qqw<mkfs.btrfs /dev/mapper/$vault-name>);

    # set mount options
    my Str:D $mount-options = 'rw,lazytime,compress=zstd,space_cache';
    $mount-options ~= ',ssd' if $Archvault::CONF.disk-type eq 'SSD';

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
sub mkbootpart(Str:D :$partition = $Archvault::CONF.partition)
{
    # target partition for boot
    my Str:D $partition-boot = $partition ~ '2';

    # create ext2 boot partition
    run(qqw<mkfs.ext2 $partition-boot>);

    # mount ext2 boot partition in /mnt/boot
    mkdir('/mnt/boot');
    run(qqw<mount $partition-boot /mnt/boot>);
}

# bootstrap initial chroot with pacstrap
sub pacstrap-base()
{
    # base packages
    my Str:D @packages-base = qw<
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
        iptables
        iw
        kbd
        kexec-tools
        net-tools
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
    push(@packages-base, 'intel-ucode') if $Archvault::CONF.processor eq 'intel';

    # download and install packages with pacman in chroot
    run(qw<pacstrap /mnt>, @packages-base);
}

# secure user configuration
sub configure-users()
{
    # updating root password...
    my Str:D $root-pass-digest = $Archvault::CONF.root-pass-digest;
    run(qqw<arch-chroot /mnt usermod -p $root-pass-digest root>);

    # creating new user with password from secure password digest...
    my Str:D $user-name = $Archvault::CONF.user-name;
    my Str:D $user-pass-digest = $Archvault::CONF.user-pass-digest;
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -p $user-pass-digest
        -s /bin/bash
        -g users
        -G audio,games,log,lp,network,optical,power,scanner,storage,video,wheel
        $user-name
    >);

    my Str:D $sudoers = qq:to/EOF/;
    $user-name ALL=(ALL) ALL
    EOF
    spurt('/mnt/etc/sudoers', $sudoers, :append);
}

sub genfstab()
{
    shell('genfstab -U -p /mnt >> /mnt/etc/fstab');
}

sub set-hostname()
{
    spurt('/mnt/etc/hostname', $Archvault::CONF.host-name);
}

sub configure-dnscrypt-proxy()
{
    # create user _dnscrypt
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -d /usr/share/dnscrypt-proxy
        -g dnscrypt
        -s /bin/nologin
        _dnscrypt
    >);

    # User {{{

    my Str:D $sed-cmd =
          q{s,}
        ~ q{^# User.*}
        ~ q{,}
        ~ q{User _dnscrypt}
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

sub set-nameservers()
{
    copy(%?RESOURCES<etc/resolv.conf.head>, '/mnt/etc/resolv.conf.head');
}

sub set-locale()
{
    my Str:D $locale = $Archvault::CONF.locale;

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
    LC_TIME=$locale.UTF-8
    EOF
    spurt('/mnt/etc/locale.conf', $locale-conf);
}

sub set-keymap()
{
    my Str:D $keymap = $Archvault::CONF.keymap;
    my Str:D $vconsole = qq:to/EOF/;
    KEYMAP=$keymap
    FONT=Lat2-Terminus16
    FONT_MAP=
    EOF
    spurt('/mnt/etc/vconsole.conf', $vconsole);
}

sub set-timezone()
{
    run(qqw<
        arch-chroot
        /mnt
        ln
        -s /usr/share/zoneinfo/{$Archvault::CONF.timezone}
        /etc/localtime
    >);
}

sub set-hwclock()
{
    run(qw<arch-chroot /mnt hwclock --systohc --utc>);
}

sub configure-tmpfiles()
{
    # https://wiki.archlinux.org/index.php/Tmpfs#Disable_automatic_mount
    run(qw<arch-chroot /mnt systemctl mask tmp.mount>);
    copy(%?RESOURCES<etc/tmpfiles.d/tmp.conf>, '/mnt/etc/tmpfiles.d/tmp.conf');
}

sub configure-pacman()
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

sub configure-system-sleep()
{
    copy(%?RESOURCES<etc/systemd/sleep.conf>, '/mnt/etc/systemd/sleep.conf');
}

sub configure-modprobe()
{
    copy(
        %?RESOURCES<etc/modprobe.d/modprobe.conf>,
        '/mnt/etc/modprobe.d/modprobe.conf'
    );
}

sub generate-initramfs()
{
    # MODULES {{{

    my Str:D @modules;
    push(
        @modules,
        $Archvault::CONF.processor eq 'INTEL' ?? 'crc32c-intel' !! 'crc32c'
    );
    push(@modules, 'i915') if $Archvault::CONF.graphics eq 'INTEL';
    push(@modules, 'nouveau') if $Archvault::CONF.graphics eq 'NVIDIA';
    push(@modules, 'radeon') if $Archvault::CONF.graphics eq 'RADEON';
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
    $Archvault::CONF.disk-type eq 'USB'
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

sub configure-io-schedulers()
{
    mkdir('/mnt/etc/udev/rules.d');
    copy(
        %?RESOURCES<etc/udev/rules.d/60-io-schedulers.rules>,
        '/mnt/etc/udev/rules.d/60-io-schedulers.rules'
    );
}

sub install-bootloader()
{
    # GRUB_CMDLINE_LINUX {{{

    my Str:D $vault-name = $Archvault::CONF.vault-name;
    my Str:D $vault-uuid = qqx<
        blkid -s UUID -o value {$Archvault::CONF.partition}3
    >.trim;

    my Str:D $grub-cmdline-linux =
        "cryptdevice=/dev/disk/by-uuid/$vault-uuid:$vault-name"
            ~ ' rootflags=subvol=@';
    $grub-cmdline-linux ~= ' radeon.dpm=1'
        if $Archvault::CONF.graphics eq 'RADEON';

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

    spurt('/mnt/etc/default/grub', 'GRUB_DISABLE_SUBMENU=y', :append);

    # end GRUB_DISABLE_SUBMENU }}}

    run(qw<
        arch-chroot
        /mnt
        grub-install
        --target=i386-pc
        --recheck
    >, $Archvault::CONF.partition);
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

sub configure-sysctl()
{
    copy(%?RESOURCES<etc/sysctl.conf>, '/mnt/etc/sysctl.conf');

    if $Archvault::CONF.disk-type eq 'SSD'
        || $Archvault::CONF.disk-type eq 'USB'
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

    run(qw<arch-chroot /mnt sysctl -p>);
}

sub configure-hidepid()
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
    spurt('/mnt/etc/fstab', $fstab-hidepid, :append);
}

sub configure-securetty()
{
    my Str:D $securetty = q:to/EOF/;
    #
    # /etc/securetty
    # https://wiki.archlinux.org/index.php/Security#Denying_console_login_as_root
    #

    console
    #tty1
    #tty2
    #tty3
    #tty4
    #tty5
    #tty6
    #ttyS0
    #hvc0

    # End of file
    EOF
    spurt('/mnt/etc/securetty', $securetty);

    my Str:D $shell-timeout = q:to/EOF/;
    TMOUT="$(( 60*10 ))";
    [[ -z "$DISPLAY" ]] && export TMOUT;
    case $( /usr/bin/tty ) in
      /dev/tty[0-9]*) export TMOUT;;
    esac
    EOF
    spurt('/mnt/etc/profile.d/shell-timeout.sh', $shell-timeout);
}

sub configure-iptables()
{
    my Str:D $iptables-test-rules = q:to/EOF/;
    *filter
    #| Allow all loopback (lo0) traffic, and drop all traffic to 127/8 that doesn't use lo0
    -A INPUT -i lo -j ACCEPT
    -A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT
    #| Allow all established inbound connections
    -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    #| Allow all outbound traffic
    -A OUTPUT -j ACCEPT
    #| Allow HTTP and HTTPS connections
    -A INPUT -p tcp --dport 80 -j ACCEPT
    -A INPUT -p tcp --dport 443 -j ACCEPT
    #| Allow SSH connections
    -A INPUT -p tcp -m conntrack --ctstate NEW --dport 22 -j ACCEPT
    #| Allow ZeroMQ connections
    -A INPUT -p tcp -m conntrack --ctstate NEW --dport 4505 -j ACCEPT
    -A INPUT -p tcp -m conntrack --ctstate NEW --dport 4506 -j ACCEPT
    #| Allow NTP connections
    -I INPUT -p udp --dport 123 -j ACCEPT
    -I OUTPUT -p udp --sport 123 -j ACCEPT
    #| Reject pings
    -I INPUT -j DROP -p icmp --icmp-type echo-request
    #| Drop ident server
    -A INPUT -p tcp --dport ident -j DROP
    #| Log iptables denied calls
    -A INPUT -m limit --limit 15/minute -j LOG --log-prefix "[IPT]Dropped input: " --log-level 7
    -A OUTPUT -m limit --limit 15/minute -j LOG --log-prefix "[IPT]Dropped output: " --log-level 7
    #| Reject all other inbound - default deny unless explicitly allowed policy
    -A INPUT -j REJECT
    -A FORWARD -j REJECT
    COMMIT
    EOF
    spurt('iptables.test.rules', $iptables-test-rules);

    shell('iptables-save > /mnt/etc/iptables/iptables.up.rules');
    shell('iptables-restore < iptables.test.rules');
    shell('iptables-save > /mnt/etc/iptables/iptables.rules');
}

sub enable-systemd-services()
{
    my Str:D @service = qw<
        cronie
        dnscrypt-proxy
        haveged
        iptables
        systemd-swap
    >;
    @service.map(-> $service {
        run(qqw<arch-chroot /mnt systemctl enable $service>);
    });
}

sub disable-btrfs-cow()
{
    chattrify('/mnt/var/log', 0o755, 'root', 'root');
}

sub chattrify(
    Str:D $directory where *.so,
    # permissions should be octal: https://doc.perl6.org/routine/chmod
    UInt:D $permissions,
    Str:D $user where *.so,
    Str:D $group where *.so
)
{
    my Str:D $orig-dir = ~$directory.IO.resolve;
    die 'directory failed exists readable directory test'
        unless $orig-dir.IO.e && $orig-dir.IO.r && $orig-dir.IO.d;

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
sub augment()
{
    # launch fully interactive Bash console, type 'exit' to exit
    shell('expect -c "spawn /bin/bash; interact"');
}

sub unmount()
{
    shell('umount /mnt/{boot,home,opt,srv,tmp,usr,var,}');
    my Str:D $vault-name = $Archvault::CONF.vault-name;
    run(qqw<cryptsetup luksClose $vault-name>);
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
