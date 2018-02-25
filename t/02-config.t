use v6;
use Test;

plan 1;

# ensure sha512 digest of empty password is correct
subtest
{
    my Str:D $blank-pass-digest = '$1$sha512$LGta5G7pRej6dUrilUI3O.';
    my Str:D $pass-digest = qx<openssl passwd -1 -salt sha512 ''>.trim;
    is(
        $pass-digest,
        $blank-pass-digest,
        q:to/EOF/
        ♪ [blank pass digest verification] - 1 of 1
        ┏━━━━━━━━━━━━━┓
        ┃             ┃  ∙ sha512 digest of empty password is accurate
        ┃   Success   ┃
        ┃             ┃
        ┗━━━━━━━━━━━━━┛
        EOF
    );
}

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
