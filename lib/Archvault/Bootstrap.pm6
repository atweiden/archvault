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
    # ensure pressing Ctrl-C works
    signal(SIGINT).tap({ exit(130) });
    self!setup;
    self!mkdisk;
    self!pacstrap-base;
    self!mkvault-key;
    self!configure-users;
    self!configure-sudoers;
    self!genfstab;
    self!set-hostname;
    self!configure-hosts;
    self!configure-dhcpcd;
    self!configure-dnscrypt-proxy;
    self!set-nameservers;
    self!set-locale;
    self!set-keymap;
    self!set-timezone;
    self!set-hwclock;
    self!configure-pacman;
    self!configure-modprobe;
    self!configure-modules-load;
    self!generate-initramfs;
    self!install-bootloader;
    self!configure-sysctl;
    self!configure-nftables;
    self!configure-openssh;
    self!configure-systemd;
    self!configure-hidepid;
    self!configure-securetty;
    self!configure-security-limits;
    self!configure-pamd;
    self!configure-shadow;
    self!configure-xorg;
    self!configure-dbus;
    self!enable-systemd-services;
    self!augment if $augment.so;
    self!unmount;
}


# -----------------------------------------------------------------------------
# worker functions
# -----------------------------------------------------------------------------

method !setup(--> Nil)
{
    my Bool:D $reflector = $.config.reflector;

    # initialize pacman-keys
    run(qw<pacman-key --init>);
    run(qw<pacman-key --populate archlinux>);

    # fetch dependencies needed prior to pacstrap
    my Str:D @dep = qw<
        arch-install-scripts
        btrfs-progs
        coreutils
        cryptsetup
        dialog
        dosfstools
        e2fsprogs
        efibootmgr
        expect
        glibc
        gptfdisk
        grub
        kbd
        kmod
        libutil-linux
        man-pages
        openssl
        pacman
        procps-ng
        tzdata
        util-linux
    >;

    my Str:D $pacman-dep-cmdline =
        sprintf(
            Q{pacman --sync --refresh --needed --noconfirm %s},
            @dep.join(' ')
        );
    Archvault::Utils.loop-cmdline-proc(
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
        'pacman --sync --refresh --needed --noconfirm reflector';
    Archvault::Utils.loop-cmdline-proc(
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
    Archvault::Utils.loop-cmdline-proc(
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

    # create uefi partition
    my Str:D $partition-efi =
        Archvault::Utils.gen-partition('efi', $partition);
    mkefi($partition-efi);

    # create vault
    my Str:D $partition-vault =
        Archvault::Utils.gen-partition('vault', $partition);
    mkvault($partition-vault, $vault-name, :$vault-pass);

    # create and mount btrfs volumes
    mkbtrfs($disk-type, $vault-name);

    # mount efi boot
    mount-efi($partition-efi);

    # disable Btrfs CoW
    disable-cow();
}

# partition disk with gdisk
sub sgdisk(Str:D $partition --> Nil)
{
    # erase existing partition table
    # create 2M EF02 BIOS boot sector
    # create 550M EF00 EFI system partition
    # create max sized partition for LUKS encrypted volume
    run(qw<
        sgdisk
        --zap-all
        --clear
        --mbrtogpt
        --new=1:0:+2M
        --typecode=1:EF02
        --new=2:0:+550M
        --typecode=2:EF00
        --new=3:0:0
        --typecode=3:8300
    >, $partition);
}

sub mkefi(Str:D $partition-efi --> Nil)
{
    run(qw<modprobe vfat>);
    run(qqw<mkfs.vfat -F 32 $partition-efi>);
}

# create vault with cryptsetup
sub mkvault(
    Str:D $partition-vault,
    VaultName:D $vault-name,
    VaultPass :$vault-pass
    --> Nil
)
{
    # load kernel modules for cryptsetup
    run(qw<modprobe dm_mod dm-crypt>);
    # create vault
    mkvault-cryptsetup(:$partition-vault, :$vault-name, :$vault-pass);
}

# LUKS encrypted volume password was given
multi sub mkvault-cryptsetup(
    Str:D :$partition-vault! where .so,
    VaultName:D :$vault-name! where .so,
    VaultPass:D :$vault-pass! where .so
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
    Str:D :$partition-vault! where .so,
    VaultName:D :$vault-name! where .so,
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
    Archvault::Utils.loop-cmdline-proc(
        'Creating LUKS vault...',
        $cryptsetup-luks-format-cmdline
    );

    # open LUKS encrypted volume, prompt user for vault password
    Archvault::Utils.loop-cmdline-proc(
        'Opening LUKS vault...',
        $cryptsetup-luks-open-cmdline
    );
}

multi sub build-cryptsetup-luks-format-cmdline(
    Str:D $partition-vault where .so,
    Bool:D :interactive($)! where .so
    --> Str:D
)
{
    my Str:D $spawn-cryptsetup-luks-format = qqw<
         spawn cryptsetup
         --type luks1
         --cipher aes-xts-plain64
         --key-slot 1
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
    Str:D $partition-vault where .so,
    VaultPass:D $vault-pass where .so,
    Bool:D :non-interactive($)! where .so
    --> Str:D
)
{
    my Str:D $spawn-cryptsetup-luks-format = qqw<
                 spawn cryptsetup
                 --type luks1
                 --cipher aes-xts-plain64
                 --key-slot 1
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
        'sleep 7',
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
    Str:D $partition-vault where .so,
    VaultName:D $vault-name where .so,
    Bool:D :interactive($)! where .so
    --> Str:D
)
{
    my Str:D $cryptsetup-luks-open-cmdline =
        "cryptsetup luksOpen $partition-vault $vault-name";
}

multi sub build-cryptsetup-luks-open-cmdline(
    Str:D $partition-vault where .so,
    VaultName:D $vault-name where .so,
    VaultPass:D $vault-pass where .so,
    Bool:D :non-interactive($)! where .so
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
    run(qw<modprobe btrfs xxhash_generic>);
    run(qqw<mkfs.btrfs --csum xxhash /dev/mapper/$vault-name>);

    # set mount options
    my Str:D @mount-options = qw<
        rw
        noatime
        compress-force=zstd
        space_cache=v2
    >;
    push(@mount-options, 'ssd') if $disk-type eq 'SSD';
    my Str:D $mount-options = @mount-options.join(',');

    # mount main btrfs filesystem on open vault
    mkdir('/mnt2');
    run(qqw<
        mount
        --types btrfs
        --options $mount-options
        /dev/mapper/$vault-name
        /mnt2
    >);

    # btrfs subvolumes, starting with root / ('')
    my Str:D @btrfs-dir =
        '',
        'home',
        'opt',
        'srv',
        'var',
        'var-cache-pacman',
        'var-lib-ex',
        'var-lib-machines',
        'var-lib-portables',
        'var-log',
        'var-opt',
        'var-spool',
        'var-tmp';

    # create btrfs subvolumes
    chdir('/mnt2');
    @btrfs-dir.map(-> Str:D $btrfs-dir {
        run(qqw<btrfs subvolume create @$btrfs-dir>);
    });
    chdir('/');

    # mount btrfs subvolumes
    @btrfs-dir.map(-> Str:D $btrfs-dir {
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
        --types btrfs
        --options $mount-options,nodev,noexec,nosuid,subvol=@$btrfs-dir
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
        --types btrfs
        --options $mount-options,subvol=@var-cache-pacman
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
        --types btrfs
        --options $mount-options,nodev,noexec,nosuid,subvol=@var-lib-ex
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
    run(qqw<chmod 1777 /mnt/$btrfs-dir>);
}

multi sub mount-btrfs-subvolume(
    'var-lib-machines',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/lib/machines';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        --types btrfs
        --options $mount-options,subvol=@var-lib-machines
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
    chmod(0o700, "/mnt/$btrfs-dir");
}

multi sub mount-btrfs-subvolume(
    'var-lib-portables',
    Str:D $mount-options,
    VaultName:D $vault-name
    --> Nil
)
{
    my Str:D $btrfs-dir = 'var/lib/portables';
    mkdir("/mnt/$btrfs-dir");
    run(qqw<
        mount
        --types btrfs
        --options $mount-options,subvol=@var-lib-portables
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
    chmod(0o700, "/mnt/$btrfs-dir");
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
        --types btrfs
        --options $mount-options,nodev,noexec,nosuid,subvol=@var-log
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
        --types btrfs
        --options $mount-options,subvol=@var-opt
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
        --types btrfs
        --options $mount-options,nodev,noexec,nosuid,subvol=@var-spool
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
        --types btrfs
        --options $mount-options,nodev,noexec,nosuid,subvol=@var-tmp
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
        --types btrfs
        --options $mount-options,subvol=@$btrfs-dir
        /dev/mapper/$vault-name
        /mnt/$btrfs-dir
    >);
}

sub mount-efi(Str:D $partition-efi --> Nil)
{
    my Str:D $efi-dir = '/mnt/boot/efi';
    mkdir($efi-dir);
    my Str:D $mount-options = qw<
        nodev
        noexec
        nosuid
    >.join(',');
    run(qqw<mount --options $mount-options $partition-efi $efi-dir>);
}

sub disable-cow(--> Nil)
{
    my Str:D @directory = qw<
        srv
        var/lib/ex
        var/lib/machines
        var/lib/portables
        var/log
        var/spool
        var/tmp
    >.map(-> Str:D $directory { sprintf(Q{/mnt/%s}, $directory) });
    Archvault::Utils.disable-cow(|@directory, :recursive);
}

# bootstrap initial chroot with pacstrap
method !pacstrap-base(--> Nil)
{
    my Str:D @package = $.config.package;
    my Processor:D $processor = $.config.processor;
    my Bool:D $reflector = $.config.reflector;

    # base packages - arch's C<base> with light additions
    # duplicates C<base>'s C<depends> for thoroughness
    my Str:D @pkg = qw<
        acpi
        arch-install-scripts
        base
        bash
        bash-completion
        binutils
        btrfs-progs
        busybox
        bzip2
        ca-certificates
        coreutils
        cryptsetup
        curl
        device-mapper
        dhcpcd
        diffutils
        dnscrypt-proxy
        dosfstools
        e2fsprogs
        efibootmgr
        exfat-utils
        file
        filesystem
        findutils
        gawk
        gcc-libs
        gettext
        glibc
        gptfdisk
        grep
        grub
        gzip
        iana-etc
        iproute2
        iputils
        iw
        kbd
        kmod
        ldns
        less
        licenses
        linux
        linux-firmware
        lynx
        lz4
        man-db
        man-pages
        mkinitcpio
        ncurses
        nftables
        openresolv
        openssh
        openssl
        pacman
        pciutils
        perl
        pinentry
        procps-ng
        rsync
        sed
        shadow
        sudo
        systemd
        systemd-sysvcompat
        tar
        tzdata
        util-linux
        vim
        which
        wireguard-tools
        wireless-regdb
        wpa_supplicant
        xz
        zlib
        zram-generator
        zstd
    >;

    # https://www.archlinux.org/news/changes-to-intel-microcodeupdates/
    push(@pkg, 'intel-ucode') if $processor eq 'INTEL';

    push(@pkg, $_) for @package;

    # download and install packages with pacman in chroot
    my Str:D $pacstrap-cmdline = sprintf('pacstrap /mnt %s', @pkg.join(' '));
    Archvault::Utils.loop-cmdline-proc(
        'Running pacstrap...',
        $pacstrap-cmdline
    );
}

# avoid having to enter password twice on boot
method !mkvault-key(--> Nil)
{
    my Str:D $partition = $.config.partition;
    my Str:D $partition-vault =
        Archvault::Utils.gen-partition('vault', $partition);
    my VaultName:D $vault-name = $.config.vault-name;
    my VaultPass $vault-pass = $.config.vault-pass;
    mkvault-key-gen();
    mkvault-key-add(:$partition-vault, :$vault-pass);
    mkvault-key-sec();
}

# generate LUKS key
sub mkvault-key-gen(--> Nil)
{
    # source of entropy
    my Str:D $src = '/dev/random';
    my Str:D $dst = '/mnt/boot/volume.key';
    # bytes to read from C<$src>
    my UInt:D $bytes = 64;
    # exec idiomatic version of C<head -c 64 /dev/random > /mnt/boot/volume.key>
    my IO::Handle:D $fh = $src.IO.open(:bin);
    my Buf:D $buf = $fh.read($bytes);
    $fh.close;
    spurt($dst, $buf);
}

# LUKS encrypted volume password was given
multi sub mkvault-key-add(
    Str:D :$partition-vault! where .so,
    VaultPass:D :$vault-pass! where .so
    --> Nil
)
{
    my Str:D $cryptsetup-luks-add-key-cmdline =
        build-cryptsetup-luks-add-key-cmdline(
            :non-interactive,
            $partition-vault,
            $vault-pass
        );

    # make LUKS key without prompt for vault password
    shell($cryptsetup-luks-add-key-cmdline);
}

multi sub mkvault-key-add(
    Str:D :$partition-vault! where .so,
    VaultPass :vault-pass($)
    --> Nil
)
{
    my Str:D $cryptsetup-luks-add-key-cmdline =
        build-cryptsetup-luks-add-key-cmdline(
            :interactive,
            $partition-vault
        );

    # add LUKS key, prompt user for vault password
    Archvault::Utils.loop-cmdline-proc(
        'Adding LUKS key...',
        $cryptsetup-luks-add-key-cmdline
    );
}

multi sub build-cryptsetup-luks-add-key-cmdline(
    Str:D $partition-vault where .so,
    Bool:D :interactive($)! where .so
    --> Str:D
)
{
    my Str:D $iter-time = '--iter-time 1';
    my Str:D $key = '/mnt/boot/volume.key';
    my Str:D $spawn-cryptsetup-luks-add-key =
        "spawn cryptsetup luksAddKey $iter-time $partition-vault $key";
    my Str:D $interact =
        'interact';
    my Str:D $catch-wait-result =
        'catch wait result';
    my Str:D $exit-lindex-result =
        'exit [lindex $result 3]';

    my Str:D @cryptsetup-luks-add-key-cmdline =
        $spawn-cryptsetup-luks-add-key,
        $interact,
        $catch-wait-result,
        $exit-lindex-result;

    my Str:D $cryptsetup-luks-add-key-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-add-key-cmdline);
        expect -c '%s;
                   %s;
                   %s;
                   %s'
        EOF
}

multi sub build-cryptsetup-luks-add-key-cmdline(
    Str:D $partition-vault where .so,
    VaultPass:D $vault-pass where .so,
    Bool:D :non-interactive($)! where .so
    --> Str:D
)
{
    my Str:D $iter-time = '--iter-time 1';
    my Str:D $key = '/mnt/boot/volume.key';
    my Str:D $spawn-cryptsetup-luks-add-key =
                "spawn cryptsetup luksAddKey $iter-time $partition-vault $key";
    my Str:D $sleep =
                'sleep 0.33';
    my Str:D $expect-enter-send-vault-pass =
        sprintf('expect "Enter*" { send "%s\r" }', $vault-pass);
    my Str:D $expect-eof =
                'expect eof';

    my Str:D @cryptsetup-luks-add-key-cmdline =
        $spawn-cryptsetup-luks-add-key,
        $sleep,
        $expect-enter-send-vault-pass,
        'sleep 7',
        $expect-eof;

    my Str:D $cryptsetup-luks-add-key-cmdline =
        sprintf(q:to/EOF/.trim, |@cryptsetup-luks-add-key-cmdline);
        expect <<EOS
          %s
          %s
          %s
          %s
          %s
        EOS
        EOF
}

sub mkvault-key-sec(--> Nil)
{
    run(qw<arch-chroot /mnt chmod 000 /boot/volume.key>);
    run(qw<arch-chroot /mnt chmod -R g-rwx,o-rwx /boot>);
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
    mksudo($user-name-admin);
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
        log
        proc
        users
        uucp
        wheel
    >.join(',');
    my Str:D $user-shell-admin = '/bin/bash';

    say("Creating new admin user named $user-name-admin...");
    groupadd($user-name-admin);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        --create-home
        --gid $user-name-admin
        --groups $user-group-admin
        --password $user-pass-hash-admin
        --shell $user-shell-admin
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
    my Str:D $user-group-guest = qw<
        guests
        users
    >.join(',');
    my Str:D $user-shell-guest = '/bin/bash';

    say("Creating new guest user named $user-name-guest...");
    groupadd($user-name-guest, 'guests');
    run(qqw<
        arch-chroot
        /mnt
        useradd
        --create-home
        --gid $user-name-guest
        --groups $user-group-guest
        --password $user-pass-hash-guest
        --shell $user-shell-guest
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
    my Str:D $user-group-sftp = qw<
        sftponly
    >.join(',');
    my Str:D $user-shell-sftp = '/usr/bin/nologin';
    my Str:D $auth-dir = '/etc/ssh/authorized_keys';
    my Str:D $jail-dir = '/srv/ssh/jail';
    my Str:D $home-dir = "$jail-dir/$user-name-sftp";
    my Str:D @root-dir = $auth-dir, $jail-dir;

    say("Creating new SFTP user named $user-name-sftp...");
    arch-chroot-mkdir(@root-dir, 'root', 'root', 0o755);
    groupadd($user-name-sftp, $user-group-sftp);
    run(qqw<
        arch-chroot
        /mnt
        useradd
        --no-create-home
        --home-dir $home-dir
        --gid $user-name-sftp
        --groups $user-group-sftp
        --password $user-pass-hash-sftp
        --shell $user-shell-sftp
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
    run(qqw<arch-chroot /mnt usermod --password $user-pass-hash-root root>);
}

sub groupadd(*@group-name --> Nil)
{
    @group-name.map(-> Str:D $group-name {
        run(qqw<arch-chroot /mnt groupadd $group-name>);
    });
}

sub mksudo(UserName:D $user-name-admin --> Nil)
{
    say("Giving sudo privileges to admin user $user-name-admin...");
    my Str:D $sudoers = qq:to/EOF/;
    $user-name-admin ALL=(ALL) ALL
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/reboot
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/shutdown
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl halt
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff
    $user-name-admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot
    EOF
    spurt('/mnt/etc/sudoers', "\n" ~ $sudoers, :append);
}

method !configure-sudoers(--> Nil)
{
    replace('sudoers');
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

method !configure-hosts(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    my HostName:D $host-name = $.config.host-name;
    my Str:D $path = 'etc/hosts';
    copy(%?RESOURCES{$path}, "/mnt/$path");
    replace('hosts', $disable-ipv6, $host-name);
}

method !configure-dhcpcd(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    replace('dhcpcd.conf', $disable-ipv6);
}

method !configure-dnscrypt-proxy(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    replace('dnscrypt-proxy.toml', $disable-ipv6);
}

method !set-nameservers(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    my Str:D $path = 'etc/resolvconf.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
    replace('resolvconf.conf', $disable-ipv6);
}

method !set-locale(--> Nil)
{
    my Locale:D $locale = $.config.locale;
    my Str:D $locale-fallback = $locale.substr(0, 2);

    # customize /etc/locale.gen
    replace('locale.gen', $locale);
    run(qw<arch-chroot /mnt locale-gen>);

    # customize /etc/locale.conf
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
        --symbolic
        --force
        /usr/share/zoneinfo/$timezone
        /etc/localtime
    >);
}

method !set-hwclock(--> Nil)
{
    run(qw<arch-chroot /mnt hwclock --systohc --utc>);
}

method !configure-pacman(--> Nil)
{
    replace('pacman.conf');
}

method !configure-modprobe(--> Nil)
{
    my Str:D $path = 'etc/modprobe.d/modprobe.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-modules-load(--> Nil)
{
    my Str:D $path = 'etc/modules-load.d/bbr.conf';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !generate-initramfs(--> Nil)
{
    my DiskType:D $disk-type = $.config.disk-type;
    my Graphics:D $graphics = $.config.graphics;
    my Processor:D $processor = $.config.processor;
    replace('mkinitcpio.conf', $disk-type, $graphics, $processor);
    run(qw<arch-chroot /mnt mkinitcpio --preset linux>);
}

method !install-bootloader(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    my DiskType:D $disk-type = $.config.disk-type;
    my Bool:D $enable-serial-console = $.config.enable-serial-console;
    my Graphics:D $graphics = $.config.graphics;
    my Str:D $partition = $.config.partition;
    my Str:D $partition-vault =
        Archvault::Utils.gen-partition('vault', $partition);
    my UserName:D $user-name-grub = $.config.user-name-grub;
    my Str:D $user-pass-hash-grub = $.config.user-pass-hash-grub;
    my VaultName:D $vault-name = $.config.vault-name;
    replace(
        'grub',
        $disable-ipv6,
        $disk-type,
        $enable-serial-console,
        $graphics,
        $partition-vault,
        $vault-name
    );
    replace('10_linux');
    configure-bootloader('superusers', $user-name-grub, $user-pass-hash-grub);
    install-bootloader($partition);
}

sub configure-bootloader(
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

multi sub install-bootloader(
    Str:D $partition
    --> Nil
)
{
    install-bootloader(:legacy, $partition);
    install-bootloader(:uefi, $partition);
    mkdir('/mnt/boot/grub/locale');
    copy(
        '/mnt/usr/share/locale/en@quot/LC_MESSAGES/grub.mo',
        '/mnt/boot/grub/locale/en.mo'
    );
    run(qw<
        arch-chroot
        /mnt
        grub-mkconfig
        --output=/boot/grub/grub.cfg
    >);
}

multi sub install-bootloader(
    Str:D $partition,
    Bool:D :legacy($)! where .so
    --> Nil
)
{
    # legacy bios
    run(qw<
        arch-chroot
        /mnt
        grub-install
        --target=i386-pc
        --recheck
    >, $partition);
}

multi sub install-bootloader(
    Str:D $partition,
    Bool:D :uefi($)! where .so
    --> Nil
)
{
    # uefi
    run(qw<
        arch-chroot
        /mnt
        grub-install
        --target=x86_64-efi
        --efi-directory=/boot/efi
        --removable
    >, $partition);

    # fix virtualbox uefi
    my Str:D $nsh = q:to/EOF/;
    fs0:
    \EFI\BOOT\BOOTX64.EFI
    EOF
    spurt('/mnt/boot/efi/startup.nsh', $nsh, :append);
}

method !configure-sysctl(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    my DiskType:D $disk-type = $.config.disk-type;
    my Str:D $path = 'etc/sysctl.d/99-sysctl.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
    replace('99-sysctl.conf', $disable-ipv6, $disk-type);
    run(qw<arch-chroot /mnt sysctl --system>);
}

method !configure-nftables(--> Nil)
{
    my Str:D @path =
        'etc/nftables.conf',
        'etc/nftables/wireguard/table/inet/filter/forward/wireguard.nft',
        'etc/nftables/wireguard/table/inet/filter/input/wireguard.nft',
        'etc/nftables/wireguard/table/wireguard.nft';
    @path.map(-> Str:D $path {
        my Str:D $base-path = $path.IO.dirname;
        mkdir("/mnt/$base-path");
        copy(%?RESOURCES{$path}, "/mnt/$path");
    });
}

method !configure-openssh(--> Nil)
{
    my Bool:D $disable-ipv6 = $.config.disable-ipv6;
    my UserName:D $user-name-sftp = $.config.user-name-sftp;
    configure-openssh('ssh_config');
    configure-openssh('sshd_config', $disable-ipv6, $user-name-sftp);
    configure-openssh('moduli');
}

multi sub configure-openssh(
    'ssh_config'
    --> Nil
)
{
    my Str:D $path = 'etc/ssh/ssh_config';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-openssh(
    'sshd_config',
    Bool:D $disable-ipv6,
    UserName:D $user-name-sftp
    --> Nil
)
{
    my Str:D $path = 'etc/ssh/sshd_config';
    copy(%?RESOURCES{$path}, "/mnt/$path");
    replace('sshd_config', $disable-ipv6, $user-name-sftp);
}

multi sub configure-openssh(
    'moduli'
    --> Nil
)
{
    # filter weak ssh moduli
    replace('moduli');
}

method !configure-systemd(--> Nil)
{
    configure-systemd('coredump');
    configure-systemd('ipv6');
    configure-systemd('journald');
    configure-systemd('limits');
    configure-systemd('machine-id');
    configure-systemd('mounts');
    configure-systemd('sleep');
    configure-systemd('tmpfiles');
    configure-systemd('udev');
    configure-systemd('zram-generator');
}

multi sub configure-systemd('coredump' --> Nil)
{
    # insist systemd disable core dumps
    my Str:D $path = 'etc/systemd/coredump.conf.d/disable.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('ipv6' --> Nil)
{
    # insist systemd-networkd enable ipv6 privacy extensions
    my Str:D $path = 'etc/systemd/network/ipv6.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('journald' --> Nil)
{
    my Str:D $path = 'etc/systemd/journald.conf.d/limits.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('limits' --> Nil)
{
    my Str:D $path = 'etc/systemd/system.conf.d/limits.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('machine-id' --> Nil)
{
    my Str:D $path = 'etc/machine-id';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('mounts' --> Nil)
{
    my Str:D $path = 'etc/systemd/system/tmp.mount.d/noexec.conf';
    my Str:D $base-path = $path.IO.dirname;
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
    my Str:D $path = 'etc/udev/rules.d/60-io-schedulers.rules';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-systemd('zram-generator' --> Nil)
{
    my Str:D $path = 'etc/systemd/zram-generator.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-hidepid(--> Nil)
{
    my Str:D $path = 'etc/systemd/system/systemd-logind.service.d/hidepid.conf';
    my Str:D $base-path = $path.IO.dirname;
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
    my Bool:D $enable-serial-console = $.config.enable-serial-console;
    configure-securetty('securetty');
    configure-securetty('securetty', 'enable-serial-console')
        if $enable-serial-console.so;
    configure-securetty('shell-timeout');
}

multi sub configure-securetty('securetty' --> Nil)
{
    my Str:D $path = 'etc/securetty';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-securetty('securetty', 'enable-serial-console' --> Nil)
{
    replace('securetty');
}

multi sub configure-securetty('shell-timeout' --> Nil)
{
    my Str:D $path = 'etc/profile.d/shell-timeout.sh';
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-security-limits(--> Nil)
{
    my Str:D $path = 'etc/security/limits.d/coredump.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-pamd(--> Nil)
{
    # raise number of passphrase hashing rounds C<passwd> employs
    replace('passwd');
}

method !configure-shadow(--> Nil)
{
    # set C<shadow> (group) passphrase encryption method and hashing
    # rounds in line with pam
    replace('login.defs');
}

method !configure-xorg(--> Nil)
{
    configure-xorg('Xwrapper.config');
    configure-xorg('10-synaptics.conf');
    configure-xorg('99-security.conf');
}

multi sub configure-xorg('Xwrapper.config' --> Nil)
{
    my Str:D $path = 'etc/X11/Xwrapper.config';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-xorg('10-synaptics.conf' --> Nil)
{
    my Str:D $path = 'etc/X11/xorg.conf.d/10-synaptics.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

multi sub configure-xorg('99-security.conf' --> Nil)
{
    my Str:D $path = 'etc/X11/xorg.conf.d/99-security.conf';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    copy(%?RESOURCES{$path}, "/mnt/$path");
}

method !configure-dbus(--> Nil)
{
    my Str:D $path = 'var/lib/dbus/machine-id';
    my Str:D $base-path = $path.IO.dirname;
    mkdir("/mnt/$base-path");
    run(qqw<
        arch-chroot
        /mnt
        ln
        --symbolic
        --force
        /etc/machine-id
        /$path
    >);
}

method !enable-systemd-services(--> Nil)
{
    my Str:D @service = qw<
        dnscrypt-proxy.service
        nftables
        systemd-zram-setup@zram0.service
    >;
    @service.map(-> Str:D $service {
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
    shell('umount --recursive --verbose /mnt');
    my VaultName:D $vault-name = $.config.vault-name;
    run(qqw<cryptsetup luksClose $vault-name>);
}


# -----------------------------------------------------------------------------
# helper functions
# -----------------------------------------------------------------------------

# sub arch-chroot-mkdir {{{

multi sub arch-chroot-mkdir(
    Str:D @dir,
    Str:D $user,
    Str:D $group,
    # permissions should be octal: https://docs.raku.org/routine/chmod
    UInt:D $permissions
    --> Nil
)
{
    @dir.map(-> Str:D $dir {
        arch-chroot-mkdir($dir, $user, $group, $permissions)
    });
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

# end sub arch-chroot-mkdir }}}
# sub replace {{{

# --- sudoers {{{

multi sub replace(
    'sudoers'
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/sudoers';
    my Str:D $slurp = slurp($file);
    my Str:D $defaults = q:to/EOF/;
    # reset environment by default
    Defaults env_reset

    # set default editor to rvim, do not allow visudo to use $EDITOR/$VISUAL
    Defaults editor=/usr/bin/rvim, !env_editor

    # force password entry with every sudo
    Defaults timestamp_timeout=0

    # only allow sudo when the user is logged in to a real tty
    Defaults requiretty

    # set PATH environment variable for commands run using sudo
    Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    # always use indicated umask regardless of what umask user has set
    Defaults umask=0022
    Defaults umask_override

    # prevent arbitrary code execution as your user when sudoing to another
    # user due to TTY hijacking via TIOCSTI ioctl
    Defaults use_pty

    # wrap logfile lines at 72 characters
    Defaults loglinelen=72
    EOF
    my Str:D $replace = join("\n", $defaults, $slurp);
    spurt($file, $replace);
}

# --- end sudoers }}}
# --- hosts {{{

multi sub replace(
    'hosts',
    Bool:D $disable-ipv6 where .so,
    HostName:D $host-name
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/hosts';
    my Str:D @replace =
        $file.IO.lines
        # remove IPv6 hosts
        ==> replace('hosts', '::1')
        ==> replace('hosts', '127.0.1.1', $host-name);
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'hosts',
    Bool:D $disable-ipv6,
    HostName:D $host-name
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/hosts';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('hosts', '127.0.1.1', $host-name);
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'hosts',
    '::1',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'::1'/, :k);
    @line.splice($index, 1);
    @line;
}

multi sub replace(
    'hosts',
    '127.0.1.1',
    HostName:D $host-name,
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.elems;
    my Str:D $replace =
        "127.0.1.1       $host-name.localdomain       $host-name";
    @line[$index] = $replace;
    @line;
}

# --- end hosts }}}
# --- dhcpcd.conf {{{

multi sub replace(
    'dhcpcd.conf',
    Bool:D $disable-ipv6 where .so
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/dhcpcd.conf';
    my Str:D $dhcpcd = q:to/EOF/;
    # Set vendor-class-id to empty string
    vendorclassid

    # Use the same DNS servers every time
    static domain_name_servers=127.0.0.1

    # Disable IPv6 router solicitation
    noipv6rs
    noipv6
    EOF
    spurt($file, "\n" ~ $dhcpcd, :append);
}

multi sub replace(
    'dhcpcd.conf',
    Bool:D $disable-ipv6
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/dhcpcd.conf';
    my Str:D $dhcpcd = q:to/EOF/;
    # Set vendor-class-id to empty string
    vendorclassid

    # Use the same DNS servers every time
    static domain_name_servers=127.0.0.1 ::1

    # Disable IPv6 router solicitation
    #noipv6rs
    #noipv6
    EOF
    spurt($file, "\n" ~ $dhcpcd, :append);
}

# --- end dhcpcd.conf }}}
# --- dnscrypt-proxy.toml {{{

multi sub replace(
    'dnscrypt-proxy.toml',
    Bool:D $disable-ipv6 where .so
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/dnscrypt-proxy/dnscrypt-proxy.toml';
    my Str:D @replace =
        $file.IO.lines
        # do not listen on IPv6 address
        ==> replace('dnscrypt-proxy.toml', 'listen_addresses')
        # server must support DNS security extensions (DNSSEC)
        ==> replace('dnscrypt-proxy.toml', 'require_dnssec')
        # disable undesireable resolvers
        ==> replace('dnscrypt-proxy.toml', 'disabled_server_names')
        # always use TCP to connect to upstream servers
        ==> replace('dnscrypt-proxy.toml', 'force_tcp')
        # create new, unique key for each DNS query
        ==> replace('dnscrypt-proxy.toml', 'dnscrypt_ephemeral_keys')
        # disable TLS session tickets
        ==> replace('dnscrypt-proxy.toml', 'tls_disable_session_tickets')
        # unconditionally use fallback resolver
        ==> replace('dnscrypt-proxy.toml', 'ignore_system_dns')
        # wait for network connectivity before initializing
        ==> replace('dnscrypt-proxy.toml', 'netprobe_timeout')
        # immediately respond to IPv6 queries with empty response
        ==> replace('dnscrypt-proxy.toml', 'block_ipv6')
        # disable DNS cache
        ==> replace('dnscrypt-proxy.toml', 'cache')
        # skip resolvers incompatible with anonymization
        ==> replace('dnscrypt-proxy.toml', 'skip_incompatible');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Bool:D $disable-ipv6
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/dnscrypt-proxy/dnscrypt-proxy.toml';
    my Str:D @replace =
        $file.IO.lines
        # server must support DNS security extensions (DNSSEC)
        ==> replace('dnscrypt-proxy.toml', 'require_dnssec')
        # disable undesireable resolvers
        ==> replace('dnscrypt-proxy.toml', 'disabled_server_names')
        # always use TCP to connect to upstream servers
        ==> replace('dnscrypt-proxy.toml', 'force_tcp')
        # create new, unique key for each DNS query
        ==> replace('dnscrypt-proxy.toml', 'dnscrypt_ephemeral_keys')
        # disable TLS session tickets
        ==> replace('dnscrypt-proxy.toml', 'tls_disable_session_tickets')
        # unconditionally use fallback resolver
        ==> replace('dnscrypt-proxy.toml', 'ignore_system_dns')
        # wait for network connectivity before initializing
        ==> replace('dnscrypt-proxy.toml', 'netprobe_timeout')
        # disable DNS cache
        ==> replace('dnscrypt-proxy.toml', 'cache')
        # skip resolvers incompatible with anonymization
        ==> replace('dnscrypt-proxy.toml', 'skip_incompatible');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'listen_addresses',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = ['127.0.0.1:53']}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'require_dnssec',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'disabled_server_names',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = ['cloudflare-ipv6']}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'force_tcp',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'dnscrypt_ephemeral_keys',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'\h*$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'tls_disable_session_tickets',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'\h*$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'ignore_system_dns',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'netprobe_timeout',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 420}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'block_ipv6',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject\h/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'cache',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject\h/, :k);
    my Str:D $replace = sprintf(Q{%s = false}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'dnscrypt-proxy.toml',
    Str:D $subject where 'skip_incompatible',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject\h/, :k);
    my Str:D $replace = sprintf(Q{%s = true}, $subject);
    @line[$index] = $replace;
    @line;
}

# --- end dnscrypt-proxy.toml }}}
# --- resolvconf.conf {{{

multi sub replace(
    'resolvconf.conf',
    Bool:D $disable-ipv6 where .so
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/resolvconf.conf';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('resolvconf.conf', 'name_servers');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'resolvconf.conf',
    Bool:D $disable-ipv6
    --> Nil
)
{*}

multi sub replace(
    'resolvconf.conf',
    Str:D $subject where 'name_servers',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s="127.0.0.1"}, $subject);
    @line[$index] = $replace;
    @line;
}

# --- end resolvconf.conf }}}
# --- locale.gen {{{

multi sub replace(
    'locale.gen',
    Locale:D $locale
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/locale.gen';
    my Str:D @line = $file.IO.lines;
    my Str:D $locale-full = sprintf(Q{%s.UTF-8 UTF-8}, $locale);
    my UInt:D $index = @line.first(/^"#$locale-full"/, :k);
    @line[$index] = $locale-full;
    my Str:D $replace = @line.join("\n");
    spurt($file, $replace ~ "\n");
}

# --- end locale.gen }}}
# --- pacman.conf {{{

multi sub replace(
    'pacman.conf'
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/pacman.conf';
    my Str:D @replace =
        $file.IO.lines
        # uncomment C<Color>
        ==> replace('pacman.conf', 'Color')
        # put C<ILoveCandy> on the line below C<CheckSpace>
        ==> replace('pacman.conf', 'ILoveCandy');
    @replace =
        @replace
        # uncomment multilib section on 64-bit machines
        ==> replace('pacman.conf', 'multilib') if $*KERNEL.bits == 64;
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'pacman.conf',
    Str:D $subject where 'Color',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'\h*$subject/, :k);
    @line[$index] = $subject;
    @line;
}

multi sub replace(
    'pacman.conf',
    Str:D $subject where 'ILoveCandy',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^CheckSpace/, :k);
    @line.splice($index + 1, 0, $subject);
    @line;
}

multi sub replace(
    'pacman.conf',
    Str:D $subject where 'multilib',
    Str:D @line
    --> Array[Str:D]
)
{
    # uncomment lines starting with C<[multilib]> up to but excluding blank line
    my UInt:D @index = @line.grep({ /^'#'\h*'['$subject']'/ ff^ /^\h*$/ }, :k);
    @index.race.map(-> UInt:D $index { @line[$index] .= subst(/^'#'/, '') });
    @line;
}

# --- end pacman.conf }}}
# --- mkinitcpio.conf {{{

multi sub replace(
    'mkinitcpio.conf',
    DiskType:D $disk-type,
    Graphics:D $graphics,
    Processor:D $processor
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/mkinitcpio.conf';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('mkinitcpio.conf', 'MODULES', $graphics, $processor)
        ==> replace('mkinitcpio.conf', 'HOOKS', $disk-type)
        ==> replace('mkinitcpio.conf', 'FILES')
        ==> replace('mkinitcpio.conf', 'BINARIES')
        ==> replace('mkinitcpio.conf', 'COMPRESSION');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'mkinitcpio.conf',
    Str:D $subject where 'MODULES',
    Graphics:D $graphics,
    Processor:D $processor,
    Str:D @line
    --> Array[Str:D]
)
{
    # prepare modules
    my Str:D @module = 'xxhash_generic';
    push(@module, 'i915') if $graphics eq 'INTEL';
    push(@module, 'nouveau') if $graphics eq 'NVIDIA';
    push(@module, 'radeon') if $graphics eq 'RADEON';
    # for zram lz4 compression
    push(@module, |qw<lz4 lz4_compress>);
    # replace modules
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s=(%s)}, $subject, @module.join(' '));
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'mkinitcpio.conf',
    Str:D $subject where 'HOOKS',
    DiskType:D $disk-type,
    Str:D @line
    --> Array[Str:D]
)
{
    # prepare hooks
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
    >;
    $disk-type eq 'USB'
        ?? @hooks.splice(2, 0, 'block')
        !! @hooks.splice(4, 0, 'block');
    # replace hooks
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s=(%s)}, $subject, @hooks.join(' '));
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'mkinitcpio.conf',
    Str:D $subject where 'FILES',
    Str:D @line
    --> Array[Str:D]
)
{
    # prepare files
    my Str:D @files = qw<
        /boot/volume.key
        /etc/modprobe.d/modprobe.conf
        /etc/modules-load.d/bbr.conf
    >;
    # replace files
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s=(%s)}, $subject, @files.join(' '));
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'mkinitcpio.conf',
    Str:D $subject where 'BINARIES',
    Str:D @line
    --> Array[Str:D]
)
{
    # prepare binaries
    my Str:D @binaries = '/usr/bin/btrfs';
    # replace binaries
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s=(%s)}, $subject, @binaries.join(' '));
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'mkinitcpio.conf',
    Str:D $subject where 'COMPRESSION',
    Str:D @line
    --> Array[Str:D]
)
{
    my Str:D $algorithm = 'lz4';
    my Str:D $compression = sprintf(Q{%s="%s"}, $subject, $algorithm);
    my UInt:D $index = @line.first(/^'#'$compression/, :k);
    @line[$index] = $compression;
    @line;
}

# --- end mkinitcpio.conf }}}
# --- grub {{{

multi sub replace(
    'grub',
    *@opts (
        Bool:D $disable-ipv6,
        DiskType:D $disk-type,
        Bool:D $enable-serial-console,
        Graphics:D $graphics,
        Str:D $partition-vault,
        VaultName:D $vault-name
    )
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/default/grub';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('grub', 'GRUB_CMDLINE_LINUX', |@opts)
        ==> replace('grub', 'GRUB_CMDLINE_LINUX_DEFAULT')
        ==> replace('grub', 'GRUB_DISABLE_OS_PROBER')
        ==> replace('grub', 'GRUB_DISABLE_RECOVERY')
        ==> replace('grub', 'GRUB_ENABLE_CRYPTODISK')
        ==> replace('grub', 'GRUB_TERMINAL_INPUT', $enable-serial-console)
        ==> replace('grub', 'GRUB_TERMINAL_OUTPUT', $enable-serial-console)
        ==> replace('grub', 'GRUB_SERIAL_COMMAND', $enable-serial-console);
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_CMDLINE_LINUX',
    Bool:D $disable-ipv6,
    DiskType:D $disk-type,
    Bool:D $enable-serial-console,
    Graphics:D $graphics,
    Str:D $partition-vault,
    VaultName:D $vault-name,
    Str:D @line
    --> Array[Str:D]
)
{
    # prepare GRUB_CMDLINE_LINUX
    my Str:D $vault-uuid =
        qqx<blkid --match-tag UUID --output value $partition-vault>.trim;
    my Str:D $cryptdevice = "/dev/disk/by-uuid/$vault-uuid:$vault-name";
    $cryptdevice ~= ":no-read-workqueue,no-write-workqueue" if $disk-type !eq 'HDD';
    my Str:D @grub-cmdline-linux = qqw<
        quiet
        loglevel=0
        cryptdevice=$cryptdevice
        cryptkey=rootfs:/boot/volume.key
        rootflags=subvol=@
    >;
    if $enable-serial-console.so
    {
        # e.g. console=tty0
        my Str:D $virtual =
            sprintf('console=%s', $Archvault::Utils::VIRTUAL-CONSOLE);

        # e.g. console=ttyS0,115200n8
        my Str:D $serial = sprintf(
            'console=%s,%s%s%s',
            $Archvault::Utils::SERIAL-CONSOLE,
            $Archvault::Utils::GRUB-SERIAL-PORT-BAUD-RATE,
            %Archvault::Utils::GRUB-SERIAL-PORT-PARITY{$Archvault::Utils::GRUB-SERIAL-PORT-PARITY}{$subject},
            $Archvault::Utils::GRUB-SERIAL-PORT-WORD-LENGTH-BITS
        );

        # enable both serial and virtual console on boot
        push(@grub-cmdline-linux, $virtual);
        push(@grub-cmdline-linux, $serial);
    }
    # required for use of fsck mkinitcpio hook on systemd
    push(@grub-cmdline-linux, 'rw=1');
    # disable slab merging (makes many heap overflow attacks more difficult)
    push(@grub-cmdline-linux, 'slab_nomerge=1');
    # always enable Kernel Page Table Isolation (to be safe from Meltdown)
    push(@grub-cmdline-linux, 'pti=on');
    # unprivilege RDRAND (distrusts CPU for initial entropy at boot)
    push(@grub-cmdline-linux, 'random.trust_cpu=off');
    # zero memory at allocation and free time
    push(@grub-cmdline-linux, 'init_on_alloc=1');
    push(@grub-cmdline-linux, 'init_on_free=1');
    # enable page allocator freelist randomization
    push(@grub-cmdline-linux, 'page_alloc.shuffle=1');
    # randomize kernel stack offset on syscall entry
    push(@grub-cmdline-linux, 'randomize_kstack_offset=on');
    # disable vsyscalls (inhibits return oriented programming)
    push(@grub-cmdline-linux, 'vsyscall=none');
    # restrict access to debugfs
    push(@grub-cmdline-linux, 'debugfs=off');
    # enable all mitigations for spectre variant 2
    push(@grub-cmdline-linux, 'spectre_v2=on');
    # disable speculative store bypass
    push(@grub-cmdline-linux, 'spec_store_bypass_disable=on');
    # disable TSX, enable all mitigations for TSX Async Abort
    # vulnerability, and disable SMT
    push(@grub-cmdline-linux, 'tsx=off');
    push(@grub-cmdline-linux, 'tsx_async_abort=full,nosmt');
    # enable all mitigations for MDS vulnerability and disable SMT
    push(@grub-cmdline-linux, 'mds=full,nosmt');
    # enable all mitigations for L1TF vulnerability, and disable SMT
    # and L1D flush runtime control
    push(@grub-cmdline-linux, 'l1tf=full,force');
    # force disable SMT
    push(@grub-cmdline-linux, 'nosmt=force');
    # mark all huge pages in EPT non-executable (mitigates iTLB multihit)
    push(@grub-cmdline-linux, 'kvm.nx_huge_pages=force');
    # always perform cache flush when entering guest vm (limits unintended
    # memory exposure to malicious guests)
    push(@grub-cmdline-linux, 'kvm-intel.vmentry_l1d_flush=always');
    # enable IOMMU (prevents DMA attacks)
    push(@grub-cmdline-linux, 'intel_iommu=on');
    push(@grub-cmdline-linux, 'amd_iommu=on');
    push(@grub-cmdline-linux, 'amd_iommu=force_isolation');
    push(@grub-cmdline-linux, 'iommu=force');
    # force IOMMU TLB invalidation (avoids access to stale data contents)
    push(@grub-cmdline-linux, 'iommu.passthrough=0');
    push(@grub-cmdline-linux, 'iommu.strict=1');
    # disable busmaster bit on all PCI bridges (avoids holes in IOMMU)
    push(@grub-cmdline-linux, 'efi=disable_early_pci_dma');
    # enable kernel lockdown (avoids userspace escalation to kernel mode)
    my Str:D $lsm = qw<
        landlock
        lockdown
        yama
        safesetid
        integrity
        apparmor
        bpf
    >.join(',');
    push(@grub-cmdline-linux, "lsm=$lsm");
    push(@grub-cmdline-linux, 'lockdown=confidentiality');
    # always panic on uncorrected errors, log corrected errors
    push(@grub-cmdline-linux, 'mce=0');
    push(@grub-cmdline-linux, 'printk.time=1');
    # counteract arch enabling zswap by default (see: CONFIG_ZSWAP_DEFAULT_ON=y)
    push(@grub-cmdline-linux, 'zswap.enabled=0');
    push(@grub-cmdline-linux, 'radeon.dpm=1') if $graphics eq 'RADEON';
    push(@grub-cmdline-linux, 'ipv6.disable=1') if $disable-ipv6.so;
    my Str:D $grub-cmdline-linux = @grub-cmdline-linux.join(' ');
    # replace GRUB_CMDLINE_LINUX
    my UInt:D $index = @line.first(/^$subject'='/, :k);
    my Str:D $replace = sprintf(Q{%s="%s"}, $subject, $grub-cmdline-linux);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_CMDLINE_LINUX_DEFAULT',
    Str:D @line
    --> Array[Str:D]
)
{
    # comment out C<GRUB_CMDLINE_LINUX_DEFAULT>
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $original = @line[$index];
    my Str:D $replace = sprintf(Q{#%s}, $original);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_DISABLE_OS_PROBER',
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_DISABLE_OS_PROBER> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s=true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_DISABLE_RECOVERY',
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_DISABLE_RECOVERY> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'?$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s=true}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_ENABLE_CRYPTODISK',
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_ENABLE_CRYPTODISK> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s=y}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_TERMINAL_INPUT',
    Bool:D $enable-serial-console where .so,
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_TERMINAL_INPUT> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'?$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s="console serial"}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_TERMINAL_INPUT',
    Bool:D $enable-serial-console,
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_TERMINAL_INPUT> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'?$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s="console"}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_TERMINAL_OUTPUT',
    Bool:D $enable-serial-console where .so,
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_TERMINAL_OUTPUT> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'?$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s="console serial"}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_TERMINAL_OUTPUT',
    Bool:D $enable-serial-console,
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_TERMINAL_OUTPUT> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'?$subject/, :k) // @line.elems;
    my Str:D $replace = sprintf(Q{%s="console"}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $subject where 'GRUB_SERIAL_COMMAND',
    Bool:D $enable-serial-console where .so,
    Str:D @line
    --> Array[Str:D]
)
{
    # if C<GRUB_SERIAL_COMMAND> not found, append to bottom of file
    my UInt:D $index = @line.first(/^'#'?$subject/, :k) // @line.elems;
    my Str:D $speed = $Archvault::Utils::GRUB-SERIAL-PORT-BAUD-RATE;
    my Str:D $unit = $Archvault::Utils::GRUB-SERIAL-PORT-UNIT;
    my Str:D $word = $Archvault::Utils::GRUB-SERIAL-PORT-WORD-LENGTH-BITS;
    my Str:D $parity = %Archvault::Utils::GRUB-SERIAL-PORT-PARITY{$Archvault::Utils::GRUB-SERIAL-PORT-PARITY}{$subject};
    my Str:D $stop = $Archvault::Utils::GRUB-SERIAL-PORT-STOP-BITS;
    my Str:D $grub-serial-command = qqw<
        serial
        --speed=$speed
        --unit=$unit
        --word=$word
        --parity=$parity
        --stop=$stop
    >.join(' ');
    my Str:D $replace = sprintf(Q{%s="%s"}, $subject, $grub-serial-command);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'grub',
    Str:D $ where 'GRUB_SERIAL_COMMAND',
    Bool:D $,
    Str:D @line
    --> Array[Str:D]
)
{
    @line;
}

# --- end grub }}}
# --- 10_linux {{{

multi sub replace(
    '10_linux'
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/grub.d/10_linux';
    my Str:D @line = $file.IO.lines;
    my Regex:D $regex = /'${CLASS}'\h/;
    my UInt:D @index = @line.grep($regex, :k);
    @index.race.map(-> UInt:D $index {
        @line[$index] .= subst($regex, '--unrestricted ${CLASS} ')
    });
    my Str:D $replace = @line.join("\n");
    spurt($file, $replace ~ "\n");
}

# --- end 10_linux }}}
# --- 99-sysctl.conf {{{

multi sub replace(
    '99-sysctl.conf',
    Bool:D $disable-ipv6 where .so,
    DiskType:D $disk-type where /SSD|USB/
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/sysctl.d/99-sysctl.conf';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('99-sysctl.conf', 'kernel.pid_max')
        ==> replace('99-sysctl.conf', 'net.ipv6.conf.all.disable_ipv6')
        ==> replace('99-sysctl.conf', 'net.ipv6.conf.default.disable_ipv6')
        ==> replace('99-sysctl.conf', 'net.ipv6.conf.lo.disable_ipv6')
        ==> replace('99-sysctl.conf', 'vm.mmap_rnd_bits')
        ==> replace('99-sysctl.conf', 'vm.vfs_cache_pressure')
        ==> replace('99-sysctl.conf', 'vm.swappiness');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    '99-sysctl.conf',
    Bool:D $disable-ipv6 where .so,
    DiskType:D $disk-type
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/sysctl.d/99-sysctl.conf';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('99-sysctl.conf', 'kernel.pid_max')
        ==> replace('99-sysctl.conf', 'net.ipv6.conf.all.disable_ipv6')
        ==> replace('99-sysctl.conf', 'net.ipv6.conf.default.disable_ipv6')
        ==> replace('99-sysctl.conf', 'net.ipv6.conf.lo.disable_ipv6')
        ==> replace('99-sysctl.conf', 'vm.mmap_rnd_bits');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    '99-sysctl.conf',
    Bool:D $disable-ipv6,
    DiskType:D $disk-type where /SSD|USB/
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/sysctl.d/99-sysctl.conf';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('99-sysctl.conf', 'kernel.pid_max')
        ==> replace('99-sysctl.conf', 'vm.mmap_rnd_bits')
        ==> replace('99-sysctl.conf', 'vm.vfs_cache_pressure')
        ==> replace('99-sysctl.conf', 'vm.swappiness');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    '99-sysctl.conf',
    Bool:D $disable-ipv6,
    DiskType:D $disk-type
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/sysctl.d/99-sysctl.conf';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('99-sysctl.conf', 'kernel.pid_max')
        ==> replace('99-sysctl.conf', 'vm.mmap_rnd_bits');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'kernel.pid_max',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $kernel-bits = $*KERNEL.bits;
    replace('99-sysctl.conf', $subject, @line, :$kernel-bits);
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'kernel.pid_max',
    Str:D @line,
    UInt:D :kernel-bits($)! where 64
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'$subject/, :k);
    # extract C<kernel.pid_max> value from file 99-sysctl.conf
    my Str:D $pid-max = @line[$index].split('=').map({ .trim }).tail;
    my Str:D $replace = sprintf(Q{%s = %s}, $subject, $pid-max);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'kernel.pid_max',
    Str:D @line,
    UInt:D :kernel-bits($)!
    --> Array[Str:D]
)
{
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'net.ipv6.conf.all.disable_ipv6',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 1}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'net.ipv6.conf.default.disable_ipv6',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 1}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'net.ipv6.conf.lo.disable_ipv6',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 1}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'vm.mmap_rnd_bits',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $kernel-bits = $*KERNEL.bits;
    replace('99-sysctl.conf', $subject, @line, :$kernel-bits);
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'vm.mmap_rnd_bits',
    Str:D @line,
    UInt:D :kernel-bits($)! where 32
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 16}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'vm.mmap_rnd_bits',
    Str:D @line,
    UInt:D :kernel-bits($)!
    --> Array[Str:D]
)
{
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'vm.vfs_cache_pressure',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 50}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    '99-sysctl.conf',
    Str:D $subject where 'vm.swappiness',
    Str:D @line
    --> Array[Str:D]
)
{
    my UInt:D $index = @line.first(/^'#'$subject/, :k);
    my Str:D $replace = sprintf(Q{%s = 1}, $subject);
    @line[$index] = $replace;
    @line;
}

# --- end 99-sysctl.conf }}}
# --- sshd_config {{{

multi sub replace(
    'sshd_config',
    Bool:D $disable-ipv6 where .so,
    UserName:D $user-name-sftp
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/ssh/sshd_config';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('sshd_config', 'AddressFamily')
        ==> replace('sshd_config', 'AllowUsers', $user-name-sftp)
        ==> replace('sshd_config', 'ListenAddress');
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'sshd_config',
    Bool:D $disable-ipv6,
    UserName:D $user-name-sftp
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/ssh/sshd_config';
    my Str:D @replace =
        $file.IO.lines
        ==> replace('sshd_config', 'AllowUsers', $user-name-sftp);
    my Str:D $replace = @replace.join("\n");
    spurt($file, $replace ~ "\n");
}

multi sub replace(
    'sshd_config',
    Str:D $subject where 'AddressFamily',
    Str:D @line
    --> Array[Str:D]
)
{
    # listen on IPv4 only
    my UInt:D $index = @line.first(/^$subject/, :k);
    my Str:D $replace = sprintf(Q{%s inet}, $subject);
    @line[$index] = $replace;
    @line;
}

multi sub replace(
    'sshd_config',
    Str:D $subject where 'AllowUsers',
    UserName:D $user-name-sftp,
    Str:D @line
    --> Array[Str:D]
)
{
    # put AllowUsers on the line below AddressFamily
    my UInt:D $index = @line.first(/^AddressFamily/, :k);
    my Str:D $replace = sprintf(Q{%s %s}, $subject, $user-name-sftp);
    @line.splice($index + 1, 0, $replace);
    @line;
}

multi sub replace(
    'sshd_config',
    Str:D $subject where 'ListenAddress',
    Str:D @line
    --> Array[Str:D]
)
{
    # listen on IPv4 only
    my UInt:D $index = @line.first(/^"$subject ::"/, :k);
    @line.splice($index, 1);
    @line;
}

# --- end sshd_config }}}
# --- moduli {{{

multi sub replace(
    'moduli'
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/ssh/moduli';
    my Str:D $replace =
        $file.IO.lines
        .grep(/^\w/)
        .grep({ .split(/\h+/)[4] > 3071 })
        .join("\n");
    spurt($file, $replace ~ "\n");
}

# --- end moduli }}}
# --- securetty {{{

multi sub replace(
    'securetty'
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/securetty';
    my Str:D @line = $file.IO.lines;
    my UInt:D $index =
        @line.first(/^'#'$Archvault::Utils::SERIAL-CONSOLE/, :k);
    @line[$index] = $Archvault::Utils::SERIAL-CONSOLE;
    my Str:D $replace = @line.join("\n");
    spurt($file, $replace ~ "\n");
}

# --- end securetty }}}
# --- passwd {{{

multi sub replace(
    'passwd'
    --> Nil
)
{
    my Str:D $file = '/mnt/etc/pam.d/passwd';
    my Str:D $slurp = slurp($file).trim-trailing;
    my Str:D $replace =
        sprintf(Q{%s rounds=%s}, $slurp, $Archvault::Utils::CRYPT-ROUNDS);
    spurt($file, $replace ~ "\n");
}

# --- end passwd }}}
# --- login.defs {{{

multi sub replace(
    'login.defs'
    --> Nil
)
{
    my Str:D $crypt-rounds = ~$Archvault::Utils::CRYPT-ROUNDS;
    my Str:D $crypt-scheme = $Archvault::Utils::CRYPT-SCHEME;
    my Str:D $file = '/mnt/etc/login.defs';
    my Str:D $replace = qq:to/EOF/;
    #
    # Encrypt group passwords with {$crypt-scheme}-based algorithm ($crypt-rounds SHA rounds)
    #
    ENCRYPT_METHOD $crypt-scheme
    SHA_CRYPT_MIN_ROUNDS $crypt-rounds
    SHA_CRYPT_MAX_ROUNDS $crypt-rounds
    EOF
    spurt($file, "\n" ~ $replace, :append);
}

# --- end login.defs }}}

# end sub replace }}}

# vim: set filetype=raku foldmethod=marker foldlevel=0 nowrap:
