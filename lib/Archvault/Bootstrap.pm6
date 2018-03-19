use v6;
use Archvault::Config;
use Archvault::Types;
use Archvault::Utils;
unit class Archvault::Bootstrap;


# -----------------------------------------------------------------------------
# attributes
# -----------------------------------------------------------------------------

has Archvault::Config:D $.config is required;


# -----------------------------------------------------------------------------
# bootstrap
# -----------------------------------------------------------------------------

method bootstrap(::?CLASS:D: --> Nil)
{
    my Bool:D $augment = $.config.augment;

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
    self!disable-cow;
    self!augment if $augment;
    self!unmount;
}


# -----------------------------------------------------------------------------
# worker functions
# -----------------------------------------------------------------------------

method !setup(--> Nil)
{
    my Bool:D $reflector = $.config.reflector;

    # initialize pacman-keys
    run(qw<haveged -w 1024>);
    run(qw<pacman-key --init>);
    run(qw<pacman-key --populate archlinux>);
    run(qw<pkill haveged>);

    # fetch dependencies needed prior to pacstrap
    my Str:D @deps = qw<
        arch-install-scripts
        btrfs-progs
        cryptsetup
        dialog
        expect
        findutils
        gawk
        glibc
        gptfdisk
        kbd
        kmod
        openssl
        sed
        tzdata
        util-linux
    >;
    run(qw<pacman -Sy --needed --noconfirm>, @deps);

    # use readable font
    run(qw<setfont Lat2-Terminus16>);

    # optionally run reflector
    reflector() if $reflector;
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
    my DiskType:D $disk-type = $.config.disk-type;
    my Str:D $partition = $.config.partition;
    my VaultName:D $vault-name = $.config.vault-name;
    my VaultPass $vault-pass = $.config.vault-pass;

    # partition disk
    sgdisk($partition);

    # create vault
    mkvault($partition, $vault-name, :$vault-pass);

    # create and mount btrfs volumes
    mkbtrfs($disk-type, $vault-name);

    # create boot partition
    mkbootpart($partition);
}

# partition disk with gdisk
sub sgdisk(Str:D $partition --> Nil)
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
    Str:D $partition,
    VaultName:D $vault-name,
    VaultPass :$vault-pass
    --> Nil
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
    loop-cmdline-proc(
        'Creating LUKS vault...',
        $cryptsetup-luks-format-cmdline
    );

    # open LUKS encrypted volume, prompt user for vault password
    loop-cmdline-proc(
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
    my Str:D $sleep =
                'sleep 1';
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
        $sleep,
        $expect-are-you-sure-send-yes,
        $sleep,
        $expect-enter-send-vault-pass,
        $sleep,
        $expect-verify-send-vault-pass,
        $sleep,
        $expect-eof;

    my Str:D $cryptsetup-luks-format-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-format-cmdline);
        expect <<EOS
          %s
          %s
          %s
          %s
          %s
          %s
          %s
          %s
          %s
        EOS
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
    my Str:D $sleep =
                'sleep 1';
    my Str:D $expect-enter-send-vault-pass =
        sprintf('expect "Enter*" { send "%s\r" }', $vault-pass);
    my Str:D $expect-eof =
                'expect eof';

    my Str:D @cryptsetup-luks-open-cmdline =
        $spawn-cryptsetup-luks-open,
        $sleep,
        $expect-enter-send-vault-pass,
        $sleep,
        $expect-eof;

    my Str:D $cryptsetup-luks-open-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-open-cmdline);
        expect <<EOS
          %s
          %s
          %s
          %s
          %s
        EOS
        EOF
}

