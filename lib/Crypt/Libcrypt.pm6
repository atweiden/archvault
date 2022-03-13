use v6;
use NativeCall;
unit module Crypt::Libcrypt:auth<atweiden>;

# Credit: https://github.com/jonathanstowe/Crypt-Libcrypt
sub crypt(Str, Str --> Str) is native('crypt', v2) is export {*}

# vim: set filetype=raku foldmethod=marker foldlevel=0:
