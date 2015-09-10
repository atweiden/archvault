use v6;
use Holovault::Types;
unit class Holovault::Config;

# -----------------------------------------------------------------------------
# settings
# -----------------------------------------------------------------------------

# - attributes appear in specific order for prompting user
# - defaults are geared towards live media installation

# name for normal user (default: live)
has UserName $.user_name =
    %*ENV<USER_NAME> ?? self.gen_user_name(%*ENV<USER_NAME>)
                     !! prompt_name(:user);

# sha512 password digest for normal user (default: secret sha512 salt)
has Str $.user_pass_digest =
    %*ENV<USER_PASS> ?? self.gen_digest(%*ENV<USER_PASS>)
                     !! prompt_pass_digest();

# sha512 password digest for root user (default: secret sha512 salt)
has Str $.root_pass_digest =
    %*ENV<ROOT_PASS> ?? self.gen_digest(%*ENV<ROOT_PASS>)
                     !! prompt_pass_digest(:root);

# name for LUKS encrypted volume (default: vault)
has VaultName $.vault_name =
    %*ENV<VAULT_NAME> ?? self.gen_vault_name(%*ENV<VAULT_NAME>)
                      !! prompt_name(:vault);

# password for LUKS encrypted volume (default: entered manually)
has VaultPass $.vault_pass =
    %*ENV<VAULT_PASS> ?? self.gen_vault_pass(%*ENV<VAULT_PASS>)
                      !! Nil;

# name for host (default: vault)
has HostName $.host_name =
    %*ENV<HOST_NAME> ?? self.gen_host_name(%*ENV<HOST_NAME>)
                     !! prompt_name(:host);

# device path of target partition (default: /dev/sdb)
has Str $.partition = %*ENV<PARTITION> || self!prompt_partition;

# type of processor (default: other)
has Processor $.processor =
    %*ENV<PROCESSOR> ?? self.gen_processor(%*ENV<PROCESSOR>)
                     !! prompt_processor();

# type of graphics card (default: intel)
has Graphics $.graphics =
    %*ENV<GRAPHICS> ?? self.gen_graphics(%*ENV<GRAPHICS>)
                    !! prompt_graphics();

# type of hard drive (default: usb)
has DiskType $.disk_type =
    %*ENV<DISK_TYPE> ?? self.gen_disk_type(%*ENV<DISK_TYPE>)
                     !! prompt_disk_type();

# locale (default: en_US)
has Locale $.locale =
    %*ENV<LOCALE> ?? self.gen_locale(%*ENV<LOCALE>)
                  !! self!prompt_locale;

# keymap (default: us)
has Keymap $.keymap =
    %*ENV<KEYMAP> ?? self.gen_keymap(%*ENV<KEYMAP>)
                  !! self!prompt_keymap;

# timezone (default: America/Los_Angeles)
has Timezone $.timezone =
    %*ENV<TIMEZONE> ?? self.gen_timezone(%*ENV<TIMEZONE>)
                    !! self!prompt_timezone;

# directory in which to search for holograms requested (default: none)
has IO::Path $.holograms_dir =
    %*ENV<HOLOGRAMS_DIR> ?? self.gen_holograms_dir_handle(%*ENV<HOLOGRAMS_DIR>)
                         !! self!resolve_holograms_dir;

# holograms requested (default: none)
has Str @.holograms =
    %*ENV<HOLOGRAMS> ?? self.gen_holograms(%*ENV<HOLOGRAMS>)
                     !! self!prompt_holograms;

# augment (default: no)
has Bool $.augment = %*ENV<AUGMENT>.Bool || False;


# -----------------------------------------------------------------------------
# string formatting, resolution and validation
# -----------------------------------------------------------------------------

# return sha512 salt of password for linux user
method gen_digest(Str:D $password) returns Str:D
{
    my Str $digest = qqx{openssl passwd -1 -salt sha512 $password}.trim;
}

# confirm disk type $d is valid DiskType and return DiskType
method gen_disk_type(Str:D $d) returns DiskType:D
{
    my DiskType $disk_type = $d or die "Sorry, invalid disk type";
}

# confirm graphics card type $g is valid Graphics and return Graphics
method gen_graphics(Str:D $g) returns Graphics:D
{
    my Graphics $graphics = $g or die "Sorry, invalid graphics card type";
}

# split holograms space separated into array of Str and return array
method gen_holograms(Str:D $holograms) returns Array[Str:D]
{
    my Str @holograms = $holograms.split(' ');
}

