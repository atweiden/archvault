use v6;
use Archvault::Types;
unit class Archvault::Config;

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
has VaultPass $.vault-pass =
    %*ENV<VAULT_PASS> ?? self.gen-vault-pass(%*ENV<VAULT_PASS>)
                      !! Nil;

# name for host (default: vault)
has HostName:D $.host-name =
    %*ENV<HOST_NAME> ?? self.gen-host-name(%*ENV<HOST_NAME>)
                     !! prompt-name(:host);

# device path of target partition (default: /dev/sdb)
has Str:D $.partition = %*ENV<PARTITION> || self!prompt-partition();

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

# augment
has Bool:D $.augment = ?%*ENV<AUGMENT>;


# -----------------------------------------------------------------------------
# class instantation
# -----------------------------------------------------------------------------

submethod BUILD(
    Bool :$augment,
    Str :$disktype,
    Str :$graphics,
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
    Str :$vaultpass
    --> Nil
)
{
    # if --augment, initialize $.augment to True
    $!augment = $augment if $augment;

    # if --disktype, initialize $.disk-type to DiskType
    $!disk-type = self.gen-disk-type($disktype) if $disktype;

    # if --graphics, initialize $.graphics to Graphics
    $!graphics = self.gen-graphics($graphics) if $graphics;

    # if --hostname, initialize $.hostname to HostName
    $!host-name = self.gen-host-name($hostname) if $hostname;

    # if --keymap, initialize $.keymap to Keymap
    $!keymap = self.gen-keymap($keymap) if $keymap;

    # if --locale, initialize $.locale to Locale
    $!locale = self.gen-locale($locale) if $locale;

    # if --vaultname, initialize $.vault-name to VaultName
    $!vault-name = self.gen-vault-name($vaultname) if $vaultname;

    # if --vaultpass, initialize $.vault-pass to VaultPass
    $!vault-pass = self.gen-vault-pass($vaultpass) if $vaultpass;

    # if --partition, initialize $.partition to Partition
    $!partition = $partition if $partition;

    # if --processor, initialize $.processor to Processor
    $!processor = self.gen-processor($processor) if $processor;

    # if --rootpass, initialize $.root-pass-digest to sha512 digest
    $!root-pass-digest = self.gen-digest($rootpass) if $rootpass;

    # if --timezone, initialize $.timezone to Timezone
    $!timezone = self.gen-timezone($timezone) if $timezone;

    # if --username, initialize $.user-name to UserName
    $!user-name = self.gen-user-name($username) if $username;

    # if --userpass, initialize $.user-pass-digest to sha512 digest
    $!user-pass-digest = self.gen-digest($userpass) if $userpass;
}

method new(
    *%opts (
        Bool :augment($),
        Str :disktype($),
        Str :graphics($),
        Str :hostname($),
        Str :keymap($),
        Str :locale($),
        Str :partition($),
        Str :processor($),
        Str :rootpass($),
        Str :timezone($),
        Str :username($),
        Str :userpass($),
        Str :vaultname($),
        Str :vaultpass($)
    )
    --> Archvault::Config:D
)
{
    self.bless(|%opts);
}


# -----------------------------------------------------------------------------
# string formatting, resolution and validation
# -----------------------------------------------------------------------------

# return sha512 salt of password for linux user
method gen-digest(Str:D $password --> Str:D)
{
    my Str:D $digest = qqx{openssl passwd -1 -salt sha512 $password}.trim;
}

# confirm disk type $d is valid DiskType and return DiskType
method gen-disk-type(Str:D $d --> DiskType:D)
{
    my DiskType:D $disk-type = $d or die 'Sorry, invalid disk type';
}

# confirm graphics card type $g is valid Graphics and return Graphics
method gen-graphics(Str:D $g --> Graphics:D)
{
    my Graphics:D $graphics = $g or die 'Sorry, invalid graphics card type';
}

# confirm hostname $h is valid HostName and return HostName
method gen-host-name(Str:D $h --> HostName:D)
{
    my HostName:D $host-name = $h or die "Sorry, invalid hostname 「$h」";
}

# confirm keymap $k is valid Keymap and return Keymap
method gen-keymap(Str:D $k --> Keymap:D)
{
    my Keymap:D $keymap = $k or die "Sorry, invalid keymap 「$k」";
}

# confirm locale $l is valid Locale and return Locale
method gen-locale(Str:D $l --> Locale:D)
{
    my Locale:D $locale = $l or die "Sorry, invalid locale 「$l」";
}

# confirm processor $p is valid Processor and return Processor
method gen-processor(Str:D $p --> Processor:D)
{
    my Processor:D $processor = $p or die "Sorry, invalid processor 「$p」";
}

# confirm timezone $t is valid Timezone and return Timezone
method gen-timezone(Str:D $t --> Timezone:D)
{
    my Timezone:D $timezone = $t or die "Sorry, invalid timezone 「$t」";
}

# confirm user name $u is valid UserName and return UserName
method gen-user-name(Str:D $u --> UserName:D)
{
    my UserName:D $user-name = $u or die "Sorry, invalid username 「$u」";
}

