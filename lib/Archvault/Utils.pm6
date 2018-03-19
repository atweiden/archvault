use v6;
use Archvault::Types;
use Crypt::Libcrypt:auth<atweiden>;
unit class Archvault::Utils;

# -----------------------------------------------------------------------------
# constants
# -----------------------------------------------------------------------------

# libcrypt encryption scheme for user password hash generation
constant $SCHEME = 'SHA512';

# libcrypt encryption rounds
constant $ROUNDS = 700_000;


# -----------------------------------------------------------------------------
# copy-on-write
# -----------------------------------------------------------------------------

method disable-cow(
    UInt:D :$permissions = 0o755,
    Str:D :$user = $*USER,
    Str:D :$group = $*GROUP,
    *@directory
    --> Nil
)
{
    # https://wiki.archlinux.org/index.php/Btrfs#Disabling_CoW
    @directory.map({ disable-cow($_, $permissions, $user, $group) });
}

sub disable-cow(
    Str:D $directory,
    UInt:D $permissions,
    Str:D $user,
    Str:D $group
    --> Nil
)
{
    my Str:D $orig-dir = ~$directory.IO.resolve;
    $orig-dir.IO.e && $orig-dir.IO.r && $orig-dir.IO.d
        or die('directory failed exists readable directory test');
    my Str:D $backup-dir = $orig-dir ~ '-old';
    rename($orig-dir, $backup-dir);
    mkdir($orig-dir);
    chmod($permissions, $orig-dir);
    run(qqw<chattr +C $orig-dir>);
    dir($backup-dir).race.map(-> $file {
        run(qqw<cp -dpr --no-preserve=ownership $file $orig-dir>)
    });
    run(qqw<chown -R $user:$group $orig-dir>);
    run(qqw<rm -rf $backup-dir>);
}


# -----------------------------------------------------------------------------
# password hashes
# -----------------------------------------------------------------------------

# generate sha512 salted password hash from plaintext password
method gen-pass-hash(Str:D $user-pass --> Str:D)
{
    my Str:D $salt = gen-pass-salt();
    my Str:D $pass-hash = crypt($user-pass, $salt);
}

# generate sha512 salted password hash from interactive user input
method prompt-pass-hash(Str $user-name? --> Str:D)
{
    my Str:D $salt = gen-pass-salt();
    my Str:D $pass-hash-blank = crypt('', $salt);
    my Str $pass-hash;
    loop
    {
        say("Determining password for $user-name...") if $user-name;
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

# user input prompt (secret text)
sub stprompt(Str:D $prompt-text --> Str:D)
{
    ENTER { run(qw<stty -echo>); }
    LEAVE { run(qw<stty echo>); say(''); }
    my Str:D $secret = prompt($prompt-text);
}


# -----------------------------------------------------------------------------
# system information
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
    >.trim.split("\n").hyper.map({ .subst(/(.*)/, -> $/ { "/dev/$0" }) }).sort;
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