# create and mount btrfs volumes on open vault
sub mkbtrfs(DiskType:D $disk-type, VaultName:D $vault-name --> Nil)
{
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
sub mkbootpart(Str:D $partition --> Nil)
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
method !pacstrap-base(--> Nil)
{
    my Processor:D $processor = $.config.processor;
    my Bool:D $reflector = $.config.reflector;

    # base packages
    my Str:D @packages-base = qw<
        acpi
        arch-install-scripts
        base
        base-devel
        bash-completion
        btrfs-progs
        ca-certificates
        dhclient
        dialog
        dnscrypt-proxy
        ed
        ethtool
        expect
        gptfdisk
        grub-bios
        haveged
        ifplugd
        iproute2
        iw
        kbd
        net-tools
        nftables
        openresolv
        openssh
        rsync
        systemd-swap
        tmux
        unzip
        vim
        wget
        wireless_tools
        wpa_actiond
        wpa_supplicant
        zip
    >;

    # https://www.archlinux.org/news/changes-to-intel-microcodeupdates/
    push(@packages-base, 'intel-ucode') if $processor eq 'intel';
    push(@packages-base, 'reflector') if $reflector;

    # download and install packages with pacman in chroot
    run(qw<pacstrap /mnt>, @packages-base);
}

# secure user configuration
method !configure-users(--> Nil)
{
    my UserName:D $user-name-admin = $.config.user-name-admin;
    my UserName:D $user-name-ssh = $.config.user-name-ssh;
    my Str:D $user-pass-hash-admin = $.config.user-pass-hash-admin;
    my Str:D $user-pass-hash-root = $.config.user-pass-hash-root;
    my Str:D $user-pass-hash-ssh = $.config.user-pass-hash-ssh;
    configure-users('root', $user-pass-hash-root);
    configure-users('admin', $user-name-admin, $user-pass-hash-admin);
    configure-users('ssh', $user-name-ssh, $user-pass-hash-ssh);
}

multi sub configure-users(
    'admin',
    UserName:D $user-name-admin,
    Str:D $user-pass-hash-admin
    --> Nil
)
{
    useradd('admin', $user-name-admin, $user-pass-hash-admin);
    configure-sudoers($user-name-admin);
}

multi sub configure-users(
    'root',
    Str:D $user-pass-hash-root
    --> Nil
)
{
    usermod('root', $user-pass-hash-root);
}

multi sub configure-users(
    'ssh',
    UserName:D $user-name-ssh,
    Str:D $user-pass-hash-ssh
    --> Nil
)
{
    useradd('ssh', $user-name-ssh, $user-pass-hash-ssh);
}

multi sub useradd(
    'admin',
    UserName:D $user-name-admin,
    Str:D $user-pass-hash-admin
    --> Nil
)
{
    my Str:D $user-group-admin = qw<
        audio
        games
        log
        lp
        network
        optical
        power
        scanner
        storage
        users
        video
        wheel
    >.join(',');
    my Str:D $user-shell-admin = '/bin/bash';

    say("Creating new admin user named $user-name-admin...");
    run(qqw<arch-chroot /mnt groupadd $user-name-admin>);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -g $user-name-admin
        -G $user-group-admin
        -p $user-pass-hash-admin
        -s $user-shell-admin
        $user-name-admin
    >);
    chmod(0o700, "/mnt/home/$user-name-admin");
}

multi sub useradd(
    'dnscrypt',
    UserName:D $user-name-dnscrypt
    --> Nil
)
{
    my Str:D $user-home-dnscrypt = '/usr/share/dnscrypt-proxy';
    my Str:D $user-shell-dnscrypt = '/bin/false';

    say("Creating new DNSCrypt user named $user-name-dnscrypt...");
    run(qqw<arch-chroot /mnt groupadd $user-name-dnscrypt>);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -M
        -d $user-home-dnscrypt
        -g $user-name-dnscrypt
        -s $user-shell-dnscrypt
        $user-name-dnscrypt
    >);
}

multi sub useradd(
    'ssh',
    UserName:D $user-name-ssh,
    Str:D $user-pass-hash-ssh
    --> Nil
)
{
    # https://wiki.archlinux.org/index.php/SFTP_chroot
    my Str:D $user-group-ssh = 'sftponly';
    my Str:D $user-shell-ssh = '/sbin/nologin';
    my Str:D $auth-dir = '/etc/ssh/authorized_keys';
    my Str:D $jail-dir = '/srv/ssh/jail';
    my Str:D $home-dir = "$jail-dir/$user-name-ssh";
    my Str:D @root-dir = $auth-dir, $jail-dir;

    say("Creating new SSH user named $user-name-ssh...");
    arch-chroot-mkdir(@root-dir, 'root', 'root', 0o755);
    run(qqw<arch-chroot /mnt groupadd $user-group-ssh>);
    run(qqw<arch-chroot /mnt groupadd $user-name-ssh>);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -M
        -d $home-dir
        -g $user-name-ssh
        -G $user-group-ssh
        -p $user-pass-hash-ssh
        -s $user-shell-ssh
        $user-name-ssh
    >);
    arch-chroot-mkdir($home-dir, $user-name-ssh, $user-name-ssh, 0o700);
}

sub usermod(
    'root',
    Str:D $user-pass-hash-root
    --> Nil
)
{
    say('Updating root password...');
    run(qqw<arch-chroot /mnt usermod -p $user-pass-hash-root root>);
}

sub configure-sudoers(UserName:D $user-name-admin --> Nil)
{
    say("Giving sudo privileges to admin user $user-name-admin...");
    my Str:D $sudoers = qq:to/EOF/;
    $user-name-admin ALL=(ALL) ALL
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/reboot
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/shutdown
    EOF
    spurt('/mnt/etc/sudoers', "\n" ~ $sudoers, :append);
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
    my Str:D $user-name-dnscrypt = 'dnscrypt';
    useradd('dnscrypt', $user-name-dnscrypt);
    configure-dnscrypt-proxy('User', $user-name-dnscrypt);
    configure-dnscrypt-proxy('EphemeralKeys');
}

multi sub configure-dnscrypt-proxy(
    'User',
    UserName:D $user-name-dnscrypt
    --> Nil
)
{
    my Str:D $sed-cmd =
          q{s,}
        ~ q{^# User.*}
        ~ q{,}
        ~ qq{User $user-name-dnscrypt}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/dnscrypt-proxy.conf");
}

multi sub configure-dnscrypt-proxy('EphemeralKeys' --> Nil)
{
    my Str:D $sed-cmd =
          q{s,}
        ~ q{EphemeralKeys off}
        ~ q{,}
        ~ q{EphemeralKeys on}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/dnscrypt-proxy.conf");
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
    configure-pacman('CheckSpace');
    configure-pacman('ILoveCandy');
    configure-pacman('multilib') if $*KERNEL.bits == 64;
}

multi sub configure-pacman('CheckSpace' --> Nil)
{
    my Str:D $sed-cmd = 's/^#\h*\(CheckSpace\|Color\|TotalDownload\)$/\1/';
    shell("sed -i '$sed-cmd' /mnt/etc/pacman.conf");
}

multi sub configure-pacman('ILoveCandy' --> Nil)
{
    my Str:D $sed-cmd = '/^CheckSpace.*/a ILoveCandy';
    shell("sed -i '$sed-cmd' /mnt/etc/pacman.conf");
}

multi sub configure-pacman('multilib' --> Nil)
{
    my Str:D $sed-cmd = '/^#\h*\[multilib]/,/^\h*$/s/^#//';
    shell("sed -i '$sed-cmd' /mnt/etc/pacman.conf");
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
    configure-initramfs('MODULES', $graphics, $processor);
    configure-initramfs('HOOKS', $disk-type);
    configure-initramfs('FILES');
    run(qw<arch-chroot /mnt mkinitcpio -p linux>);
}

multi sub configure-initramfs(
    'MODULES',
    Graphics:D $graphics,
    Processor:D $processor
    --> Nil
)
{
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
}

multi sub configure-initramfs('HOOKS', DiskType:D $disk-type --> Nil)
{
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
    my Str:D $sed-cmd =
          q{s,}
        ~ q{^HOOKS.*}
        ~ q{,}
        ~ q{HOOKS=(} ~ @hooks.join(' ') ~ q{)}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/mkinitcpio.conf");
}

multi sub configure-initramfs('FILES' --> Nil)
{
    my Str:D $sed-cmd = 's,^FILES.*,FILES=(/etc/modprobe.d/modprobe.conf),';
    run(qqw<sed -i $sed-cmd /mnt/etc/mkinitcpio.conf>);
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
    my Graphics:D $graphics = $.config.graphics;
    my Str:D $partition = $.config.partition;
    my VaultName:D $vault-name = $.config.vault-name;
    configure-bootloader(
        'GRUB_CMDLINE_LINUX',
        $partition,
        $vault-name,
        $graphics
    );
    configure-bootloader('GRUB_DEFAULT');
    configure-bootloader('GRUB_SAVEDEFAULT');
    configure-bootloader('GRUB_ENABLE_CRYPTODISK');
    configure-bootloader('GRUB_DISABLE_SUBMENU');
    install-bootloader($partition);
}

multi sub configure-bootloader(
    'GRUB_CMDLINE_LINUX',
    Str:D $partition,
    VaultName:D $vault-name,
    Graphics:D $graphics
    --> Nil
)
{
    my Str:D $partition-vault = $partition ~ '3';
    my Str:D $vault-uuid = qqx<blkid -s UUID -o value $partition-vault>.trim;
    my Str:D $grub-cmdline-linux =
        "cryptdevice=/dev/disk/by-uuid/$vault-uuid:$vault-name"
            ~ ' rootflags=subvol=@';
    $grub-cmdline-linux ~= ' radeon.dpm=1' if $graphics eq 'RADEON';
    my Str:D $sed-cmd =
          q{s,}
        ~ q{^\(GRUB_CMDLINE_LINUX\)=.*}
        ~ q{,}
        ~ q{\1=\"} ~ $grub-cmdline-linux ~ q{\"}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/default/grub");
}

multi sub configure-bootloader('GRUB_DEFAULT' --> Nil)
{
    my Str:D $sed-cmd = 's,^\(GRUB_DEFAULT\)=.*,\1=saved,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);
}

multi sub configure-bootloader('GRUB_SAVEDEFAULT' --> Nil)
{
    my Str:D $sed-cmd = 's,^#\(GRUB_SAVEDEFAULT\),\1,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);
}

multi sub configure-bootloader('GRUB_ENABLE_CRYPTODISK' --> Nil)
{
    my Str:D $sed-cmd = 's,^#\(GRUB_ENABLE_CRYPTODISK\),\1,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);
}

multi sub configure-bootloader('GRUB_DISABLE_SUBMENU' --> Nil)
{
    my Str:D $grub-disable-submenu = q:to/EOF/;
    GRUB_DISABLE_SUBMENU=y
    EOF
    spurt('/mnt/etc/default/grub', "\n" ~ $grub-disable-submenu, :append);
}

sub install-bootloader(Str:D $partition --> Nil)
{
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
        configure-sysctl('vm.vfs_cache_pressure');
        configure-sysctl('vm.swappiness');
    }
    run(qw<arch-chroot /mnt sysctl --system>);
}

