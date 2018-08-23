# Configure SSH Port Forwarding

Open a local tunnel to guest machine port 54321 on host machine at
port 12345.

**On guest machine**:

```sh
pacman -S darkhttpd
darkhttpd "$PWD" --addr 127.0.0.1 --port 54321
systemctl start sshd
```

**On host machine**:

```sh
ssh -N -T -L 12345:127.0.0.1:54321 variable@vbox-arch64
```

Open a web browser and visit http://127.0.0.1:12345.