# confirm directory $directory exists and is readable, and return IO::Path
method gen_holograms_dir_handle(Str:D $directory) returns IO::Path:D
{
    sub is_permissible(Str:D $directory) returns Bool
    {
        unless $directory.IO.d
        {
            say "Sorry, directory does not exist at 「$directory」";
            exit;
        }
        unless $directory.IO.r
        {
            say "Sorry, directory found at 「$directory」 is unreadable.";
            exit;
        }
        True;
    }

    my IO::Path $dir_handle = $directory.IO if is_permissible($directory);
}

# confirm hostname $h is valid HostName and return HostName
method gen_host_name(Str:D $h) returns HostName:D
{
    my HostName $host_name = $h or die "Sorry, invalid hostname";
}

# confirm keymap $k is valid Keymap and return Keymap
method gen_keymap(Str:D $k) returns Keymap:D
{
    my Keymap $keymap = $k or die "Sorry, invalid keymap";
}

# confirm locale $l is valid Locale and return Locale
method gen_locale(Str:D $l) returns Locale:D
{
    my Locale $locale = $l or die "Sorry, invalid locale";
}

# confirm processor $p is valid Processor and return Processor
method gen_processor(Str:D $p) returns Processor:D
{
    my Processor $processor = $p or die "Sorry, invalid processor";
}

# confirm timezone $t is valid Timezone and return Timezone
method gen_timezone(Str:D $t) returns Timezone:D
{
    my Timezone $timezone = $t or die "Sorry, invalid timezone";
}

# confirm user name $u is valid UserName and return UserName
method gen_user_name(Str:D $u) returns UserName:D
{
    my UserName $user_name = $u or die "Sorry, invalid username";
}

# confirm vault name $v is valid VaultName and return VaultName
method gen_vault_name(Str:D $v) returns VaultName:D
{
    my VaultName $vault_name = $v or die "Sorry, invalid vault name";
}

# confirm vault pass $v is valid VaultPass and return VaultPass
method gen_vault_pass(Str:D $v) returns VaultPass:D
{
    my VaultPass $vault_pass = $v or die "Sorry, invalid vault pass";
}

# resolve holograms dir
# does not need to return a defined IO::Path since holograms are optional
method !resolve_holograms_dir() returns IO::Path
{
    my IO::Path $dir_handle;

    # is $PWD/holograms readable?
    if my IO::Path $local_holograms_dir =
        self.gen_holograms_dir_handle('holograms')
    {
        # set dir handle to $PWD/holograms
        $dir_handle = $local_holograms_dir;
    }
    # is $HOME/.holograms readable?
    elsif my IO::Path $home_holograms_dir =
        self.gen_holograms_dir_handle("%*ENV<HOME>/.holograms")
    {
        # set dir handle to $HOME/.holograms
        $dir_handle = $home_holograms_dir;
    }
    # is /etc/holograms readable?
    elsif my IO::Path $system_holograms_dir =
        self.gen_holograms_dir_handle('/etc/holograms')
    {
        # set dir handle to /etc/holograms
        $dir_handle = $system_holograms_dir;
    }

    $dir_handle;
}


# -----------------------------------------------------------------------------
# user input prompts
# -----------------------------------------------------------------------------

sub is_valid($response, Str:D @valid_responses) returns Bool:D
{
    True;
}

sub prompt_disk_type() returns DiskType:D
{
    my DiskType $disk_type = prompt "Disk type? (hdd, ssd, usb) ";
    $disk_type = 'USB';
}

sub prompt_graphics() returns Graphics:D
{
    my Graphics $graphics = 'INTEL';
}

method !prompt_holograms() returns Array[Str:D]
{
    my Str @holograms_found = self.ls_holograms;
    my Str @holograms = "string";
}

method !prompt_keymap() returns Keymap:D
{
    # get list of keymaps
    my Keymap @keymaps = self.ls_keymaps;
    my Keymap $keymap = "us";
}

method !prompt_locale() returns Locale:D
{
    # get list of locales
    my Locale @locales = self.ls_locales;
    my Locale $locale = "en_US";
}

multi sub prompt_name(Bool :$host! where *.so) returns HostName:D
{
    my HostName $host_name = "string";
}

multi sub prompt_name(Bool :$user! where *.so) returns UserName:D
{
    my UserName $user_name = "string";
}

multi sub prompt_name(Bool :$vault! where *.so) returns VaultName:D
{
    my VaultName $vault_name = "string";
}

method !prompt_partition() returns Str:D
{
    # get list of partitions
    my Str @partitions = self.ls_partitions;
    "string";
}

