use v6;
use Archvault::Bootstrap;
use Archvault::Config;
unit class Archvault;

constant $VERSION = v0.0.1;
our $CONF;

# setup with type checking
sub mkconf(
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
)
{
    my %cfg;

    # if --augment, initialize $CONF.augment to True
    %cfg<augment> = $augment if $augment;

    # if --disktype, initialize $CONF.disk-type to DiskType
    %cfg<disk-type> = Archvault::Config.gen-disk-type($disktype)
        if $disktype;

    # if --graphics, initialize $CONF.graphics to Graphics
    %cfg<graphics> = Archvault::Config.gen-graphics($graphics) if $graphics;

    # if --hostname, initialize $CONF.hostname to HostName
    %cfg<host-name> = Archvault::Config.gen-host-name($hostname)
        if $hostname;

    # if --keymap, initialize $CONF.keymap to Keymap
    %cfg<keymap> = Archvault::Config.gen-keymap($keymap) if $keymap;

    # if --locale, initialize $CONF.locale to Locale
    %cfg<locale> = Archvault::Config.gen-locale($locale) if $locale;

    # if --vaultname, initialize $CONF.vault-name to VaultName
    %cfg<vault-name> = Archvault::Config.gen-vault-name($vaultname)
        if $vaultname;

    # if --vaultpass, initialize $CONF.vault-pass to VaultPass
    %cfg<vault-pass> = Archvault::Config.gen-vault-pass($vaultpass)
        if $vaultpass;

    # if --partition, initialize $CONF.partition to Partition
    %cfg<partition> = $partition if $partition;

    # if --processor, initialize $CONF.processor to Processor
    %cfg<processor> = Archvault::Config.gen-processor($processor)
        if $processor;

    # if --rootpass, initialize $CONF.root-pass-digest to sha512 digest
    %cfg<root-pass-digest> = Archvault::Config.gen-digest($rootpass)
        if $rootpass;

    # if --timezone, initialize $CONF.timezone to Timezone
    %cfg<timezone> = Archvault::Config.gen-timezone($timezone) if $timezone;

    # if --username, initialize $CONF.user-name to UserName
    %cfg<user-name> = Archvault::Config.gen-user-name($username)
        if $username;

    # if --userpass, initialize $CONF.user-pass-digest to sha512 digest
    %cfg<user-pass-digest> = Archvault::Config.gen-digest($userpass)
        if $userpass;

    # instantiate global config, prompting for user input as needed
    $CONF = Archvault::Config.new(|%cfg);
}

method install(
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
)
{
    # verify root permissions
    $*USER == 0 or die 'root privileges required';

    mkconf(|%opts);
    bootstrap();
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
