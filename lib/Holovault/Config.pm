use v6;
use Holovault::Types;
unit class Holovault::Config;

# -----------------------------------------------------------------------------
# settings
# -----------------------------------------------------------------------------

# - attributes appear in specific order for prompting user
# - defaults are geared towards live media installation

# name for normal user (default: live)
has UserName:D $.user-name =
    %*ENV<USER_NAME> ?? self.gen-user-name(%*ENV<USER_NAME>)
                     !! prompt-name(:user);

# sha512 password digest for normal user
has Str:D $.user-pass-digest =
    %*ENV<USER_PASS> ?? self.gen-digest(%*ENV<USER_PASS>)
                     !! prompt-pass-digest();

# sha512 password digest for root user
has Str:D $.root-pass-digest =
    %*ENV<ROOT_PASS> ?? self.gen-digest(%*ENV<ROOT_PASS>)
                     !! prompt-pass-digest(:root);

# name for LUKS encrypted volume (default: vault)
has VaultName:D $.vault-name =
    %*ENV<VAULT_NAME> ?? self.gen-vault-name(%*ENV<VAULT_NAME>)
                      !! prompt-name(:vault);

# password for LUKS encrypted volume
has VaultPass:D $.vault-pass =
    %*ENV<VAULT_PASS> ?? self.gen-vault-pass(%*ENV<VAULT_PASS>)
                      !! Nil;

# name for host (default: vault)
has HostName:D $.host-name =
    %*ENV<HOST_NAME> ?? self.gen-host-name(%*ENV<HOST_NAME>)
                     !! prompt-name(:host);

# device path of target partition (default: /dev/sdb)
has Str:D $.partition = %*ENV<PARTITION> || self!prompt-partition;

# type of processor (default: other)
has Processor:D $.processor =
    %*ENV<PROCESSOR> ?? self.gen-processor(%*ENV<PROCESSOR>)
                     !! prompt-processor();

# type of graphics card (default: intel)
has Graphics:D $.graphics =
    %*ENV<GRAPHICS> ?? self.gen-graphics(%*ENV<GRAPHICS>)
                    !! prompt-graphics();

# type of hard drive (default: usb)
has DiskType:D $.disk-type =
    %*ENV<DISK_TYPE> ?? self.gen-disk-type(%*ENV<DISK_TYPE>)
                     !! prompt-disk-type();

# locale (default: en_US)
has Locale:D $.locale =
    %*ENV<LOCALE> ?? self.gen-locale(%*ENV<LOCALE>)
                  !! prompt-locale();

# keymap (default: us)
has Keymap:D $.keymap =
    %*ENV<KEYMAP> ?? self.gen-keymap(%*ENV<KEYMAP>)
                  !! prompt-keymap();

# timezone (default: America/Los_Angeles)
has Timezone:D $.timezone =
    %*ENV<TIMEZONE> ?? self.gen-timezone(%*ENV<TIMEZONE>)
                    !! prompt-timezone();

# directory in which to search for holograms requested
has IO::Path:D $.holograms-dir =
    %*ENV<HOLOGRAMS_DIR> ?? self.gen-holograms-dir-handle(%*ENV<HOLOGRAMS_DIR>)
                         !! self!resolve-holograms-dir;

# holograms requested
has PkgName:D @.holograms =
    %*ENV<HOLOGRAMS> ?? self.gen-holograms(%*ENV<HOLOGRAMS>)
                     !! prompt-holograms();

# augment
has Bool:D $.augment = ?%*ENV<AUGMENT>;


# -----------------------------------------------------------------------------
# string formatting, resolution and validation
# -----------------------------------------------------------------------------

# return sha512 salt of password for linux user
method gen-digest(Str:D $password) returns Str:D
{
    my Str:D $digest = qqx{openssl passwd -1 -salt sha512 $password}.trim;
}

# confirm disk type $d is valid DiskType and return DiskType
method gen-disk-type(Str:D $d) returns DiskType:D
{
    my DiskType:D $disk-type = $d or die "Sorry, invalid disk type";
}

# confirm graphics card type $g is valid Graphics and return Graphics
method gen-graphics(Str:D $g) returns Graphics:D
{
    my Graphics:D $graphics = $g or die "Sorry, invalid graphics card type";
}

# split holograms space separated into array of PkgNames and return array
method gen-holograms(Str:D $holograms) returns Array[PkgName:D]
{
    my PkgName:D @holograms = $holograms.split(/\s+/).unique;
}

# confirm directory $directory exists and is readable, and return IO::Path
method gen-holograms-dir-handle(Str:D $directory) returns IO::Path:D
{
    unless is-permissible($directory)
    {
        die "Sorry, directory 「$directory」 does not exist or is unreadable.";
    }
    my IO::Path:D $dir-handle = $directory.IO;
}

# confirm hostname $h is valid HostName and return HostName
method gen-host-name(Str:D $h) returns HostName:D
{
    my HostName:D $host-name = $h or die "Sorry, invalid hostname 「$h」";
}

# confirm keymap $k is valid Keymap and return Keymap
method gen-keymap(Str:D $k) returns Keymap:D
{
    my Keymap:D $keymap = $k or die "Sorry, invalid keymap 「$k」";
}

# confirm locale $l is valid Locale and return Locale
method gen-locale(Str:D $l) returns Locale:D
{
    my Locale:D $locale = $l or die "Sorry, invalid locale 「$l」";
}

# confirm processor $p is valid Processor and return Processor
method gen-processor(Str:D $p) returns Processor:D
{
    my Processor:D $processor = $p or die "Sorry, invalid processor 「$p」";
}

# confirm timezone $t is valid Timezone and return Timezone
method gen-timezone(Str:D $t) returns Timezone:D
{
    my Timezone:D $timezone = $t or die "Sorry, invalid timezone 「$t」";
}

# confirm user name $u is valid UserName and return UserName
method gen-user-name(Str:D $u) returns UserName:D
{
    my UserName:D $user-name = $u or die "Sorry, invalid username 「$u」";
}

# confirm vault name $v is valid VaultName and return VaultName
method gen-vault-name(Str:D $v) returns VaultName:D
{
    my VaultName:D $vault-name = $v or die "Sorry, invalid vault name 「$v」";
}

# confirm vault pass $v is valid VaultPass and return VaultPass
method gen-vault-pass(Str:D $v) returns VaultPass:D
{
    my VaultPass:D $vault-pass = $v
        or die "Sorry, invalid vault pass."
            ~ " Length needed: 1-512. Length given: {$v.chars}";
}

# does directory exist and is directory readable?
sub is-permissible(Str:D $directory) returns Bool:D
{
    $directory.IO.d && $directory.IO.r;
}

# resolve holograms dir
# does not need to return a defined IO::Path since holograms are optional
method !resolve-holograms-dir() returns IO::Path
{
    my IO::Path $dir-handle;

    # is $PWD/holograms readable?
    if is-permissible('holograms')
    {
        # set dir handle to $PWD/holograms
        $dir-handle = 'holograms'.IO;
    }
    # is $HOME/.holograms readable?
    elsif is-permissible("%*ENV<HOME>/.holograms")
    {
        # set dir handle to $HOME/.holograms
        $dir-handle = "%*ENV<HOME>/.holograms".IO;
    }
    # is /etc/holograms readable?
    elsif is-permissible('/etc/holograms')
    {
        # set dir handle to /etc/holograms
        $dir-handle = '/etc/holograms'.IO;
    }

    $dir-handle;
}


# -----------------------------------------------------------------------------
# user input prompts
# -----------------------------------------------------------------------------

