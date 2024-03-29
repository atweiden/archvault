use v6;
use Archvault::Bootstrap;
use Archvault::Config;
use Archvault::Utils;
unit class Archvault;

constant $VERSION = v1.13.0;

method new(
    *%opts (
        Str :admin-name($),
        Str :admin-pass($),
        Str :admin-pass-hash($),
        Bool :augment($),
        Bool :disable-ipv6($),
        Str :disk-type($),
        Bool :enable-serial-console($),
        Str :graphics($),
        Str :grub-name($),
        Str :grub-pass($),
        Str :grub-pass-hash($),
        Str :guest-name($),
        Str :guest-pass($),
        Str :guest-pass-hash($),
        Str :hostname($),
        Str :keymap($),
        Str :locale($),
        Str :packages($),
        Str :partition($),
        Str :processor($),
        Bool :reflector($),
        Str :root-pass($),
        Str :root-pass-hash($),
        Str :sftp-name($),
        Str :sftp-pass($),
        Str :sftp-pass-hash($),
        Str :timezone($),
        Str :vault-name($),
        Str :vault-pass($)
    )
    --> Nil
)
{
    '/usr/bin/dialog'.IO.x.so
        or Archvault::Utils.pacman-install('dialog');

    # instantiate archvault config, prompting for user input as needed
    my Archvault::Config $config .= new(|%opts);

    # bootstrap archvault
    Archvault::Bootstrap.new(:$config).bootstrap;
}

# vim: set filetype=raku foldmethod=marker foldlevel=0:
