use v6;
use Archvault::Grammar;

# test user name validation

# a
# 1 char works

# _
# 1 char underline works

# &
# 1 char ampersand does not

# asdfghkjlzxcvbnmqwertyuiop
# 26 chars works

# asdfghkjlzxcv$bnmqwertyuiop
# 27 chars incl dollar sign in the middle does not

# asdfghkjlzxcvbnmqwertyuiop$
# 27 chars incl dollar sign at the end works

# asdfghkjlzxcvbnmqwertyuiopzzzzz$
# 32 chars incl dollar sign at the end works

# asdfghkjlzxcvbnmqwertyuiopzzzzzz$
# 33 chars incl dollar sign at the end does not

# vim: set filetype=perl6 foldmethod=marker foldlevel=0:
