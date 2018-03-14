use v6;
use Archvault::Types;
use Crypt::Libcrypt:auth<atweiden>;
unit class Archvault::Config;

# -----------------------------------------------------------------------------
# settings
# -----------------------------------------------------------------------------

# - attributes appear in specific order for prompting user
# - defaults are geared towards live media installation

# name for trusted admin user (default: live)
has UserName:D $.user-name-admin =
    %*ENV<ARCHVAULT_USERNAME>
        ?? self.gen-user-name(%*ENV<ARCHVAULT_USERNAME>)
        !! prompt-name(:user, :trusted);

# sha512 password hash for trusted admin user
has Str:D $.user-pass-hash-admin =
    %*ENV<ARCHVAULT_USERPASS>
        ?? self.gen-pass-hash(%*ENV<ARCHVAULT_USERPASS>)
        !! self.prompt-pass-hash($!user-name-admin);

# name for untrusted ssh user (default: variable)
has UserName:D $.user-name-ssh =
    %*ENV<ARCHVAULT_SSHUSERNAME>
        ?? self.gen-user-name(%*ENV<ARCHVAULT_SSHUSERNAME>)
        !! prompt-name(:user, :untrusted);

# sha512 password hash for untrusted ssh user
has Str:D $.user-pass-hash-ssh =
    %*ENV<ARCHVAULT_USERPASS>
        ?? self.gen-pass-hash(%*ENV<ARCHVAULT_USERPASS>)
        !! self.prompt-pass-hash($!user-name-ssh);

# sha512 password hash for root user
has Str:D $.user-pass-hash-root =
    %*ENV<ARCHVAULT_ROOTPASS>
        ?? self.gen-pass-hash(%*ENV<ARCHVAULT_ROOTPASS>)
        !! self.prompt-pass-hash('root');

# name for LUKS encrypted volume (default: vault)
has VaultName:D $.vault-name =
    %*ENV<ARCHVAULT_VAULTNAME>
        ?? self.gen-vault-name(%*ENV<ARCHVAULT_VAULTNAME>)
        !! prompt-name(:vault);

# password for LUKS encrypted volume
has VaultPass $.vault-pass =
    %*ENV<ARCHVAULT_VAULTPASS>
        ?? self.gen-vault-pass(%*ENV<ARCHVAULT_VAULTPASS>)
        !! Nil;

# name for host (default: vault)
has HostName:D $.host-name =
    %*ENV<ARCHVAULT_HOSTNAME>
        ?? self.gen-host-name(%*ENV<ARCHVAULT_HOSTNAME>)
        !! prompt-name(:host);

# device path of target partition (default: /dev/sdb)
has Str:D $.partition =
    %*ENV<ARCHVAULT_PARTITION>
        || prompt-partition(self.ls-partitions);

# type of processor (default: other)
has Processor:D $.processor =
    %*ENV<ARCHVAULT_PROCESSOR>
        ?? self.gen-processor(%*ENV<ARCHVAULT_PROCESSOR>)
        !! prompt-processor();

# type of graphics card (default: intel)
has Graphics:D $.graphics =
    %*ENV<ARCHVAULT_GRAPHICS>
        ?? self.gen-graphics(%*ENV<ARCHVAULT_GRAPHICS>)
        !! prompt-graphics();

# type of hard drive (default: usb)
has DiskType:D $.disk-type =
    %*ENV<ARCHVAULT_DISKTYPE>
        ?? self.gen-disk-type(%*ENV<ARCHVAULT_DISKTYPE>)
        !! prompt-disk-type();

# locale (default: en_US)
has Locale:D $.locale =
    %*ENV<ARCHVAULT_LOCALE>
        ?? self.gen-locale(%*ENV<ARCHVAULT_LOCALE>)
        !! prompt-locale();

# keymap (default: us)
has Keymap:D $.keymap =
    %*ENV<ARCHVAULT_KEYMAP>
        ?? self.gen-keymap(%*ENV<ARCHVAULT_KEYMAP>)
        !! prompt-keymap();

# timezone (default: America/Los_Angeles)
has Timezone:D $.timezone =
    %*ENV<ARCHVAULT_TIMEZONE>
        ?? self.gen-timezone(%*ENV<ARCHVAULT_TIMEZONE>)
        !! prompt-timezone();

# augment
has Bool:D $.augment =
    ?%*ENV<ARCHVAULT_AUGMENT>;

# reflector
has Bool:D $.reflector =
    ?%*ENV<ARCHVAULT_REFLECTOR>;


# -----------------------------------------------------------------------------
# constants
# -----------------------------------------------------------------------------

# linux crypt encryption scheme for user password hash generation
constant $SCHEME = 'SHA512';

# linux crypt encryption rounds
constant $ROUNDS = 700_000;


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
    Bool :$reflector,
    Str :$rootpass,
    Str :$sshusername,
    Str :$sshuserpass,
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

    # if --partition, initialize $.partition to Partition
    $!partition = $partition if $partition;

    # if --processor, initialize $.processor to Processor
    $!processor = self.gen-processor($processor) if $processor;

    # if --reflector, initialize $.reflector to True
    $!reflector = $reflector if $reflector;

    # if --timezone, initialize $.timezone to Timezone
    $!timezone = self.gen-timezone($timezone) if $timezone;

    # if --username, initialize $.user-name-admin to UserName
    $!user-name-admin = self.gen-user-name($username) if $username;

    # if --userpass, initialize $.user-pass-hash-admin to sha512 salted hash
    $!user-pass-hash-admin = self.gen-pass-hash($userpass) if $userpass;

    # if --rootpass, initialize $.user-pass-hash-root to sha512 salted hash
    $!user-pass-hash-root = self.gen-pass-hash($rootpass) if $rootpass;

    # if --sshusername, initialize $.user-name-ssh to UserName
    $!user-name-ssh = self.gen-user-name($sshusername) if $sshusername;

    # if --sshuserpass, initialize $.user-pass-hash-ssh to sha512 salted hash
    $!user-pass-hash-ssh = self.gen-pass-hash($sshuserpass) if $sshuserpass;

    # if --vaultname, initialize $.vault-name to VaultName
    $!vault-name = self.gen-vault-name($vaultname) if $vaultname;

    # if --vaultpass, initialize $.vault-pass to VaultPass
    $!vault-pass = self.gen-vault-pass($vaultpass) if $vaultpass;
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
        Bool :reflector($),
        Str :rootpass($),
        Str :sshusername($),
        Str :sshuserpass($),
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

# confirm disk type $d is valid DiskType and return DiskType
method gen-disk-type(Str:D $d --> DiskType:D)
{
    my DiskType:D $disk-type = $d.uc or die('Sorry, invalid disk type');
}

# confirm graphics card type $g is valid Graphics and return Graphics
method gen-graphics(Str:D $g --> Graphics:D)
{
    my Graphics:D $graphics = $g.uc or die('Sorry, invalid graphics card type');
}

# confirm hostname $h is valid HostName and return HostName
method gen-host-name(Str:D $h --> HostName:D)
{
    my HostName:D $host-name = $h or die("Sorry, invalid hostname 「$h」");
}

# confirm keymap $k is valid Keymap and return Keymap
method gen-keymap(Str:D $k --> Keymap:D)
{
    my Keymap:D $keymap = $k or die("Sorry, invalid keymap 「$k」");
}

# confirm locale $l is valid Locale and return Locale
method gen-locale(Str:D $l --> Locale:D)
{
    my Locale:D $locale = $l or die("Sorry, invalid locale 「$l」");
}

# generate sha512 salted password hash from plaintext password
method gen-pass-hash(Str:D $user-pass --> Str:D)
{
    my Str:D $salt = gen-pass-salt();
    my Str:D $pass-hash = crypt($user-pass, $salt);
}

# confirm processor $p is valid Processor and return Processor
method gen-processor(Str:D $p --> Processor:D)
{
    my Processor:D $processor = $p.uc or die("Sorry, invalid processor 「$p」");
}

# confirm timezone $t is valid Timezone and return Timezone
method gen-timezone(Str:D $t --> Timezone:D)
{
    my Timezone:D $timezone = $t or die("Sorry, invalid timezone 「$t」");
}

# confirm user name $u is valid UserName and return UserName
method gen-user-name(Str:D $u --> UserName:D)
{
    my UserName:D $user-name = $u or die("Sorry, invalid username 「$u」");
}

# confirm vault name $v is valid VaultName and return VaultName
method gen-vault-name(Str:D $v --> VaultName:D)
{
    my VaultName:D $vault-name = $v or die("Sorry, invalid vault name 「$v」");
}

# confirm vault pass $v is valid VaultPass and return VaultPass
method gen-vault-pass(Str:D $v --> VaultPass:D)
{
    my VaultPass:D $vault-pass = $v
        or die('Sorry, invalid vault pass. Length needed: 1-512. '
                ~ 'Length given: ' ~ $v.chars);
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
        $response = qqx<
            dialog \\
                --stdout \\
                --no-items \\
                --scrollbar \\
                --no-cancel \\
                --default-item $default-item \\
                --title '$title' \\
                --menu '$prompt-text' $height $width $menu-height @menu[]
        >;

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
        $response = qqx<
            dialog \\
                --stdout \\
                --scrollbar \\
                --no-cancel \\
                --default-item $default-item \\
                --title '$title' \\
                --menu '$prompt-text' $height $width $menu-height {%menu.sort}
        >;

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

# user input prompt (secret text)
sub stprompt(Str:D $prompt-text --> Str:D)
{
    run(qw<stty -echo>);
    my Str:D $secret = prompt($prompt-text);
    run(qw<stty echo>);
    say('');
    $secret;
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
    my DiskType:D $disk-type = do {
        my DiskType:D $default-item = 'USB';
        my Str:D $prompt-text = 'Select disk type:';
        my Str:D $title = 'DISK TYPE SELECTION';
        my Str:D $confirm-topic = 'disk type selected';
        dprompt(
            DiskType,
            %Archvault::Types::disktypes,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }
}

sub prompt-graphics(--> Graphics:D)
{
    my Graphics:D $graphics = do {
        my Graphics:D $default-item = 'INTEL';
        my Str:D $prompt-text = 'Select graphics card type:';
        my Str:D $title = 'GRAPHICS CARD TYPE SELECTION';
        my Str:D $confirm-topic = 'graphics card type selected';
        dprompt(
            Graphics,
            %Archvault::Types::graphics,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }
}

sub prompt-keymap(--> Keymap:D)
{
    my Keymap:D $keymap = do {
        my Keymap:D $default-item = 'us';
        my Str:D $prompt-text = 'Select keymap:';
        my Str:D $title = 'KEYMAP SELECTION';
        my Str:D $confirm-topic = 'keymap selected';
        dprompt(
            Keymap,
            %Archvault::Types::keymaps,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }
}

sub prompt-locale(--> Locale:D)
{
    my Locale:D $locale = do {
        my Locale:D $default-item = 'en_US';
        my Str:D $prompt-text = 'Select locale:';
        my Str:D $title = 'LOCALE SELECTION';
        my Str:D $confirm-topic = 'locale selected';
        dprompt(
            Locale,
            %Archvault::Types::locales,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }
}

multi sub prompt-name(Bool:D :host($)! where *.so --> HostName:D)
{
    my HostName:D $host-name = do {
        my HostName:D $response-default = 'vault';
        my Str:D $prompt-text = "Enter hostname [$response-default]: ";
        my Str:D $help-text = q:to/EOF/.trim;
        Determining hostname...

        Leave blank if you don't know what this is
        EOF
        tprompt(
            HostName,
            $response-default,
            :$prompt-text,
            :$help-text
        );
    }
}

multi sub prompt-name(
    Bool:D :user($)! where *.so,
    Bool:D :trusted($)! where *.so
    --> UserName:D
)
{
    my UserName:D $user-name = do {
        my UserName:D $response-default = 'live';
        my Str:D $prompt-text = "Enter username [$response-default]: ";
        my Str:D $help-text = q:to/EOF/.trim;
        Determining name for trusted admin user...

        Leave blank if you don't know what this is
        EOF
        tprompt(
            UserName,
            $response-default,
            :$prompt-text,
            :$help-text
        );
    }
}

multi sub prompt-name(
    Bool:D :user($)! where *.so,
    Bool:D :untrusted($)! where *.so
    --> UserName:D
)
{
    my UserName:D $user-name = do {
        my UserName:D $response-default = 'variable';
        my Str:D $prompt-text = "Enter username [$response-default]: ";
        my Str:D $help-text = q:to/EOF/.trim;
        Determining name for untrusted SSH user...

        Leave blank if you don't know what this is
        EOF
        tprompt(
            UserName,
            $response-default,
            :$prompt-text,
            :$help-text
        );
    }
}

multi sub prompt-name(Bool:D :vault($)! where *.so --> VaultName:D)
{
    my VaultName:D $vault-name = do {
        my VaultName:D $response-default = 'vault';
        my Str:D $prompt-text = "Enter vault name [$response-default]: ";
        my Str:D $help-text = q:to/EOF/.trim;
        Determining name of LUKS encrypted volume...

        Leave blank if you don't know what this is
        EOF
        tprompt(
            VaultName,
            $response-default,
            :$prompt-text,
            :$help-text
        );
    }
}

sub prompt-partition(Str:D @ls-partitions --> Str:D)
{
    my Str:D $partition = do {
        my Str:D @partitions =
            @ls-partitions.hyper.map({ .subst(/(.*)/, -> $/ { "/dev/$0" }) });
        my Str:D $default-item = '/dev/sdb';
        my Str:D $prompt-text = 'Select partition for installing Arch:';
        my Str:D $title = 'PARTITION SELECTION';
        my Str:D $confirm-topic = 'partition selected';
        dprompt(
            Str,
            @partitions,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }
}

# generate sha512 salted password hash from interactive user input
method prompt-pass-hash(Str $user-name? --> Str:D)
{
    my Str:D $salt = gen-pass-salt();
    my Str:D $pass-hash-blank = crypt('', $salt);
    my Str $pass-hash;
    loop
    {
        say("Generating password hash for $user-name...") if $user-name;
        my Str:D $user-pass = stprompt('Enter new password: ');
        $pass-hash = crypt($user-pass, $salt);
        if $pass-hash eqv $pass-hash-blank
        {
            say('Password cannot be blank. Please try again');
            next;
        }
        my Str:D $user-pass-confirm = stprompt('Retype new password: ');
        my Str:D $pass-hash-confirm = crypt($user-pass-confirm, $salt);
        last if $pass-hash eqv $pass-hash-confirm;
        # passwords do not match
        say('Please try again');
    }
    $pass-hash;
}

sub prompt-processor(--> Processor:D)
{
    my Processor:D $processor = do {
        my Processor:D $default-item = 'OTHER';
        my Str:D $prompt-text = 'Select processor:';
        my Str:D $title = 'PROCESSOR SELECTION';
        my Str:D $confirm-topic = 'processor selected';
        dprompt(
            Processor,
            %Archvault::Types::processors,
            :$default-item,
            :$prompt-text,
            :$title,
            :$confirm-topic
        );
    }
}

sub prompt-timezone(--> Timezone:D)
{
    # get list of timezones
    my Timezone:D @timezones = @Archvault::Types::timezones;

    # prompt choose region
    my Str:D $region = do {
        # get list of timezone regions
        my Str:D @regions =
            @timezones.hyper.map({ .subst(/'/'\N*$/, '') }).unique;
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

    # prompt choose subregion
    my Str:D $subregion = do {
        # get list of timezone region subregions
        my Str:D @subregions =
            @timezones
            .grep(/$region/)
            .hyper
            .map({ .subst(/^$region'/'/, '') })
            .sort;
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

    my Timezone:D $timezone = @timezones.grep("$region/$subregion").first;
}


# -----------------------------------------------------------------------------
# utilities
# -----------------------------------------------------------------------------

# list keymaps
method ls-keymaps(--> Array[Keymap:D])
{
    # equivalent to `localectl list-keymaps --no-pager`
    # see: src/basic/def.h in systemd source code
    my Keymap:D @keymaps = qx<
        find /usr/share/kbd/keymaps -type f \
               \( ! -name "*compose*" \)    \
            -a \( ! -name "*.doc*"    \)    \
            -a \( ! -name "*.html*"   \)    \
            -a \( ! -name "*.inc*"    \)    \
            -a \( ! -name "*.latin1*" \)    \
            -a \( ! -name "*.m4*"     \)    \
            -printf '%f\n'
    >.trim.split("\n").hyper.map({ .subst(/'.map.gz'$/, '') }).sort;
}

# list locales
method ls-locales(--> Array[Locale:D])
{
    my Locale:D @locales = qx<
        find /usr/share/i18n/locales -type f -printf '%f\n'
    >.trim.split("\n").sort;
}

# list block devices (partitions)
method ls-partitions(--> Array[Str:D])
{
    my Str:D @partitions = qx<
        lsblk --output NAME --nodeps --noheadings --raw
    >.trim.split("\n").sort;
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


# -----------------------------------------------------------------------------
# helper functions
# -----------------------------------------------------------------------------

sub gen-pass-salt(--> Str:D)
{
    my Str:D $scheme = gen-scheme-id($SCHEME);
    my Str:D $rounds = ~$ROUNDS;
    my Str:D $rand =
        qx<openssl rand -base64 16>.trim.subst(/<[+=]>/, :g, '').substr(0, 16);
    my Str:D $salt = sprintf('$%s$rounds=%s$%s$', $scheme, $rounds, $rand);
}

# linux crypt encrypted method id accessed by encryption method
multi sub gen-scheme-id('MD5' --> Str:D)      { '1' }
multi sub gen-scheme-id('BLOWFISH' --> Str:D) { '2a' }
multi sub gen-scheme-id('SHA256' --> Str:D)   { '5' }
multi sub gen-scheme-id('SHA512' --> Str:D)   { '6' }

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