# confirm vault name $v is valid VaultName and return VaultName
method gen-vault-name(Str:D $v --> VaultName:D)
{
    my VaultName:D $vault-name = $v or die "Sorry, invalid vault name 「$v」";
}

# confirm vault pass $v is valid VaultPass and return VaultPass
method gen-vault-pass(Str:D $v --> VaultPass:D)
{
    my VaultPass:D $vault-pass = $v
        or die 'Sorry, invalid vault pass. Length needed: 1-512. '
             ~ 'Length given: ' ~ $v.chars;
}


# -----------------------------------------------------------------------------
# user input prompts
# -----------------------------------------------------------------------------

# dialog menu user input prompt with tags (keys) only
multi sub dprompt(
    # type of response expected
    ::T,
    # menu (T $tag)
    @menu,
    # default response
    T :$default-item! where *.defined,
    # menu title
    Str:D :$title!,
    # question posed to user
    Str:D :$prompt-text!,
    UInt:D :$height = 80,
    UInt:D :$width = 80,
    UInt:D :$menu-height = 24,
    # context string for confirm text
    Str:D :$confirm-topic!
    --> Any:D
)
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
    # type of response expected
    ::T,
    # menu (T $tag => Str $item)
    %menu,
    # default response
    T :$default-item! where *.defined,
    # menu title
    Str:D :$title!,
    # question posed to user
    Str:D :$prompt-text!,
    UInt:D :$height = 80,
    UInt:D :$width = 80,
    UInt:D :$menu-height = 24,
    # context string for confirm text
    Str:D :$confirm-topic!
    --> Any:D
)
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
    # type of response expected
    ::T,
    # default response
    T $response-default where *.defined,
    # question posed to user
    Str:D :$prompt-text!,
    # optional help text to display before prompt
    Str :$help-text
    --> Any:D
)
{
    my $response;

    loop
    {
        # display help text (optional)
        say($help-text) if $help-text;

        # prompt for response
        $response = prompt($prompt-text);

        # if empty carriage return entered, use default response value
        unless $response
        {
            $response = $response-default;
        }

        # retry if response is invalid
        unless $response ~~ T
        {
            say('Sorry, invalid response. Please try again.');
            next;
        }

        # prompt for confirmation
        my Str:D $confirmation =
            prompt("Confirm «{$response.split(/\s+/).join(', ')}» [y/N]: ");

        # check for affirmative confirmation
        last if is-confirmed($confirmation);
    }

    $response;
}

# was response affirmative?
multi sub is-confirmed(Str:D $confirmation where /:i y[e[s]?]?/ --> Bool:D)
{
    my Bool:D $is-confirmed = True;
}

# was response negatory?
multi sub is-confirmed(Str:D $confirmation where /:i n[o]?/ --> Bool:D)
{
    my Bool:D $is-confirmed = False;
}

# was response empty?
multi sub is-confirmed(Str:D $confirmation where *.chars == 0 --> Bool:D)
{
    my Bool:D $is-confirmed = False;
}

# were unrecognized characters entered?
multi sub is-confirmed($confirmation --> Bool:D)
{
    my Bool:D $is-confirmed = False;
}

