Install
=======

If you intend to run Archvault in a LiveCD environment, *you must boot the
LiveCD from RAM* to avoid running out of disk space on the LiveCD. Using
the official Arch Linux ISO, when you see the boot loader screen, press
<kbd>Tab</kbd> and [append the following][gist] parameter to the kernel
line: `copytoram=y`.

In order to use Archvault, install [Rakudo Perl 6][rakudo]. Archvault
will automatically resolve all other dependencies.

[gist]: https://gist.github.com/satreix/c01fd1cb5168e539404b
[rakudo]: https://github.com/rakudo/rakudo
