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
    self!disable-cow;
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
    self!configure-pacman;
    self!configure-modprobe;
    self!generate-initramfs;
    self!install-bootloader;
    self!configure-sysctl;
    self!configure-nftables;
    self!configure-openssh;
    self!configure-systemd;
    self!configure-hidepid;
    self!configure-securetty;
    self!configure-xorg;
    self!enable-systemd-services;
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
    my Str:D @dep = qw<
        arch-install-scripts
        btrfs-progs
        coreutils
        cryptsetup
        dialog
        e2fsprogs
        expect
        findutils
        gawk
        glibc
        gptfdisk
        grub
        haveged
        kbd
        kmod
        openssl
        pacman
        procps-ng
        sed
        tzdata
        util-linux
    >;

    my Str:D $pacman-dep-cmdline =
        sprintf('pacman -Sy --needed --noconfirm %s', @dep.join(' '));
    loop-cmdline-proc(
        'Installing dependencies...',
        $pacman-dep-cmdline
    );

    # use readable font
    run(qw<setfont Lat2-Terminus16>);

    # optionally run reflector
    reflector() if $reflector;
}

sub reflector(--> Nil)
{
    my Str:D $pacman-reflector-cmdline =
        'pacman -Sy --needed --noconfirm reflector';
    loop-cmdline-proc(
        'Installing reflector...',
        $pacman-reflector-cmdline
    );

    # rank mirrors
    rename('/etc/pacman.d/mirrorlist', '/etc/pacman.d/mirrorlist.bak');
    my Str:D $reflector-cmdline = qw<
        reflector
        --threads 5
        --protocol https
        --fastest 7
        --number 7
        --save /etc/pacman.d/mirrorlist
    >.join(' ');
    loop-cmdline-proc(
        'Running reflector to optimize pacman mirrors',
        $reflector-cmdline
    );
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
}

