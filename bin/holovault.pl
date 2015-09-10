#!/usr/bin/perl6




use v6;




# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------

multi sub MAIN(
    'install',
    Bool :$augment,
    Str :$disktype,
    Str :$graphics,
    Str :$holograms,
    Str :$holograms-dir,
    Str :$hostname,
    Str :$keymap,
    Str :$locale,
    Str :$partition,
    Str :$processor,
    Str :$rootpass,
    Str :$timezone,
    Str :$username,
    Str :$userpass,
    Str :$vaultname,
    Str :$vaultpass,
)
{
    use Holovault::Config;
    our $CONF;

    # setup with type checking
    {
        my %cfg;

        # if --augment, initialize $CONF.augment to True
        %cfg<augment> = $augment if $augment;

        # if --disktype, initialize $CONF.disk_type to DiskType
        %cfg<disk_type> = Holovault::Config.gen_disk_type($disktype)
            if $disktype;

        # if --graphics, initialize $CONF.graphics to Graphics
        %cfg<graphics> = Holovault::Config.gen_graphics($graphics) if $graphics;

        # if --holograms, initialize $CONF.holograms to space split array
        %cfg<holograms> = Holovault::Config.gen_holograms($holograms)
            if $holograms;

        # if --holograms-dir, ensure dir is readable and initialze
        # $CONF.holograms_dir to IO::Handle
        %cfg<holograms_dir> =
            Holovault::Config.gen_holograms_dir_handle($holograms-dir)
                if $holograms-dir;

        # if --hostname, initialize $CONF.hostname to HostName
        %cfg<hostname> = Holovault::Config.gen_host_name($hostname)
            if $hostname;

        # if --keymap, initialize $CONF.keymap to Keymap
        %cfg<keymap> = Holovault::Config.gen_keymap($keymap) if $keymap;

        # if --locale, initialize $CONF.locale to Locale
        %cfg<locale> = Holovault::Config.gen_locale($locale) if $locale;

        # if --vaultname, initialize $CONF.vault_name to VaultName
        %cfg<vault_name> = Holovault::Config.gen_vault_name($vaultname)
            if $vaultname;

        # if --vaultpass, initialize $CONF.vault_pass to VaultPass
        %cfg<vault_pass> = Holovault::Config.gen_vault_pass($vaultpass)
            if $vaultpass;

        # if --partition, initialize $CONF.partition to Partition
        %cfg<partition> = $partition if $partition;

        # if --processor, initialize $CONF.processor to Processor
        %cfg<processor> = Holovault::Config.gen_processor($processor)
            if $processor;

        # if --rootpass, initialize $CONF.root_pass_diges to sha512 digest
        %cfg<root_pass_digest> = Holovault::Config.gen_digest($rootpass)
            if $rootpass;

        # if --timezone, initialize $CONF.timezone to Timezone
        %cfg<timezone> = Holovault::Config.gen_timezone($timezone) if $timezone;

        # if --username, initialize $CONF.user_name to UserName
        %cfg<user_name> = Holovault::Config.gen_user_name($username)
            if $username;

        # if --userpass, initialize $CONF.user_pass_digest to sha512 digest
        %cfg<user_pass_digest> = Holovault::Config.gen_digest($userpass)
            if $userpass;

        # instantiate global config, prompting for user input as needed
        $CONF = Holovault::Config.new(|%cfg);
    }

    say $CONF.perl;

    # secure disk configuration
    sub configure_disk()
    {
        # partition disk with gdisk
        sub mkdisk(Str:D :$partition = $CONF.partition)
        {
            # erase existing partition table
            # create 2MB EF02 BIOS boot sector
            # create 128MB sized partition for /boot
            # create max sized partition for LUKS encrypted volume
            shell "sgdisk --zap-all --clear --mbrtogpt \
                          --new=1:0:+2M --typecode=1:EF02 \
                          --new=2:0:+128M --typecode=2:8300 \
                          --new=3:0:0 --typecode=3:8300 $partition";
        }

        # partition disk
        mkdisk();

        # create vault with cryptsetup
        sub mkvault(
            Str:D :$partition = $CONF.partition,
            Str:D :$vault_name = $CONF.vault_name
        )
        {
            # target partition for vault
            my Str $partition_vault = $partition ~ "3";

            # load kernel modules for cryptsetup
            shell 'modprobe dm_mod dm-crypt';

            # was LUKS encrypted volume password given in cmdline flag?
            if my Str $vault_pass = $CONF.vault_pass
            {
                # make LUKS encrypted volume without prompt for vault password
                shell "expect <<'EOF'
                         spawn cryptsetup --cipher aes-xts-plain64 \
                                          --key-size 512           \
                                          --hash sha512            \
                                          --iter-time 5000         \
                                          --use-random             \
                                          --verify-passphrase      \
                                          luksFormat $partition_vault
                         expect \"Are you sure*\" \{ send \"YES\r\" \}
                         expect \"Enter*\" \{ send \"$vault_pass\r\" \}
                         expect \"Verify*\" \{ send \"$vault_pass\r\" \}
                         expect eof
                       EOF";

                # open vault without prompt for vault password
                shell "expect <<'EOF'
                         spawn cryptsetup luksOpen $partition_vault $vault_name
                         expect \"Enter*\" \{ send \"$vault_pass\r\" \}
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
                    say "Creating LUKS vault...";

                    # create LUKS encrypted volume, prompt user for
                    # vault password
                    my Proc $cryptsetup_luks_format =
                        shell "expect -c 'spawn cryptsetup \
                                              --cipher aes-xts-plain64 \
                                              --key-size 512           \
                                              --hash sha512            \
                                              --iter-time 5000         \
                                              --use-random             \
                                              --verify-passphrase      \
                                              luksFormat $partition_vault;
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
                    last if $cryptsetup_luks_format.exitcode == 0;
                }

                while True
                {
                    # hacky output to inform user of password entry
                    # context until i can implement advanced expect
                    # cryptsetup luksOpen program output interception
                    say "Opening LUKS vault...";

                    # open vault with prompt for vault password
                    my Proc $cryptsetup_luks_open =
                        shell "cryptsetup luksOpen $partition_vault \
                                 $vault_name";

                    # loop until passphrase works
                    # - returns exit code 0 if success
                    # - returns exit code 1 if SIGINT
                    # - returns exit code 2 if wrong password
                    last if $cryptsetup_luks_open.exitcode == 0;
                }
            }
        }

        # create vault
        mkvault();

        # create and mount btrfs volumes on open vault
        sub mkbtrfs(Str:D :$vault_name = $CONF.vault_name)
        {
            # create btrfs filesystem on opened vault
            shell "mkfs.btrfs /dev/mapper/$vault_name";

            # mount main btrfs filesystem on open vault
            '/mnt2'.IO.mkdir;
            shell "mount \
                     -t btrfs \
                     -o rw,noatime,nodiratime,compress=lzo,space_cache \
                     /dev/mapper/$vault_name /mnt2";

            # create btrfs subvolumes
            chdir '/mnt2';
            shell 'btrfs subvolume create @';
            shell 'btrfs subvolume create @home';
            shell 'btrfs subvolume create @opt';
            shell 'btrfs subvolume create @srv';
            shell 'btrfs subvolume create @usr';
            shell 'btrfs subvolume create @var';
            chdir '/';

            # mount btrfs subvolumes, starting with root / ('')
            my Str @btrfs_dirs = '', 'home', 'opt', 'srv', 'usr', 'var';
            for @btrfs_dirs -> $btrfs_dir
            {
                "/mnt/$btrfs_dir".IO.mkdir;
                shell "mount \
                         -t btrfs \
                         -o rw, \
                            noatime, \
                            nodiratime, \
                            compress=lzo, \
                            space_cache, \
                            subvol=@$btrfs_dir \
                         /dev/mapper/$vault_name /mnt/$btrfs_dir";
            }

            # unmount /mnt2 and remove
            shell 'umount /mnt2';
            '/mnt2'.IO.rmdir;
        }

        # create and mount btrfs volumes
        mkbtrfs();

        # create and mount boot partition
        sub mkbootpart(Str:D :$partition = $CONF.partition)
        {
            # target partition for boot
            my Str $partition_boot = $partition ~ 2;

            # create ext2 boot partition
            shell "mkfs.ext2 $partition_boot";

            # mount ext2 boot partition in /mnt/boot
            '/mnt/boot'.IO.mkdir;
            shell "mount $partition_boot /mnt/boot";
        }

        # create boot partition
        mkbootpart();
    }

    # bootstrap initial chroot with pacstrap
    sub pacstrap_base()
    {
        # base packages
        my Str @packages_base =
            'abs',
            'arch-install-scripts',
            'base',
            'base-devel',
            'bash-completion',
            'btrfs-progs',
            'ca-certificates',
            'cronie',
            'dhclient',
            'dialog',
            'dnscrypt-proxy',
            'ed',
            'ethtool',
            'expect',
            'gptfdisk',
            'grub-bios',
            'haveged',
            'iproute2',
            'iptables',
            'iw',
            'kbd',
            'kexec-tools',
            'net-tools',
            'openresolv',
            'openssh',
            'python2',
            'reflector',
            'rsync',
            'sshpass',
            'systemd-swap',
            'tmux',
            'unzip',
            'wget',
            'wireless_tools',
            'wpa_actiond',
            'wpa_supplicant',
            'zip',
            'zsh';

        # https://www.archlinux.org/news/changes-to-intel-microcodeupdates/
        push @packages_base, 'intel-ucode' if $CONF.processor ~~ 'intel';

        # download and install packages with pacman in chroot
        shell "pacstrap /mnt @packages_base[]";
    }

    # secure user configuration
    sub configure_users()
    {
        # updating root password...
        my Str $root_pass_digest = $CONF.root_pass_digest;
        shell "arch-chroot /mnt usermod -p '$root_pass_digest' root";

        # creating new user with password from secure password digest...
        my Str $user_name = $CONF.user_name;
        my Str $user_pass_digest = $CONF.user_pass_digest;
        shell "arch-chroot /mnt useradd \
                                  -m \
                                  -p '$user_pass_digest' \
                                  -s /bin/bash \
                                  -g users \
                                  -G audio, \
                                     games, \
                                     log, \
                                     lp, \
                                     network, \
                                     optical, \
                                     power, \
                                     scanner, \
                                     storage, \
                                     video, \
                                     wheel \
                                  $user_name";
    }

    sub customize()
    {
        # launch fully interactive Bash console, type 'exit' to exit
        shell "expect -c 'spawn /bin/bash; interact'" if $CONF.augment;
    }
}