# dialog menu user input prompt with tags (keys) only
multi sub dprompt(
    ::T, # type of response expected
    @menu, # menu (T $tag)
    T :$default-item! where *.defined, # default response
    Str:D :$title!, # menu title
    Str:D :$prompt-text!, # question posed to user
    UInt:D :$height = 80,
    UInt:D :$width = 80,
    UInt:D :$menu-height = 24,
    Str:D :$confirm-topic! # context string for confirm text
) returns Any:D
{
    my T $response;

    loop
    {
        # prompt for selection
        $response = qqx!
            dialog \\
                --stdout \\
                --no-items \\
                --scrollbar \\
                --no-cancel \\
                --default-item $default-item \\
                --title '$title' \\
                --menu '$prompt-text' $height $width $menu-height @menu[]
        !;

        # confirm selection
        my Bool:D $confirmed = shell("
            dialog \\
                --stdout \\
                --defaultno \\
                --title 'ARE YOU SURE?' \\
                --yesno 'Use $confirm-topic «$response»?' 8 35
        ").exitcode == 0;

        last if $confirmed;
    }

    $response;
}

# dialog menu user input prompt with tags (keys) and items (values)
multi sub dprompt(
    ::T, # type of response expected
    %menu, # menu (T $tag => Str $item)
    T :$default-item! where *.defined, # default response
    Str:D :$title!, # menu title
    Str:D :$prompt-text!, # question posed to user
    UInt:D :$height = 80,
    UInt:D :$width = 80,
    UInt:D :$menu-height = 24,
    Str:D :$confirm-topic! # context string for confirm text
) returns Any:D
{
    my T $response;

    loop
    {
        # prompt for selection
        $response = qqx!
            dialog \\
                --stdout \\
                --scrollbar \\
                --no-cancel \\
                --default-item $default-item \\
                --title '$title' \\
                --menu '$prompt-text' $height $width $menu-height {%menu.sort}
        !;

        # confirm selection
        my Bool:D $confirmed = shell("
            dialog \\
                --stdout \\
                --defaultno \\
                --title 'ARE YOU SURE?' \\
                --yesno 'Use $confirm-topic «$response»?' 8 35
        ").exitcode == 0;

        last if $confirmed;
    }

    $response;
}

# user input prompt (text)
sub tprompt(
    ::T, # type of response expected
    T $response-default where *.defined, # default response
    Str:D :$prompt-text!, # question posed to user
    Str :$help-text # optional help text to display before prompt
) returns Any:D
{
    my $response;

    # check for affirmative confirmation
    sub is-confirmed(Str:D $confirmation) returns Bool:D
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

    loop
    {
        # display help text (optional)
        say $help-text if $help-text;

        # prompt for response
        $response = prompt $prompt-text;

        # if empty carriage return entered, use default response value
        unless $response
        {
            $response = $response-default;
        }

        # retry if response is invalid
        unless $response ~~ T
        {
            say 'Sorry, invalid response. Please try again.';
            next;
        }

        # prompt for confirmation
        my Str:D $confirmation =
            prompt "Confirm «{$response.split(/\s+/).join(', ')}» [y/N]: ";
        last if is-confirmed($confirmation);
    }

    $response;
}

sub prompt-disk-type() returns DiskType:D
{
    my DiskType:D $default-item = 'USB';
    my Str:D $prompt-text = 'Select disk type:';
    my Str:D $title = 'DISK TYPE SELECTION';
    my Str:D $confirm-topic = 'disk type selected';

    my DiskType:D $disk-type = dprompt(
        DiskType,
        %Holovault::Types::disktypes,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-graphics() returns Graphics:D
{
    my Graphics:D $default-item = 'INTEL';
    my Str:D $prompt-text = 'Select graphics card type:';
    my Str:D $title = 'GRAPHICS CARD TYPE SELECTION';
    my Str:D $confirm-topic = 'graphics card type selected';

    my Graphics:D $graphics = dprompt(
        Graphics,
        %Holovault::Types::graphics,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-holograms()
{
    # default response
    my Str:D $response-default = "";

    # prompt text
    my Str:D $prompt-text = "Holograms (optional): ";

    # help text
    my Str:D $help-text = q:to/EOF/;
    Determining holograms requested...

    Enter pkgname of holograms, space-separated, e.g. hologram-simple
    or configure-ovpn

    Leave blank if you don't want any or don't know what this is
    EOF
    $help-text .= trim;

    my PkgName:D @holograms;
    loop
    {
        # prompt user
        my Str:D @h = tprompt(
            Str,
            $response-default,
            :$prompt-text,
            :$help-text
        ).split(/\s+/).unique;

        # don't return anything if user input carriage return
        last if @h[0] ~~ "";

        # were all holograms input valid pkgnames (hologram names)?
        if @h.grep(PkgName:D).elems == @h.elems
        {
            @holograms = @h;
            last;
        }
        # user must've input at least one invalid hologram name
        else
        {
            # display non-fatal error message and loop
            my Str:D @invalid-hologram-names = (@h (-) @h.grep(PkgName:D)).keys;
            my Str:D $msg = qq:to/EOF/;
            Sorry, invalid hologram name(s) given:

            {@invalid-hologram-names.join(', ')}

            Please try again.
            EOF
            say $msg.trim;
        }
    }

    # optionally return holograms if user input valid holograms
    @holograms if @holograms;
}

sub prompt-keymap() returns Keymap:D
{
    my Keymap:D $default-item = 'us';
    my Str:D $prompt-text = 'Select keymap:';
    my Str:D $title = 'KEYMAP SELECTION';
    my Str:D $confirm-topic = 'keymap selected';

    my Keymap:D $keymap = dprompt(
        Keymap,
        %Holovault::Types::keymaps,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-locale() returns Locale:D
{
    my Locale:D $default-item = 'en_US';
    my Str:D $prompt-text = 'Select locale:';
    my Str:D $title = 'LOCALE SELECTION';
    my Str:D $confirm-topic = 'locale selected';

    my Locale:D $locale = dprompt(
        Locale,
        %Holovault::Types::locales,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

multi sub prompt-name(Bool:D :$host! where *.so) returns HostName:D
{
    # default response
    my HostName:D $response-default = "vault";

    # prompt text
    my Str:D $prompt-text = "Enter hostname [vault]: ";

    # help text
    my Str:D $help-text = q:to/EOF/;
    Determining hostname...

    Leave blank if you don't know what this is
    EOF
    $help-text .= trim;

    # prompt user
    my HostName:D $host-name = tprompt(
        HostName,
        $response-default,
        :$prompt-text,
        :$help-text
    );
}

multi sub prompt-name(Bool:D :$user! where *.so) returns UserName:D
{
    # default response
    my UserName:D $response-default = "live";

    # prompt text
    my Str:D $prompt-text = "Enter username [live]: ";

    # help text
    my Str:D $help-text = q:to/EOF/;
    Determining username...

    Leave blank if you don't know what this is
    EOF
    $help-text .= trim;

    # prompt user
    my UserName:D $user-name = tprompt(
        UserName,
        $response-default,
        :$prompt-text,
        :$help-text
    );
}

multi sub prompt-name(Bool:D :$vault! where *.so) returns VaultName:D
{
    # default response
    my VaultName:D $response-default = "vault";

    # prompt text
    my Str:D $prompt-text = "Enter vault name [vault]: ";

    # help text
    my Str:D $help-text = q:to/EOF/;
    Determining name of LUKS encrypted volume...

    Leave blank if you don't know what this is
    EOF
    $help-text .= trim;

    # prompt user
    my VaultName:D $vault-name = tprompt(
        VaultName,
        $response-default,
        :$prompt-text,
        :$help-text
    );
}

method !prompt-partition() returns Str:D
{
    # get list of partitions
    my Str:D @partitions =
        self.ls-partitions».subst(/(.*)/, -> $/ { "/dev/$0" });

    my Str:D $default-item = '/dev/sdb';
    my Str:D $prompt-text = 'Select partition for installing Arch:';
    my Str:D $title = 'PARTITION SELECTION';
    my Str:D $confirm-topic = 'partition selected';

    my Str:D $partition = dprompt(
        Str,
        @partitions,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

# generate sha512 password digest from user input
sub prompt-pass-digest(Bool :$root) returns Str:D
{
    # sha512 digest of empty password, for verifying passwords aren't blank
    my Str:D $blank-pass-digest = '$1$sha512$LGta5G7pRej6dUrilUI3O.';

    # for "Enter Root / User Password" input prompts
    my Str:D $subject = $root ?? 'Root' !! 'User';

    # store sha512 digest of password
    my Str $pass-digest;

    # loop until a non-blank password is entered twice in a row
    loop
    {
        # reading secure password digest into memory...
        print "Enter $subject "; # Enter Root / User Password
        $pass-digest = qx{openssl passwd -1 -salt sha512}.trim;

        # verifying secure password digest is not empty...
        if $pass-digest eqv $blank-pass-digest
        {
            # password is empty, try again
            say "$subject password cannot be blank. Please try again";
            next;
        }

        # verifying secure password digest...
        print "Retype $subject "; # Retype Root / User Password
        my Str:D $pass-digest-confirm = qx{openssl passwd -1 -salt sha512}.trim;
        if $pass-digest eqv $pass-digest-confirm
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

    $pass-digest;
}

sub prompt-processor() returns Processor:D
{
    my Processor:D $default-item = 'OTHER';
    my Str:D $prompt-text = 'Select processor:';
    my Str:D $title = 'PROCESSOR SELECTION';
    my Str:D $confirm-topic = 'processor selected';

    my Processor:D $processor = dprompt(
        Processor,
        %Holovault::Types::processors,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-timezone() returns Timezone:D
{
    # get list of timezones
    my Timezone:D @timezones = @Holovault::Types::timezones;

    # get list of timezone regions
    my Str:D @regions = @timezones».subst(/'/'\N*$/, '').unique;

    # prompt choose region
    my Str $region;
    {
        my Str:D $default-item = 'America';
        my Str:D $prompt-text = 'Select region:';
        my Str:D $title = 'TIMEZONE REGION SELECTION';
        my Str:D $confirm-topic = 'timezone region selected';

        $region = dprompt(
            Str,
            @regions,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }

    # get list of timezone region subregions
    my Str:D @subregions =
        @timezones.grep(/$region/)».subst(/^$region'/'/, '').sort;

    # prompt choose subregion
    my Str $subregion;
    {
        my Str:D $default-item = 'Los_Angeles';
        my Str:D $prompt-text = 'Select subregion:';
        my Str:D $title = 'TIMEZONE SUBREGION SELECTION';
        my Str:D $confirm-topic = 'timezone subregion selected';

        $subregion = dprompt(
            Str,
            @subregions,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }

    my Timezone:D $timezone = @timezones.grep("$region/$subregion")[0];
}


# -----------------------------------------------------------------------------
# utilities
# -----------------------------------------------------------------------------

# list holograms
method ls-holograms(Str :$holograms-dir)
{
    my Str $dir;
    if $holograms-dir
    {
        # if holograms-dir option passed, make sure it's readable
        # if so, use it
        $dir = self.gen-holograms-dir-handle($holograms-dir).Str;
    }
    else
    {
        # if HOLOGRAMS_DIR env is set, make sure it's readable
        # otherwise use resolve holograms dir with default methodology
        $dir = %*ENV<HOLOGRAMS_DIR>
            ?? self.gen-holograms-dir-handle(%*ENV<HOLOGRAMS_DIR>).Str
            !! self!resolve-holograms-dir.Str;
    }

    # if clause because holograms dir may not resolve to anything
    my Str:D @holograms-found;
    @holograms-found = qqx{
        find $dir -mindepth 1 -maxdepth 1 -type d | sed 's!^./!!'
    }.trim.split("\n").sort if $dir;

    # return holograms only if found readable dir not empty
    @holograms-found if @holograms-found[0];
}

# list keymaps
method ls-keymaps() returns Array[Keymap:D]
{
    # equivalent to `localectl list-keymaps --no-pager`
    # see: src/basic/def.h in systemd source code
    my Keymap:D @keymaps = qx{
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
method ls-locales() returns Array[Locale:D]
{
    my Locale:D @locales = qx{
        find /usr/share/i18n/locales -type f -printf '%f\n'
    }.trim.split("\n").sort;
}

# list block devices (partitions)
method ls-partitions() returns Array[Str:D]
{
    my Str:D @partitions = qx{
        lsblk --output NAME --nodeps --noheadings --raw
    }.trim.split("\n").sort;
}

# list timezones
method ls-timezones() returns Array[Timezone:D]
{
    # equivalent to `timedatectl list-timezones --no-pager`
    # see: src/basic/time-util.c in systemd source code
    my Timezone:D @timezones = qx«
        sed -n '/^#/!p' /usr/share/zoneinfo/zone.tab | awk '{print $3}'
    ».trim.split("\n").sort;
    push @timezones, "UTC";
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
