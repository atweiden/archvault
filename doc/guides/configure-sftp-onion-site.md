# Configure SFTP Onion Site

**On guest machine**:

- Install `tor`

```sh
pacman -S tor
```

- Configure `tor`

```sh
cat >> /etc/tor/torrc <<'EOF'
HiddenServiceDir /var/lib/tor/sftp
HiddenServicePort 9449 127.0.0.1:22
HiddenServiceVersion 3
EOF
```

- Create hidden service directory with locked down permissions

```sh
mkdir /var/lib/tor/sftp
chown -R tor:tor /var/lib/tor/sftp
chmod 700 /var/lib/tor/sftp
```

- Retrieve onion site hostname

```sh
systemctl start tor
systemctl stop tor
cat /var/lib/tor/sftp/hostname
```

- Let's assume the onion site's hostname is
  `vzedexhc4jr2waxejybjlzu7xtfb3gswykjdojsmv2plvdb5mqpm7qyd.onion`

**On host machine**:

- Install `openssh`, `socat` and `tor` (or *Tor Browser Bundle*)

```sh
# arch
pacman -S openssh socat tor

# mac
brew install openssh socat tor
```

- Use instructions from section ["Configure SSH Pubkey Authentication
  for Host-Guest SSH"][pubkey-auth] to setup pubkey authentication
- Configure ssh for use with `tor`
  - Set `socksport=9150` if running Tor Browser Bundle

```sshconfig
Host vbox-arch64-onion
    HostName vzedexhc4jr2waxejybjlzu7xtfb3gswykjdojsmv2plvdb5mqpm7qyd.onion
    Port 9449
    PubkeyAuthentication yes
    IdentityFile ~/.ssh/vbox-arch64/id_ed25519
    Compression yes
    ProxyCommand socat STDIO SOCKS4A:localhost:%h:%p,socksport=9050
```

**On guest machine**:

- Start `sshd` and `tor`:

```sh
systemctl start sshd
systemctl start tor
```

**On host machine**:

- Start `tor` or Tor Browser Bundle
- Try `sftp` with shortcut
  - `sftp variable@vbox-arch64-onion`
    - succeeds


[pubkey-auth]: ../README-VM.md#configure-ssh-pubkey-authentication-for-host-guest-ssh