sub prompt-disk-type(--> DiskType:D)
{
    my DiskType:D $default-item = 'USB';
    my Str:D $prompt-text = 'Select disk type:';
    my Str:D $title = 'DISK TYPE SELECTION';
    my Str:D $confirm-topic = 'disk type selected';

    my DiskType:D $disk-type = dprompt(
        DiskType,
        %Archvault::Types::disktypes,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-graphics(--> Graphics:D)
{
    my Graphics:D $default-item = 'INTEL';
    my Str:D $prompt-text = 'Select graphics card type:';
    my Str:D $title = 'GRAPHICS CARD TYPE SELECTION';
    my Str:D $confirm-topic = 'graphics card type selected';

    my Graphics:D $graphics = dprompt(
        Graphics,
        %Archvault::Types::graphics,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-keymap(--> Keymap:D)
{
    my Keymap:D $default-item = 'us';
    my Str:D $prompt-text = 'Select keymap:';
    my Str:D $title = 'KEYMAP SELECTION';
    my Str:D $confirm-topic = 'keymap selected';

    my Keymap:D $keymap = dprompt(
        Keymap,
        %Archvault::Types::keymaps,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-locale(--> Locale:D)
{
    my Locale:D $default-item = 'en_US';
    my Str:D $prompt-text = 'Select locale:';
    my Str:D $title = 'LOCALE SELECTION';
    my Str:D $confirm-topic = 'locale selected';

    my Locale:D $locale = dprompt(
        Locale,
        %Archvault::Types::locales,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

multi sub prompt-name(Bool:D :$host! where *.so --> HostName:D)
{
    # default response
    my HostName:D $response-default = 'vault';

    # prompt text
    my Str:D $prompt-text = 'Enter hostname [vault]: ';

    # help text
    my Str:D $help-text = q:to/EOF/.trim;
    Determining hostname...

    Leave blank if you don't know what this is
    EOF

    # prompt user
    my HostName:D $host-name = tprompt(
        HostName,
        $response-default,
        :$prompt-text,
        :$help-text
    );
}

multi sub prompt-name(Bool:D :$user! where *.so --> UserName:D)
{
    # default response
    my UserName:D $response-default = 'live';

    # prompt text
    my Str:D $prompt-text = 'Enter username [live]: ';

    # help text
    my Str:D $help-text = q:to/EOF/.trim;
    Determining username...

    Leave blank if you don't know what this is
    EOF

    # prompt user
    my UserName:D $user-name = tprompt(
        UserName,
        $response-default,
        :$prompt-text,
        :$help-text
    );
}

multi sub prompt-name(Bool:D :$vault! where *.so --> VaultName:D)
{
    # default response
    my VaultName:D $response-default = 'vault';

    # prompt text
    my Str:D $prompt-text = 'Enter vault name [vault]: ';

    # help text
    my Str:D $help-text = q:to/EOF/.trim;
    Determining name of LUKS encrypted volume...

    Leave blank if you don't know what this is
    EOF

    # prompt user
    my VaultName:D $vault-name = tprompt(
        VaultName,
        $response-default,
        :$prompt-text,
        :$help-text
    );
}

method !prompt-partition(--> Str:D)
{
    # get list of partitions
    my Str:D @partitions =
        self.ls-partitions()».subst(/(.*)/, -> $/ { "/dev/$0" });

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
sub prompt-pass-digest(Bool :$root --> Str:D)
{
    # sha512 digest of empty password, for verifying passwords aren't blank
    my Str:D $blank-pass-digest = '$1$sha512$LGta5G7pRej6dUrilUI3O.';

    # for 'Enter Root / User Password' input prompts
    my Str:D $subject = $root ?? 'Root' !! 'User';

    # store sha512 digest of password
    my Str $pass-digest;

    # loop until a non-blank password is entered twice in a row
    loop
    {
        # reading secure password digest into memory...
        # "Enter Root / User Password"
        print("Enter $subject ");
        $pass-digest = qx{openssl passwd -1 -salt sha512}.trim;

        # verifying secure password digest is not empty...
        if $pass-digest eqv $blank-pass-digest
        {
            # password is empty, try again
            say("$subject password cannot be blank. Please try again");
            next;
        }

        # verifying secure password digest...
        # "Retype Root / User Password"
        print("Retype $subject ");
        my Str:D $pass-digest-confirm = qx{openssl passwd -1 -salt sha512}.trim;

        last if $pass-digest eqv $pass-digest-confirm;

        # password not verified, try again
        say('Please try again');
    }

    $pass-digest;
}

sub prompt-processor(--> Processor:D)
{
    my Processor:D $default-item = 'OTHER';
    my Str:D $prompt-text = 'Select processor:';
    my Str:D $title = 'PROCESSOR SELECTION';
    my Str:D $confirm-topic = 'processor selected';

    my Processor:D $processor = dprompt(
        Processor,
        %Archvault::Types::processors,
        :$default-item,
        :$prompt-text,
        :$title,
        :$confirm-topic
    );
}

sub prompt-timezone(--> Timezone:D)
{
    # get list of timezones
    my Timezone:D @timezones = @Archvault::Types::timezones;

    # get list of timezone regions
    my Str:D @regions = @timezones».subst(/'/'\N*$/, '').unique;

    # prompt choose region
    my Str:D $region = do
    {
        my Str:D $default-item = 'America';
        my Str:D $prompt-text = 'Select region:';
        my Str:D $title = 'TIMEZONE REGION SELECTION';
        my Str:D $confirm-topic = 'timezone region selected';
        dprompt(
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
    my Str:D $subregion = do
    {
        my Str:D $default-item = 'Los_Angeles';
        my Str:D $prompt-text = 'Select subregion:';
        my Str:D $title = 'TIMEZONE SUBREGION SELECTION';
        my Str:D $confirm-topic = 'timezone subregion selected';
        dprompt(
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

# list keymaps
method ls-keymaps(--> Array[Keymap:D])
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
method ls-locales(--> Array[Locale:D])
{
    my Locale:D @locales = qx{
        find /usr/share/i18n/locales -type f -printf '%f\n'
    }.trim.split("\n").sort;
}

# list block devices (partitions)
method ls-partitions(--> Array[Str:D])
{
    my Str:D @partitions = qx{
        lsblk --output NAME --nodeps --noheadings --raw
    }.trim.split("\n").sort;
}

# list timezones
method ls-timezones(--> Array[Timezone:D])
{
    # equivalent to `timedatectl list-timezones --no-pager`
    # see: src/basic/time-util.c in systemd source code
    my Timezone:D @timezones =
        |qx<
            sed -n '/^#/!p' /usr/share/zoneinfo/zone.tab | awk '{print $3}'
        >.trim.split("\n").sort,
        'UTC';
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