# generate sha512 password digest from user input
sub prompt_pass_digest(Bool :$root) returns Str:D
{
    # sha512 digest of empty password, for verifying passwords aren't blank
    my Str $blank_pass_digest = '$1$sha512$LGta5G7pRej6dUrilUI3O.';

    # for "Enter Root / User Password" input prompts
    my Str $pass_owner = $root ?? "Root" !! "User";

    # store sha512 digest of password
    my Str $pass_digest;

    # loop until a non-blank password is entered twice in a row
    while True
    {
        # reading secure password digest into memory...
        print "Enter $pass_owner "; # Enter Root / User Password
        $pass_digest = qx{openssl passwd -1 -salt sha512}.trim;
        print "Retype $pass_owner "; # Retype Root / User Password
        my Str $pass_digest_confirm = qx{openssl passwd -1 -salt sha512}.trim;

        # verifying secure password digest...
        if $pass_digest ~~ $blank_pass_digest
        {
            # password is empty, try again
            say "$pass_owner password cannot be blank. Please try again";
            next;
        }
        elsif $pass_digest ~~ $pass_digest_confirm
        {
            last;
        }
        else
        {
            # password not verified, try again
            say "Please try again";
            next;
        }
    }

    $pass_digest;
}

sub prompt_processor() returns Processor:D
{
    my Processor $processor = 'OTHER';
}

method !prompt_timezone() returns Timezone:D
{
    # get list of timezones
    my Str @timezones = self.ls_timezones;

    # get list of timezone regions
    my Str @regions = @timezones».subst(/'/'\N*$/, '').unique;

    # prompt choose region
    my Str $region;

    # get list of timezone region subregions
    my Str @subregions =
        @timezones.grep(/$region/)».subst(/^$region'/'/, '').sort;

    # prompt choose subregion
    my Str $subregion;

    my Str $timezone = @timezones.grep("$region/$subregion").shift;
    $timezone = 'America/Los_Angeles';
}


# -----------------------------------------------------------------------------
# utilities
# -----------------------------------------------------------------------------

# list holograms
method ls_holograms(Str :$holograms_dir)
{
    my Str $dir;
    if $holograms_dir
    {
        # if holograms_dir option passed, make sure it's readable
        # if so, use it
        $dir = self.gen_holograms_dir_handle($holograms_dir).Str;
    }
    else
    {
        # if HOLOGRAMS_DIR env is set, make sure it's readable
        # otherwise use resolve holograms dir with default methodology
        $dir = %*ENV<HOLOGRAMS_DIR>
            ?? self.gen_holograms_dir_handle(%*ENV<HOLOGRAMS_DIR>).Str
            !! self!resolve_holograms_dir.Str;
    }

    # if clause because holograms dir may not resolve to anything
    my Str @holograms_found = qqx{
        find $dir -mindepth 1 -maxdepth 1 -type d | sed 's!^./!!'
    }.trim.sort if $dir;

    # return holograms only if found readable dir not empty
    @holograms_found if @holograms_found[0];
}

# list keymaps
method ls_keymaps() returns Array[Keymap:D]
{
    # equivalent to `localectl list-keymaps --no-pager`
    # see: src/basic/def.h in systemd source code
    my Keymap @keymaps = qx{
        find /usr/share/kbd/keymaps -type f \
               \( ! -name "*compose*" \)    \
            -a \( ! -name "*.doc*"    \)    \
            -a \( ! -name "*.html*"   \)    \
            -a \( ! -name "*.inc*"    \)    \
            -a \( ! -name "*.latin1*" \)    \
            -a \( ! -name "*.m4*"     \)    \
            -printf '%f\n'
    }.trim.split("\n")».subst(/'.map.gz'$/, '').sort;
}

# list locales
method ls_locales() returns Array[Locale:D]
{
    my Locale @locales = qx{
        find /usr/share/i18n/locales -type f -printf '%f\n'
    }.trim.split("\n").sort;
}

# list block devices (partitions)
method ls_partitions() returns Array[Str:D]
{
    my Str @partitions = qx{
        lsblk --output NAME --nodeps --noheadings --raw | grep -E 'sd|hd|xvd'
    }.trim;
}

# list timezones
method ls_timezones() returns Array[Timezone:D]
{
    # equivalent to `timedatectl list-timezones --no-pager`
    # see: src/basic/time-util.c in systemd source code
    my Timezone @timezones = qx{
        cat /usr/share/zoneinfo/zone.tab \
            | perl -ne 'print unless /^#/' \
            | awk '\{print $3\}'
    }.trim.split("\n").sort;
    push @timezones, "UTC";
}

# vim: ft=perl6