multi sub configure-sysctl('vm.vfs_cache_pressure' --> Nil)
{
    my Str:D $sed-cmd =
          q{s,}
        ~ q{^#\(vm.vfs_cache_pressure\).*}
        ~ q{,}
        ~ q{\1 = 50}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/sysctl.conf");
}

multi sub configure-sysctl('vm.swappiness' --> Nil)
{
    my Str:D $sed-cmd =
          q{s,}
        ~ q{^#\(vm.swappiness\).*}
        ~ q{,}
        ~ q{\1 = 1}
        ~ q{,};
    shell("sed -i '$sed-cmd' /mnt/etc/sysctl.conf");
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
    my UserName:D $user-name-ssh = $.config.user-name-ssh;

    copy(%?RESOURCES<etc/ssh/ssh_config>, '/mnt/etc/ssh/ssh_config');
    copy(%?RESOURCES<etc/ssh/sshd_config>, '/mnt/etc/ssh/sshd_config');

    # restrict allowed connections to $user-name-ssh
    my Str:D $sed-cmd = "3iAllowUsers $user-name-ssh";
    shell("sed -i '$sed-cmd' /mnt/etc/ssh/sshd_config");

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
        dnscrypt-proxy
        haveged
        nftables
        systemd-swap
    >;
    @service.map(-> $service {
        run(qqw<arch-chroot /mnt systemctl enable $service>);
    });
}

method !disable-cow(--> Nil)
{
    my Str:D @directory = '/mnt/var/log';
    my UInt:D $permissions = 0o755;
    my Str:D $user = 'root';
    my Str:D $group = 'root';
    Archvault::Utils.disable-cow(|@directory, :$permissions, :$user, :$group);
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


# -----------------------------------------------------------------------------
# helper functions
# -----------------------------------------------------------------------------

multi sub arch-chroot-mkdir(
    Str:D @dir,
    Str:D $user,
    Str:D $group,
    # permissions should be octal: https://doc.perl6.org/routine/chmod
    UInt:D $permissions
    --> Nil
)
{
    @dir.map({ arch-chroot-mkdir($_, $user, $group, $permissions) });
}

multi sub arch-chroot-mkdir(
    Str:D $dir,
    Str:D $user,
    Str:D $group,
    UInt:D $permissions
    --> Nil
)
{
    mkdir("/mnt/$dir");
    chmod($permissions, "/mnt/$dir");
    run(qqw<arch-chroot /mnt chown $user:$group $dir>);
}

sub loop-cmdline-proc(
    Str:D $message where *.so,
    Str:D $cmdline where *.so
    --> Nil
)
{
    loop
    {
        say($message);
        my Proc:D $proc = shell($cmdline);
        last if $proc.exitcode == 0;
    }
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0 nowrap:
