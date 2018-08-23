# Configure Wireless

## Bringing up the wireless interface

Find the right wireless interface:

```sh
ip link
```

Let's assume it's `wlan0`.

Bring up the wireless interface:

```sh
ip link set wlan0 up
```

## Connecting with `wpa_passphrase`

```sh
wpa_passphrase "myssid" "passphrase" > /etc/wpa_supplicant/myssid.conf
cat >> /etc/systemd/system/wpa_supplicant-myssid@.service.d/conf_file.conf <<'EOF'
SSID=myssid
CONF_FILE="/etc/wpa_supplicant/$SSID.conf"
EOF
cat >> /usr/lib/systemd/system/wpa_supplicant-myssid@.service <<'EOF'
[Unit]
Description=WPA supplicant daemon (interface-specific version for myssid)
Requires=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
Before=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/wpa_supplicant -i %I -c $CONF_FILE

[Install]
Alias=multi-user.target.wants/wpa_supplicant-myssid@%i.service
EOF
systemctl start wpa_supplicant-myssid@wlan0
```

or:

```sh
wpa_supplicant -B -i wlan0 [-Dnl80211,wext] -c <(wpa_passphrase "myssid" "passphrase")
```

If the passphrase contains special characters, rather than escaping them,
invoke `wpa_passphrase` without specifying the passphrase.

## Connecting with `wpa_cli`

Configure `wpa_supplicant` for use with `wpa_cli`:

```sh
cat >> /etc/wpa_supplicant/wpa_supplicant.conf <<'EOF'
# give configuration update rights to wpa_cli
ctrl_interface=/run/wpa_supplicant
ctrl_interface_group=wheel
update_config=1

# enable AP scanning
ap_scan=1

# EAPOL v2 provides better security, but use v1 for wider compatibility
eapol_version=1

# enable fast re-authentication (EAP-TLS session resumption) if supported
fast_reauth=1
EOF
```

Run `wpa_supplicant`:

```sh
cat >> /etc/systemd/system/wpa_supplicant@.service.d/conf_file.conf <<'EOF'
CONF_FILE="/etc/wpa_supplicant/wpa_supplicant.conf"
EOF
cat >> /usr/lib/systemd/system/wpa_supplicant@.service <<'EOF'
[Unit]
Description=WPA supplicant daemon (interface-specific version)
Requires=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
Before=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/wpa_supplicant -i %I -c $CONF_FILE

[Install]
Alias=multi-user.target.wants/wpa_supplicant@%i.service
EOF
systemctl start wpa_supplicant@wlan0
```

or:

```sh
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
```

Run `wpa_cli`:

```sh
wpa_cli
```

Use the `scan` and `scan_results` commands to see the available networks:

```
> scan
OK
<3>CTRL-EVENT-SCAN-RESULTS
> scan_results
bssid / frequency / signal level / flags / ssid
00:00:00:00:00:00 2462 -49 [WPA2-PSK-CCMP][ESS] myssid
11:11:11:11:11:11 2437 -64 [WPA2-PSK-CCMP][ESS] ANOTHERSSID
```

To associate with `myssid`, add the network, set the credentials and
enable it:

```
> add_network
0
> set_network 0 ssid "myssid"
> set_network 0 psk "passphrase"
> enable_network 0
<2>CTRL-EVENT-CONNECTED - Connection to 00:00:00:00:00:00 completed (reauth) [id=0 id_str=]
```

If the SSID does not have password authentication, you must explicitly
configure the network as keyless by replacing the command:

```
> set_network 0 psk "passphrase"
```

with:

```
> set_network 0 key_mgmt NONE
```

Save this network:

```
> save_config
OK
```

## Obtaining an IP address

### using `dhclient`:

```sh
systemctl start dhclient@wlan0
```

### using `dhcpcd`:

```sh
systemctl start dhcpcd@wlan0
```
