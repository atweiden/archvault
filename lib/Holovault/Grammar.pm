use v6;
unit grammar Holovault::Grammar;

# match a single lowercase alphanumeric character, or an underscore
token alnum_lower
{
    <+alpha_lower +digit>
}

# match a single lowercase alphabetic character, or an underscore
token alpha_lower
{
    <+lower +[_]>
}

# hostname (machine name)
regex host_name
{
    # translated from: http://stackoverflow.com/a/106223
    ^
    [
        [
            <+:Letter +digit>
            ||
            <+:Letter +digit>
            <+:Letter +digit +[-]>*
            <+:Letter +digit>
        ]
        '.'
    ]*
    [
        <+:Letter +digit>
        ||
        <+:Letter +digit>
        <+:Letter +digit +[-]>*
        <+:Letter +digit>
    ]
    $
}

# archlinux pkgname validation
token pkg_name
{
    # see pacman source: scripts/libmakepkg/lint_pkgbuild/pkgname.sh.in
    # pkgnames are not allowed to start with a period or hyphen
    <+alnum +[+] +[@]>
    <+alnum +[+] +[@] +[.] +[-]>*
}

# linux username validation
regex user_name
{
    # from `man 8 useradd` line 255:
    # - username must be between 1 and 32 characters long
    # - username cannot be 'root' (handled in Types.pm subset definition)
    # - username must start with a lower case letter or an underscore,
    #   followed by lower case letters, digits, underscores, or
    #   dashes
    # - username may end with a dollar sign
    <alpha_lower> ** 1
    <+alnum_lower +[-]> ** 0..30
    <+alnum_lower +[-] +[$]>?
}

# LUKS encrypted volume device mapper name validation
token vault_name
{
    <alpha> ** 1
    <+alnum +[-]> ** 0..15
}

# vim: ft=perl6
