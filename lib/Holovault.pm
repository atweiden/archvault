use v6;
use Holovault::Bootstrap;
use Holovault::Config;
unit class Holovault;

constant $VERSION = v0.0.1;
our $CONF;

# setup with type checking
sub mkconf(
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
    my %cfg;

    # if --augment, initialize $CONF.augment to True
    %cfg<augment> = $augment if $augment;

    # if --disktype, initialize $CONF.disk-type to DiskType
    %cfg<disk-type> = Holovault::Config.gen-disk-type($disktype)
        if $disktype;

    # if --graphics, initialize $CONF.graphics to Graphics
    %cfg<graphics> = Holovault::Config.gen-graphics($graphics) if $graphics;

    # if --holograms, initialize $CONF.holograms to space split array
    %cfg<holograms> = Holovault::Config.gen-holograms($holograms)
        if $holograms;

    # if --holograms-dir, ensure dir is readable and initialze
    # $CONF.holograms-dir to IO::Handle
    %cfg<holograms-dir> =
        Holovault::Config.gen-holograms-dir-handle($holograms-dir)
            if $holograms-dir;

    # if --hostname, initialize $CONF.hostname to HostName
    %cfg<host-name> = Holovault::Config.gen-host-name($hostname)
        if $hostname;

    # if --keymap, initialize $CONF.keymap to Keymap
    %cfg<keymap> = Holovault::Config.gen-keymap($keymap) if $keymap;

    # if --locale, initialize $CONF.locale to Locale
    %cfg<locale> = Holovault::Config.gen-locale($locale) if $locale;

    # if --vaultname, initialize $CONF.vault-name to VaultName
    %cfg<vault-name> = Holovault::Config.gen-vault-name($vaultname)
        if $vaultname;

    # if --vaultpass, initialize $CONF.vault-pass to VaultPass
    %cfg<vault-pass> = Holovault::Config.gen-vault-pass($vaultpass)
        if $vaultpass;

    # if --partition, initialize $CONF.partition to Partition
    %cfg<partition> = $partition if $partition;

    # if --processor, initialize $CONF.processor to Processor
    %cfg<processor> = Holovault::Config.gen-processor($processor)
        if $processor;

    # if --rootpass, initialize $CONF.root-pass-digest to sha512 digest
    %cfg<root-pass-digest> = Holovault::Config.gen-digest($rootpass)
        if $rootpass;

    # if --timezone, initialize $CONF.timezone to Timezone
    %cfg<timezone> = Holovault::Config.gen-timezone($timezone) if $timezone;

    # if --username, initialize $CONF.user-name to UserName
    %cfg<user-name> = Holovault::Config.gen-user-name($username)
        if $username;

    # if --userpass, initialize $CONF.user-pass-digest to sha512 digest
    %cfg<user-pass-digest> = Holovault::Config.gen-digest($userpass)
        if $userpass;

    # instantiate global config, prompting for user input as needed
    $CONF = Holovault::Config.new(|%cfg);
}

method install(
    *%opts (
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
)
{
    mkconf(|%opts);
    bootstrap();
}

# vim: ft=perl6 fdm=marker fdl=0
