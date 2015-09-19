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

# sha512 password digest for normal user
has Str $.user_pass_digest =
    %*ENV<USER_PASS> ?? self.gen_digest(%*ENV<USER_PASS>)
                     !! prompt_pass_digest();

# sha512 password digest for root user
has Str $.root_pass_digest =
    %*ENV<ROOT_PASS> ?? self.gen_digest(%*ENV<ROOT_PASS>)
                     !! prompt_pass_digest(:root);

# name for LUKS encrypted volume (default: vault)
has VaultName $.vault_name =
    %*ENV<VAULT_NAME> ?? self.gen_vault_name(%*ENV<VAULT_NAME>)
                      !! prompt_name(:vault);

# password for LUKS encrypted volume
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
                  !! prompt_locale();

# keymap (default: us)
has Keymap $.keymap =
    %*ENV<KEYMAP> ?? self.gen_keymap(%*ENV<KEYMAP>)
                  !! prompt_keymap();

# timezone (default: America/Los_Angeles)
has Timezone $.timezone =
    %*ENV<TIMEZONE> ?? self.gen_timezone(%*ENV<TIMEZONE>)
                    !! prompt_timezone();

# directory in which to search for holograms requested
has IO::Path $.holograms_dir =
    %*ENV<HOLOGRAMS_DIR> ?? self.gen_holograms_dir_handle(%*ENV<HOLOGRAMS_DIR>)
                         !! self!resolve_holograms_dir;

# holograms requested
has PkgName @.holograms =
    %*ENV<HOLOGRAMS> ?? self.gen_holograms(%*ENV<HOLOGRAMS>)
                     !! prompt_holograms();

# augment
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

# split holograms space separated into array of PkgNames and return array
method gen_holograms(Str:D $holograms) returns Array[PkgName:D]
{
    my PkgName @holograms = $holograms.split(/\s+/).unique;
}

# confirm directory $directory exists and is readable, and return IO::Path
method gen_holograms_dir_handle(Str:D $directory) returns IO::Path:D
{
    if is_permissible($directory)
    {
        my IO::Path $dir_handle = $directory.IO;
    }
    else
    {
        say "Sorry, directory 「$directory」 does not exist or is unreadable.";
        exit;
    }
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

# does directory exist and is directory readable?
sub is_permissible(Str:D $directory) returns Bool
{
    $directory.IO.d && $directory.IO.r ?? True !! False;
}

# resolve holograms dir
# does not need to return a defined IO::Path since holograms are optional
method !resolve_holograms_dir() returns IO::Path
{
    my IO::Path $dir_handle;

    # is $PWD/holograms readable?
    if is_permissible('holograms')
    {
        # set dir handle to $PWD/holograms
        $dir_handle = 'holograms'.IO;
    }
    # is $HOME/.holograms readable?
    elsif is_permissible("%*ENV<HOME>/.holograms")
    {
        # set dir handle to $HOME/.holograms
        $dir_handle = "%*ENV<HOME>/.holograms".IO;
    }
    # is /etc/holograms readable?
    elsif is_permissible('/etc/holograms')
    {
        # set dir handle to /etc/holograms
        $dir_handle = '/etc/holograms'.IO;
    }

    $dir_handle;
}


# -----------------------------------------------------------------------------
# user input prompts
# -----------------------------------------------------------------------------

# dialog menu user input prompt with tags (keys) only
multi sub dprompt(
    ::T, # type of response expected
    @menu, # menu (T $tag)
    T :$default_item! where *.defined, # default response
    Str:D :$title!, # menu title
    Str:D :$prompt_text!, # question posed to user
    Int:D :$height = 80,
    Int:D :$width = 80,
    Int:D :$menu_height = 24,
    Str:D :$confirm_topic! # context string for confirm text
) returns Any:D
{
    my T $response;

    while True
    {
        # prompt for selection
        $response = qqx!
            dialog \\
                --stdout \\
                --no-items \\
                --scrollbar \\
                --no-cancel \\
                --default-item $default_item \\
                --title '$title' \\
                --menu '$prompt_text' $height $width $menu_height @menu[]
        !;

        # confirm selection
        my Bool $confirmed = qqx!
            dialog \\
                --stdout \\
                --defaultno \\
                --title 'ARE YOU SURE?' \\
                --yesno 'Use $confirm_topic «$response»?' 8 35
        !.defined || False;

        last if $confirmed;
    }

    $response;
}

# dialog menu user input prompt with tags (keys) and items (values)
multi sub dprompt(
    ::T, # type of response expected
    %menu, # menu (T $tag => Str $item)
    T :$default_item! where *.defined, # default response
    Str:D :$title!, # menu title
    Str:D :$prompt_text!, # question posed to user
    Int:D :$height = 80,
    Int:D :$width = 80,
    Int:D :$menu_height = 24,
    Str:D :$confirm_topic! # context string for confirm text
) returns Any:D
{
    my T $response;

    while True
    {
        # prompt for selection
        $response = qqx!
            dialog \\
                --stdout \\
                --scrollbar \\
                --no-cancel \\
                --default-item $default_item \\
                --title '$title' \\
                --menu '$prompt_text' $height $width $menu_height {%menu.sort}
        !;

        # confirm selection
        my Bool $confirmed = qqx!
            dialog \\
                --stdout \\
                --defaultno \\
                --title 'ARE YOU SURE?' \\
                --yesno 'Use $confirm_topic «$response»?' 8 35
        !.defined || False;

        last if $confirmed;
    }

    $response;
}

# user input prompt (text)
sub tprompt(
    ::T, # type of response expected
    T $response_default where *.defined, # default response
    Str:D :$prompt_text!, # question posed to user
    Str :$help_text # optional help text to display before prompt
) returns Any:D
{
    my $response;

    # check for affirmative confirmation
    sub is_confirmed(Str:D $confirmation) returns Bool:D
    {
        # was response negatory or empty?
        if $confirmation ~~ /:i n[o]?/ or $confirmation.chars == 0
        {
            False;
        }
        # was response affirmative?
        elsif $confirmation ~~ /:i y[e[s]?]?/
        {
            True;
        }
        # were unrecognized characters entered?
        else
        {
            False;
        }
    }

    while True
    {
        # display help text (optional)
        say $help_text if $help_text;

        # prompt for response
        $response = prompt $prompt_text;

        # if empty carriage return entered, use default response value
        unless $response
        {
            $response = $response_default;
        }

        # retry if response is invalid
        unless $response ~~ T
        {
            say 'Sorry, invalid response. Please try again.';
            next;
        }

        # prompt for confirmation
        my Str $confirmation =
            prompt "Confirm «{$response.split(/\s+/).join(', ')}» [y/N]: ";
        last if is_confirmed($confirmation);
    }

    $response;
}

sub prompt_disk_type() returns DiskType:D
{
    my DiskType $default_item = 'USB';
    my Str $prompt_text = 'Select disk type:';
    my Str $title = 'DISK TYPE SELECTION';
    my Str $confirm_topic = 'disk type selected';

    my DiskType $disk_type = dprompt(
        DiskType,
        %Holovault::Types::disktypes,
        :$default_item,
        :$prompt_text,
        :$title,
        :$confirm_topic
    );
}

sub prompt_graphics() returns Graphics:D
{
    my Graphics $default_item = 'INTEL';
    my Str $prompt_text = 'Select graphics card type:';
    my Str $title = 'GRAPHICS CARD TYPE SELECTION';
    my Str $confirm_topic = 'graphics card type selected';

    my Graphics $graphics = dprompt(
        Graphics,
        %Holovault::Types::graphics,
        :$default_item,
        :$prompt_text,
        :$title,
        :$confirm_topic
    );
}

sub prompt_holograms()
{
    # default response
    my Str $response_default = "";

    # prompt text
    my Str $prompt_text = "Holograms (optional): ";

    # help text
    my Str $help_text = q:to/EOF/;
    Determining holograms requested...

    Enter pkgname of holograms, space-separated, e.g. hologram-simple
    or configure-ovpn

    Leave blank if you don't want any or don't know what this is
    EOF
    $help_text .= trim;

    my PkgName @holograms;
    while True
    {
        # prompt user
        my Str @h = tprompt(
            Str,
            $response_default,
            :$prompt_text,
            :$help_text
        ).split(/\s+/).unique;

        # don't return anything if user input carriage return
        last if @h[0] ~~ "";

        # were all holograms input valid pkgnames (hologram names)?
        if @h.grep(PkgName).elems == @h.elems
        {
            @holograms = @h;
            last;
        }
        # user must've input at least one invalid hologram name
        else
        {
            # display non-fatal error message and loop
            my Str @invalid_hologram_names = (@h (-) @h.grep(PkgName)).keys;
            my Str $msg = qq:to/EOF/;
            Sorry, invalid hologram name(s) given:

            {@invalid_hologram_names.join(', ')}

            Please try again.
            EOF
            say $msg.trim;
        }
    }

    # optionally return holograms if user input valid holograms
    @holograms if @holograms;
}

sub prompt_keymap() returns Keymap:D
{
    my Keymap $default_item = 'us';
    my Str $prompt_text = 'Select keymap:';
    my Str $title = 'KEYMAP SELECTION';
    my Str $confirm_topic = 'keymap selected';

    my Keymap $keymap = dprompt(
        Keymap,
        %Holovault::Types::keymaps,
        :$default_item,
        :$prompt_text,
        :$title,
        :$confirm_topic
    );
}

sub prompt_locale() returns Locale:D
{
    my Locale $default_item = 'en_US';
    my Str $prompt_text = 'Select locale:';
    my Str $title = 'LOCALE SELECTION';
    my Str $confirm_topic = 'locale selected';

    my Locale $locale = dprompt(
        Locale,
        %Holovault::Types::locales,
        :$default_item,
        :$prompt_text,
        :$title,
        :$confirm_topic
    );
}

multi sub prompt_name(Bool :$host! where *.so) returns HostName:D
{
    # default response
    my HostName $response_default = "vault";

    # prompt text
    my Str $prompt_text = "Enter hostname [vault]: ";

    # help text
    my Str $help_text = q:to/EOF/;
    Determining hostname...

    Leave blank if you don't know what this is
    EOF
    $help_text .= trim;

    # prompt user
    my HostName $host_name = tprompt(
        HostName,
        $response_default,
        :$prompt_text,
        :$help_text
    );
}

multi sub prompt_name(Bool :$user! where *.so) returns UserName:D
{
    # default response
    my UserName $response_default = "live";

    # prompt text
    my Str $prompt_text = "Enter username [live]: ";

    # help text
    my Str $help_text = q:to/EOF/;
    Determining username...

    Leave blank if you don't know what this is
    EOF
    $help_text .= trim;

    # prompt user
    my UserName $user_name = tprompt(
        UserName,
        $response_default,
        :$prompt_text,
        :$help_text
    );
}

multi sub prompt_name(Bool :$vault! where *.so) returns VaultName:D
{
    # default response
    my VaultName $response_default = "vault";

    # prompt text
    my Str $prompt_text = "Enter vault name [vault]: ";

    # help text
    my Str $help_text = q:to/EOF/;
    Determining name of LUKS encrypted volume...

    Leave blank if you don't know what this is
    EOF
    $help_text .= trim;

    # prompt user
    my VaultName $vault_name = tprompt(
        VaultName,
        $response_default,
        :$prompt_text,
        :$help_text
    );
}

method !prompt_partition() returns Str:D
{
    # get list of partitions
    my Str @partitions = self.ls_partitions.map({ $_ = "/dev/$_" });

    my Str $default_item = '/dev/sdb';
    my Str $prompt_text = 'Select partition for installing Arch:';
    my Str $title = 'PARTITION SELECTION';
    my Str $confirm_topic = 'partition selected';

    my Str $partition = dprompt(
        Str,
        @partitions,
        :$default_item,
        :$prompt_text,
        :$title,
        :$confirm_topic
    );
}

# generate sha512 password digest from user input
sub prompt_pass_digest(Bool :$root) returns Str:D
{
    # sha512 digest of empty password, for verifying passwords aren't blank
    my Str $blank_pass_digest = '$1$sha512$LGta5G7pRej6dUrilUI3O.';

    # for "Enter Root / User Password" input prompts
    my Str $subject = $root ?? "Root" !! "User";

    # store sha512 digest of password
    my Str $pass_digest;

    # loop until a non-blank password is entered twice in a row
    while True
    {
        # reading secure password digest into memory...
        print "Enter $subject "; # Enter Root / User Password
        $pass_digest = qx{openssl passwd -1 -salt sha512}.trim;

        # verifying secure password digest is not empty...
        if $pass_digest ~~ $blank_pass_digest
        {
            # password is empty, try again
            say "$subject password cannot be blank. Please try again";
            next;
        }

        # verifying secure password digest...
        print "Retype $subject "; # Retype Root / User Password
        my Str $pass_digest_confirm = qx{openssl passwd -1 -salt sha512}.trim;
        if $pass_digest ~~ $pass_digest_confirm
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
    my Processor $default_item = 'OTHER';
    my Str $prompt_text = 'Select processor:';
    my Str $title = 'PROCESSOR SELECTION';
    my Str $confirm_topic = 'processor selected';

    my Processor $processor = dprompt(
        Processor,
        %Holovault::Types::processors,
        :$default_item,
        :$prompt_text,
        :$title,
        :$confirm_topic
    );
}

sub prompt_timezone() returns Timezone:D
{
    # get list of timezones
    my Timezone @timezones = @Holovault::Types::timezones;

    # get list of timezone regions
    my Str @regions = @timezones».subst(/'/'\N*$/, '').unique;

    # prompt choose region
    my Str $region;
    {
        my Str $default_item = 'America';
        my Str $prompt_text = 'Select region:';
        my Str $title = 'TIMEZONE REGION SELECTION';
        my Str $confirm_topic = 'timezone region selected';

        $region = dprompt(
            Str,
            @regions,
            :$default_item,
            :$prompt_text,
            :$title,
            :$confirm_topic
        );
    }

    # get list of timezone region subregions
    my Str @subregions =
        @timezones.grep(/$region/)».subst(/^$region'/'/, '').sort;

    # prompt choose subregion
    my Str $subregion;
    {
        my Str $default_item = 'Los_Angeles';
        my Str $prompt_text = 'Select subregion:';
        my Str $title = 'TIMEZONE SUBREGION SELECTION';
        my Str $confirm_topic = 'timezone subregion selected';

        $subregion = dprompt(
            Str,
            @subregions,
            :$default_item,
            :$prompt_text,
            :$title,
            :$confirm_topic
        );
    }

    my Timezone $timezone = @timezones.grep("$region/$subregion")[0];
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
        lsblk --output NAME --nodeps --noheadings --raw
    }.trim.split("\n").sort;
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