# partition disk with gdisk
sub sgdisk(Str:D $partition --> Nil)
{
    # erase existing partition table
    # create 2MB EF02 BIOS boot sector
    # create max sized partition for LUKS encrypted volume
    run(qw<
        sgdisk
        --zap-all
        --clear
        --mbrtogpt
        --new=1:0:+2M
        --typecode=1:EF02
        --new=2:0:0
        --typecode=2:8300
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
    my Str:D $partition-vault = $partition ~ '2';

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
    my Str:D $interact =
        'interact';
    my Str:D $catch-wait-result =
        'catch wait result';
    my Str:D $exit-lindex-result =
        'exit [lindex $result 3]';

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
                'sleep 0.33';
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
                'sleep 0.33';
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
    my Str:D $mount-options = 'rw,lazytime,compress=lzo,space_cache';
    $mount-options ~= ',ssd' if $disk-type eq 'SSD';

    # mount main btrfs filesystem on open vault
    mkdir('/mnt2');
    run(qqw<mount -t btrfs -o $mount-options /dev/mapper/$vault-name /mnt2>);

    # btrfs subvolumes, starting with root / ('')
    my Str:D @btrfs-dir =
        '',
        'boot',
        'home',
        'opt',
        'srv',
        'usr',
        'var',
        'var-cache-pacman',
        'var-lib-ex',
        'var-lib-postgres',
        'var-log',
        'var-opt',
        'var-spool',
        'var-tmp';

    # create btrfs subvolumes
    chdir('/mnt2');
    @btrfs-dir.map(-> $btrfs-dir {
        run(qqw<btrfs subvolume create @$btrfs-dir>);
    });
    chdir('/');

    # mount btrfs subvolumes
    @btrfs-dir.map(-> $btrfs-dir {
        mount-btrfs-subvolume($btrfs-dir, $mount-options, $vault-name);
    });

    # unmount /mnt2 and remove
    run(qw<umount /mnt2>);
    rmdir('/mnt2');
}

multi sub mount-btrfs-subvolume(
    'srv',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'srv';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,nodev,noexec,nosuid,subvol=@$btrfs-dir
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

multi sub mount-btrfs-subvolume(
    'var-cache-pacman',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/cache/pacman';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,subvol=@var-cache-pacman
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

multi sub mount-btrfs-subvolume(
    'var-lib-ex',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/lib/ex';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,nodev,noexec,nosuid,subvol=@var-lib-ex
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
    run(qqw<chmod 1777 /mnt/$btrfs-dir>);
}

multi sub mount-btrfs-subvolume(
    'var-lib-postgres',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/lib/postgres';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,subvol=@var-lib-postgres
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

multi sub mount-btrfs-subvolume(
    'var-log',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/log';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,nodev,noexec,nosuid,subvol=@var-log
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

multi sub mount-btrfs-subvolume(
    'var-opt',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/opt';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,subvol=@var-opt
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

multi sub mount-btrfs-subvolume(
    'var-spool',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/spool';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,nodev,noexec,nosuid,subvol=@var-spool
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

multi sub mount-btrfs-subvolume(
    'var-tmp',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/tmp';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,nodev,noexec,nosuid,subvol=@var-tmp
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
    run(qqw<chmod 1777 /mnt/$btrfs-dir>);
}

multi sub mount-btrfs-subvolume(
    Str:D $btrfs-dir,
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        -t btrfs
        -o $mount-options,subvol=@$btrfs-dir
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

method !disable-cow(--> Nil)
{
    my Str:D $var-lib-machines = '/mnt/var/lib/machines';
    mkdir($var-lib-machines);
    chmod(0o700, $var-lib-machines);
    my Str:D @directory = qw<
        home
        srv
        var/lib/ex
        var/lib/machines
        var/lib/postgres
        var/log
        var/spool
        var/tmp
    >.map({ "/mnt/$_" });
    Archvault::Utils.disable-cow(|@directory, :recursive);
}

# bootstrap initial chroot with pacstrap
method !pacstrap-base(--> Nil)
{
    my Processor:D $processor = $.config.processor;
    my Bool:D $reflector = $.config.reflector;

    # base packages
    my Str:D @pkg = qw<
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
        lz4
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
    push(@pkg, 'intel-ucode') if $processor eq 'intel';
    push(@pkg, 'reflector') if $reflector;

    # download and install packages with pacman in chroot
    my Str:D $pacstrap-cmdline = sprintf('pacstrap /mnt %s', @pkg.join(' '));
    loop-cmdline-proc(
        'Running pacstrap...',
        $pacstrap-cmdline
    );
}

# secure user configuration
method !configure-users(--> Nil)
{
    my UserName:D $user-name-admin = $.config.user-name-admin;
    my UserName:D $user-name-guest = $.config.user-name-guest;
    my UserName:D $user-name-sftp = $.config.user-name-sftp;
    my Str:D $user-pass-hash-admin = $.config.user-pass-hash-admin;
    my Str:D $user-pass-hash-guest = $.config.user-pass-hash-guest;
    my Str:D $user-pass-hash-root = $.config.user-pass-hash-root;
    my Str:D $user-pass-hash-sftp = $.config.user-pass-hash-sftp;
    configure-users('root', $user-pass-hash-root);
    configure-users('admin', $user-name-admin, $user-pass-hash-admin);
    configure-users('guest', $user-name-guest, $user-pass-hash-guest);
    configure-users('sftp', $user-name-sftp, $user-pass-hash-sftp);
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
    'guest',
    UserName:D $user-name-guest,
    Str:D $user-pass-hash-guest
    --> Nil
)
{
    useradd('guest', $user-name-guest, $user-pass-hash-guest);
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
    'sftp',
    UserName:D $user-name-sftp,
    Str:D $user-pass-hash-sftp
    --> Nil
)
{
    useradd('sftp', $user-name-sftp, $user-pass-hash-sftp);
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
        proc
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
    'guest',
    UserName:D $user-name-guest,
    Str:D $user-pass-hash-guest
    --> Nil
)
{
    my Str:D $user-group-guest = 'guests,users';
    my Str:D $user-shell-guest = '/bin/bash';

    say("Creating new guest user named $user-name-guest...");
    run(qqw<arch-chroot /mnt groupadd $user-name-guest>);
    run(qqw<arch-chroot /mnt groupadd guests>);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -g $user-name-guest
        -G $user-group-guest
        -p $user-pass-hash-guest
        -s $user-shell-guest
        $user-name-guest
    >);
    chmod(0o700, "/mnt/home/$user-name-guest");
}

multi sub useradd(
    'sftp',
    UserName:D $user-name-sftp,
    Str:D $user-pass-hash-sftp
    --> Nil
)
{
    # https://wiki.archlinux.org/index.php/SFTP_chroot
    my Str:D $user-group-sftp = 'sftponly';
    my Str:D $user-shell-sftp = '/sbin/nologin';
    my Str:D $auth-dir = '/etc/ssh/authorized_keys';
    my Str:D $jail-dir = '/srv/ssh/jail';
    my Str:D $home-dir = "$jail-dir/$user-name-sftp";
    my Str:D @root-dir = $auth-dir, $jail-dir;

    say("Creating new SFTP user named $user-name-sftp...");
    arch-chroot-mkdir(@root-dir, 'root', 'root', 0o755);
    run(qqw<arch-chroot /mnt groupadd $user-group-sftp>);
    run(qqw<arch-chroot /mnt groupadd $user-name-sftp>);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        -M
        -d $home-dir
        -g $user-name-sftp
        -G $user-group-sftp
        -p $user-pass-hash-sftp
        -s $user-shell-sftp
        $user-name-sftp
    >);
    arch-chroot-mkdir($home-dir, $user-name-sftp, $user-name-sftp, 0o700);
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
    configure-dnscrypt-proxy('systemd-sysusers', $user-name-dnscrypt);
    configure-dnscrypt-proxy('User', $user-name-dnscrypt);
    configure-dnscrypt-proxy('EphemeralKeys');
}

multi sub configure-dnscrypt-proxy(
    'systemd-sysusers',
    UserName:D $user-name-dnscrypt
)
{
    my Str:D $systemd-sysusers = qq:to/EOF/;
    u $user-name-dnscrypt - "DNSCrypt user" /usr/share/dnscrypt-proxy -
    EOF
    my Str:D $path = 'usr/lib/sysusers.d/dnscrypt.conf';
    spurt("/mnt/$path", $systemd-sysusers);
    run(qqw<
        arch-chroot
        /mnt
        systemd-sysusers
        /$path
    >);
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
    my Str:D $path = 'etc/resolv.conf.head';
    copy(%?RESOURCES{$path}, "/mnt/$path");
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

method !configure-modprobe(--> Nil)
{
    my Str:D $path = 'etc/modprobe.d/modprobe.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !generate-initramfs(--> Nil)
{
    my DiskType:D $disk-type = $.config.disk-type;
    my Graphics:D $graphics = $.config.graphics;
    my Processor:D $processor = $.config.processor;
    configure-initramfs('MODULES', $graphics, $processor);
    configure-initramfs('HOOKS', $disk-type);
    configure-initramfs('FILES');
    configure-initramfs('BINARIES');
    configure-initramfs('COMPRESSION');
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
        fsck
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

multi sub configure-initramfs('BINARIES' --> Nil)
{
    my Str:D $sed-cmd = 's,^BINARIES.*,BINARIES=(/usr/bin/btrfs),';
    run(qqw<sed -i $sed-cmd /mnt/etc/mkinitcpio.conf>);
}

multi sub configure-initramfs('COMPRESSION' --> Nil)
{
    my Str:D $sed-cmd = 's,^#\(COMPRESSION="lz4"\),\1,';
    run(qqw<sed -i $sed-cmd /mnt/etc/mkinitcpio.conf>);
}

method !install-bootloader(--> Nil)
{
    my Graphics:D $graphics = $.config.graphics;
    my Str:D $partition = $.config.partition;
    my UserName:D $user-name-grub = $.config.user-name-grub;
    my Str:D $user-pass-hash-grub = $.config.user-pass-hash-grub;
    my VaultName:D $vault-name = $.config.vault-name;
    configure-bootloader(
        'GRUB_CMDLINE_LINUX',
        $partition,
        $vault-name,
        $graphics
    );
    configure-bootloader('GRUB_ENABLE_CRYPTODISK');
    configure-bootloader('superusers', $user-name-grub, $user-pass-hash-grub);
    configure-bootloader('unrestricted');
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
    my Str:D $partition-vault = $partition ~ '2';
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

multi sub configure-bootloader('GRUB_ENABLE_CRYPTODISK' --> Nil)
{
    my Str:D $sed-cmd = 's,^#\(GRUB_ENABLE_CRYPTODISK\),\1,';
    run(qqw<sed -i $sed-cmd /mnt/etc/default/grub>);
}

multi sub configure-bootloader(
    'superusers',
    UserName:D $user-name-grub,
    Str:D $user-pass-hash-grub
    --> Nil
)
{
    my Str:D $grub-superusers = qq:to/EOF/;
    set superusers="$user-name-grub"
    password_pbkdf2 $user-name-grub $user-pass-hash-grub
    EOF
    spurt('/mnt/etc/grub.d/40_custom', $grub-superusers, :append);
}

multi sub configure-bootloader(
    'unrestricted'
    --> Nil
)
{
    my Str:D $sed-cmd = 's/\${CLASS}\s/--unrestricted ${CLASS} /';
    shell("sed -i '$sed-cmd' /mnt/etc/grub.d/10_linux");
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
    my Str:D $path = 'etc/sysctl.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
    configure-sysctl('vm.vfs_cache_pressure') if $disk-type ~~ /SSD|USB/;
    configure-sysctl('vm.swappiness') if $disk-type ~~ /SSD|USB/;
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

method !configure-nftables(--> Nil)
{
    # XXX: customize nftables
    Nil;
}

method !configure-openssh(--> Nil)
{
    my UserName:D $user-name-sftp = $.config.user-name-sftp;
    configure-openssh('ssh_config');
    configure-openssh('sshd_config', $user-name-sftp);
    configure-openssh('hosts.allow');
    configure-openssh('moduli');
}

multi sub configure-openssh('ssh_config' --> Nil)
{
    my Str:D $path = 'etc/ssh/ssh_config';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-openssh('sshd_config', UserName:D $user-name-sftp --> Nil)
{
    my Str:D $path = 'etc/ssh/sshd_config';
    copy(%?RESOURCES{$path}, "/mnt/$path");

    # restrict allowed connections to $user-name-sftp
    my Str:D $sed-cmd = "3iAllowUsers $user-name-sftp";
    shell("sed -i '$sed-cmd' /mnt/$path");
}

multi sub configure-openssh('hosts.allow' --> Nil)
{
    # restrict allowed connections to LAN
    my Str:D $path = 'etc/hosts.allow';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-openssh('moduli' --> Nil)
{
    # filter weak ssh moduli
    shell(q{awk -i inplace '$5 > 2000' /mnt/etc/ssh/moduli});
}

method !configure-systemd(--> Nil)
{
    configure-systemd('limits');
    configure-systemd('mounts');
    configure-systemd('sleep');
    configure-systemd('tmpfiles');
    configure-systemd('udev');
}

multi sub configure-systemd('limits' --> Nil)
{
    my Str:D $base-path = 'etc/systemd/system.conf.d';
    my Str:D $path = "$base-path/limits.conf";
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('mounts' --> Nil)
{
    my Str:D $base-path = 'etc/systemd/system/tmp.mount.d';
    my Str:D $path = "$base-path/noexec.conf";
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('sleep' --> Nil)
{
    my Str:D $path = 'etc/systemd/sleep.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('tmpfiles' --> Nil)
{
    # https://wiki.archlinux.org/index.php/Tmpfs#Disable_automatic_mount
    my Str:D $path = 'etc/tmpfiles.d/tmp.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('udev' --> Nil)
{
    my Str:D $base-path = 'etc/udev/rules.d';
    my Str:D $path = "$base-path/60-io-schedulers.rules";
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-hidepid(--> Nil)
{
    my Str:D $base-path = 'etc/systemd/system/systemd-logind.service.d';
    my Str:D $path = "$base-path/hidepid.conf";
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");

    my Str:D $fstab-hidepid = q:to/EOF/;
    # /proc with hidepid (https://wiki.archlinux.org/index.php/Security#hidepid)
    proc                                      /proc       proc        nodev,noexec,nosuid,hidepid=2,gid=proc 0 0
    EOF
    spurt('/mnt/etc/fstab', $fstab-hidepid, :append);
}

method !configure-securetty(--> Nil)
{
    configure-securetty('securetty');
    configure-securetty('shell-timeout');
}

multi sub configure-securetty('securetty' --> Nil)
{
    my Str:D $path = 'etc/securetty';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-securetty('shell-timeout' --> Nil)
{
    my Str:D $path = 'etc/profile.d/shell-timeout.sh';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-xorg(--> Nil)
{
    mkdir('/mnt/etc/X11/xorg.conf.d');
    configure-xorg('scrolling');
    configure-xorg('security');
}

multi sub configure-xorg('scrolling' --> Nil)
{
    my Str:D $path = 'etc/X11/xorg.conf.d/20-natural-scrolling.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-xorg('security' --> Nil)
{
    my Str:D $path = 'etc/X11/xorg.conf.d/99-security.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
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

# interactive console
method !augment(--> Nil)
{
    # launch fully interactive Bash console, type 'exit' to exit
    shell('expect -c "spawn /bin/bash; interact"');
}

method !unmount(--> Nil)
{
    shell('umount -R /mnt');
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
    mkdir("/mnt/$dir", $permissions);
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
