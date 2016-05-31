use v6;
unit module Holovault::Bootstrap;

sub bootstrap() is export
{
    setup();
    mkdisk();
    pacstrap-base();
    configure-users();
    customize() if $Holovault::CONF.augment;
}

sub setup()
{
    # verify root permissions
    $*USER == 0 or die 'root priviledges required';

    # initialize pacman-keys
    run qw<haveged -w 1024>;
    run qw<pacman-key --init>;
    run qw<pacman-key --populate archlinux>;
    run qw<pkill haveged>;

    # fetch dependencies needed prior to pacstrap
    my Str @deps = qw<
        arch-install-scripts
        base-devel
        btrfs-progs
        expect
        gptfdisk
        iptables
        kbd
        reflector
    >;
    run qw<pacman -Sy --needed --noconfirm>, @deps;

    # use readable font
    run qw<setfont Lat2-Terminus16>;

    # rank mirrors
    run qw<mv /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak>;
    run qw<
        reflector
        --threads 3
        --protocol https
        --fastest 8
        --save /etc/pacman.d/mirrorlist
    >;
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
sub sgdisk(Str:D :$partition = $Holovault::CONF.partition)
{
    # erase existing partition table
    # create 2MB EF02 BIOS boot sector
    # create 128MB sized partition for /boot
    # create max sized partition for LUKS encrypted volume
    run qw<
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
    >, $partition;
}

# create vault with cryptsetup
sub mkvault(
    Str:D :$partition = $Holovault::CONF.partition,
    Str:D :$vault-name = $Holovault::CONF.vault-name
)
{
    # target partition for vault
    my Str $partition-vault = $partition ~ "3";

    # load kernel modules for cryptsetup
    run qw<modprobe dm_mod dm-crypt>;

    # was LUKS encrypted volume password given in cmdline flag?
    if my Str $vault-pass = $Holovault::CONF.vault-pass
    {
        # make LUKS encrypted volume without prompt for vault password
        shell "expect <<'EOF'
                    spawn cryptsetup --cipher aes-xts-plain64 \\
                                     --key-size 512           \\
                                     --hash sha512            \\
                                     --iter-time 5000         \\
                                     --use-random             \\
                                     --verify-passphrase      \\
                                     luksFormat $partition-vault
                    expect \"Are you sure*\" \{ send \"YES\r\" \}
                    expect \"Enter*\" \{ send \"$vault-pass\r\" \}
                    expect \"Verify*\" \{ send \"$vault-pass\r\" \}
                    expect eof
               EOF";

        # open vault without prompt for vault password
        shell "expect <<'EOF'
                    spawn cryptsetup luksOpen $partition-vault $vault-name
                    expect \"Enter*\" \{ send \"$vault-pass\r\" \}
                    expect eof
               EOF";
    }
    else
    {
        while True
        {
            # hacky output to inform user of password entry
            # context until i can implement advanced expect
            # cryptsetup luksFormat program output interception
            say 'Creating LUKS vault...';

            # create LUKS encrypted volume, prompt user for
            # vault password
            my Proc $cryptsetup-luks-format =
                shell "expect -c 'spawn cryptsetup \\
                                        --cipher aes-xts-plain64 \\
                                        --key-size 512           \\
                                        --hash sha512            \\
                                        --iter-time 5000         \\
                                        --use-random             \\
                                        --verify-passphrase      \\
                                        luksFormat $partition-vault;
                                    expect \"Are you sure*\" \{
                                    send \"YES\r\"
                                    \};
                                    interact;
                                    catch wait result;
                                    exit [lindex \$result 3]'";

            # loop until passphrases match
            # - returns exit code 0 if success
            # - returns exit code 1 if SIGINT
            # - returns exit code 2 if wrong password
            last if $cryptsetup-luks-format.exitcode == 0;
        }

        while True
        {
            # hacky output to inform user of password entry
            # context until i can implement advanced expect
            # cryptsetup luksOpen program output interception
            say 'Opening LUKS vault...';

            # open vault with prompt for vault password
            my Proc $cryptsetup-luks-open =
                shell "cryptsetup luksOpen $partition-vault $vault-name";

            # loop until passphrase works
            # - returns exit code 0 if success
            # - returns exit code 1 if SIGINT
            # - returns exit code 2 if wrong password
            last if $cryptsetup-luks-open.exitcode == 0;
        }
    }
}

