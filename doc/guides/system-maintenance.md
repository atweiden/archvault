# System Maintenance

Change vault password:

```sh
cryptsetup luksChangeKey /dev/sda3
```

Clear pkg cache:

```sh
pkgcacheclean -h -v 1
```
