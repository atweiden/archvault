use v6;
unit grammar Holovault::Grammar;

# hostname (machine name)
regex host_name
{
    # translated from: http://stackoverflow.com/a/106223
    ^
    [
        [
            [<:Letter> || <digit>]
            ||
            [<:Letter> || <digit>]
            [<:Letter> || <digit> || '-']*
            [<:Letter> || <digit>]
        ]
        '.'
    ]*

    [
        [<:Letter> || <digit>]
        ||
        [<:Letter> || <digit>]
        [<:Letter> || <digit> || '-']*
        [<:Letter> || <digit>]
    ]
    $
}

# LUKS encrypted volume device mapper name validation
token vault_name
{
    <alpha> ** 1
    [ <alnum> || '-' ] ** 0..15
}

# linux username validation
regex user_name
{
    # from `man 8 useradd` line 255:
    # - username must be between 1 and 32 characters long
    # - username cannot be 'root' (handled in Types.pm subset definition)
    # - username must start with a lower case letter or an underscore,
    #   followed by lower case letters, digits, underscores, or
    #   dashes.
    # - username may end with a dollar sign

    <alpha> ** 1
    [ <alnum> || '-' ] ** 0..30
    [ <alnum> || '-' || '$' ]?
}

# vim: ft=perl6