# create and mount btrfs volumes on open vault
sub mkbtrfs(Str:D :$vault-name = $Holovault::CONF.vault-name)
{
    # create btrfs filesystem on opened vault
    run qqw<mkfs.btrfs /dev/mapper/$vault-name>;

    # mount main btrfs filesystem on open vault
    '/mnt2'.IO.mkdir;
    run qqw<
        mount
        -t btrfs
        -o rw,noatime,nodiratime,compress=lzo,space_cache
        /dev/mapper/$vault-name /mnt2
    >;

    # create btrfs subvolumes
    chdir '/mnt2';
    run qw<btrfs subvolume create @>;
    run qw<btrfs subvolume create @home>;
    run qw<btrfs subvolume create @opt>;
    run qw<btrfs subvolume create @srv>;
    run qw<btrfs subvolume create @tmp>;
    run qw<btrfs subvolume create @usr>;
    run qw<btrfs subvolume create @var>;
    chdir '/';

    # mount btrfs subvolumes, starting with root / ('')
    my Str @btrfs-dirs = '', 'home', 'opt', 'srv', 'tmp', 'usr', 'var';
    for @btrfs-dirs -> $btrfs-dir
    {
        "/mnt/$btrfs-dir".IO.mkdir;
        run qqw<
            mount
            -t btrfs
            -o rw,noatime,nodiratime,compress=lzo,space_cache,subvol=@$btrfs-dir
            /dev/mapper/$vault-name /mnt/$btrfs-dir
        >;
    }

    # unmount /mnt2 and remove
    run qw<umount /mnt2>;
    '/mnt2'.IO.rmdir;
}

# create and mount boot partition
sub mkbootpart(Str:D :$partition = $Holovault::CONF.partition)
{
    # target partition for boot
    my Str $partition-boot = $partition ~ 2;

    # create ext2 boot partition
    run qqw<mkfs.ext2 $partition-boot>;

    # mount ext2 boot partition in /mnt/boot
    '/mnt/boot'.IO.mkdir;
    run qqw<mount $partition-boot /mnt/boot>;
}

# bootstrap initial chroot with pacstrap
sub pacstrap-base()
{
    # base packages
    my Str @packages-base = qw<
        abs
        arch-install-scripts
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
        python2
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
    push @packages-base, 'intel-ucode' if $Holovault::CONF.processor eq 'intel';

    # download and install packages with pacman in chroot
    run qw<pacstrap /mnt>, @packages-base;
}

# secure user configuration
sub configure-users()
{
    # updating root password...
    my Str $root-pass-digest = $Holovault::CONF.root-pass-digest;
    run qqw<arch-chroot /mnt usermod -p $root-pass-digest root>;

    # creating new user with password from secure password digest...
    my Str $user-name = $Holovault::CONF.user-name;
    my Str $user-pass-digest = $Holovault::CONF.user-pass-digest;
    run qqw<
        arch-chroot
        /mnt
        useradd
        -m
        -p $user-pass-digest
        -s /bin/bash
        -g users
        -G audio,games,log,lp,network,optical,power,scanner,storage,video,wheel
        $user-name
    >;

    my Str $sudoers = qq:to/EOF/;
    $user-name ALL=(ALL) ALL
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/loadkeys
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/pacman
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/pacmatic
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/reboot
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/shutdown
    $user-name ALL=(ALL) NOPASSWD: /usr/bin/wifi-menu
    EOF
    $sudoers .= trim-trailing;
    spurt '/mnt/etc/sudoers', $sudoers, :append;
}

# interactive console
sub customize()
{
    # launch fully interactive Bash console, type 'exit' to exit
    shell 'expect -c "spawn /bin/bash; interact"';
}

# vim: ft=perl6