# -----------------------------------------------------------------------------
# utilities
# -----------------------------------------------------------------------------

multi sub MAIN('ls', 'holograms', Str :$holograms-dir)
{
    .say for Holovault::Config.ls_holograms(:holograms_dir($holograms-dir));
}
multi sub MAIN('ls', 'keymaps') { .say for Holovault::Config.ls_keymaps; }
multi sub MAIN('ls', 'locales') { .say for Holovault::Config.ls_locales; }
multi sub MAIN('ls', 'partitions') { .say for Holovault::Config.ls_partitions; }
multi sub MAIN('ls', 'timezones') { .say for Holovault::Config.ls_timezones; }




# -----------------------------------------------------------------------------
# version
# -----------------------------------------------------------------------------

constant $VERSION = "0.0.1";
multi sub MAIN(Bool:D :$version! where *.so) { say $VERSION; exit; }




# -----------------------------------------------------------------------------
# usage
# -----------------------------------------------------------------------------

sub USAGE()
{
    constant $HELP = q:to/EOF/;
    Usage:
      holovault [-h]
      holovault --holograms="skreltoi amnesia"        \
                --username="live"                     \
                --userpass="your new user's password" \
                --rootpass="your root password"       \
                --vaultname="luckbox"                 \
                --vaultpass="your vault password"     \
                --hostname="luckbox"                  \
                --partition="/dev/sdb"                \
                --processor="other"                   \
                --graphics="intel"                    \
                --disktype="usb"                      \
                --locale="en_US"                      \
                --keymap="us"                         \
                --timezone="America/Los_Angeles"      \
                --augment                             \
                install

    positional arguments:
      <command>
        install                   Bootstrap Arch system with Holo
        ls                        List discovered holograms, keymaps, locales,
                                  partitions, timezones

    optional arguments:
      --augment                   drop to Bash console mid-execution
      --disktype=DISK_TYPE        hard drive type
      --graphics=GRAPHICS         graphics card type
      --holograms=HOLOGRAMS       holograms (space separated)
      --holograms-dir=DIR_PATH    path to dir containing hologram subdirs
      --hostname=HOSTNAME         hostname
      --keymap=KEYMAP             keymap
      --locale=LOCALE             locale
      --partition=DEVICE_PATH     partition target for install
      --processor=PROCESSOR       processor type
      --rootpass=PASSWORD         root password
      --timezone=TIMEZONE         timezone
      --username=USERNAME         user name
      --userpass=PASSWORD         user password
      --vaultname=VAULT_NAME      vault name
      --vaultpass=PASSWORD        vault password
      --version                   print version and exit
    EOF
    say $HELP.trim;
}

# vim: ft=perl6
