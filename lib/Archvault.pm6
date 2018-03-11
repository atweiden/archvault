use v6;
use Archvault::Bootstrap;
use Archvault::Config;
unit class Archvault;

constant $VERSION = v0.0.1;

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
        Str :sshusername($),
        Str :timezone($),
        Str :username($),
        Str :vaultname($),
        Str :vaultpass($)
    )
    --> Nil
)
{
    # instantiate archvault config, prompting for user input as needed
    my Archvault::Config $config .= new(|%opts);

    # bootstrap archvault
    Archvault::Bootstrap.new(:$config).bootstrap;
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
