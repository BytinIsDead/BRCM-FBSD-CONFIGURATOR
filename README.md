# BRCM-FBSD-CONFIGURATOR

A dependency-light FreeBSD configurator for the `if_bcm4313` driver. It provides a terminal UI, network scanning, WPA/WPA2 and open-network joins, DHCP, boot persistence, status, and diagnostics.

This repository contains only the configurator. It does **not** contain the kernel module, Broadcom firmware, or firmware license terms; those remain in the separate `brcmsmac-freebsd` driver repository.

## Requirements

- FreeBSD 13 or newer
- `if_bcm4313` installed and loaded as `bhnd/if_bcm4313`
- A visible `bcm4313*` device in `sysctl net.wlan.devices`
- `wpa_supplicant` and `wpa_passphrase` for protected networks
- Optional `dialog(1)` for the full-screen terminal UI

## Install

```sh
sudo make install
```

This installs:

- `/usr/local/bin/brcm-fbsd-configurator`
- `/usr/local/share/man/man8/brcm-fbsd-configurator.8`

## Use

Run the menu:

```sh
sudo brcm-fbsd-configurator
```

Scan without joining:

```sh
sudo brcm-fbsd-configurator scan
```

Join an open network:

```sh
sudo brcm-fbsd-configurator connect --open 'MyOpenNetwork'
```

Join a protected network with a hidden prompt:

```sh
sudo brcm-fbsd-configurator connect --ask-password 'MyNetwork'
```

Persist the protected network for boot:

```sh
sudo brcm-fbsd-configurator connect --ask-password --boot 'MyNetwork'
```

Use an existing supplicant configuration:

```sh
sudo brcm-fbsd-configurator wpa --boot /path/to/wpa_supplicant.conf
```

Check status or collect a diagnostic report:

```sh
brcm-fbsd-configurator status
sudo brcm-fbsd-configurator diagnose
```

## Safety and security

- Passwords are not accepted as positional command-line arguments.
- `--password-file FILE` reads a passphrase from a file; use `-` for stdin.
- Generated WPA files are mode `0600`, and `wpa_passphrase` plaintext comments are removed.
- Existing interfaces are reused. `--recreate` is required before destroying and recreating a VAP with a different parent.
- Boot mode refuses to overwrite an existing WPA configuration unless `--force` is supplied.
- Conflicting `rc.conf` keys are reported rather than silently rewritten.

## Configuration overrides

| Variable | Default |
|---|---|
| `WLANIF` | `wlan0` |
| `WLDEV` | first `bcm4313*` device |
| `TIMEOUT` | `30` |
| `BRCM_RC_CONF` | `/etc/rc.conf` |
| `BRCM_WPA_CONF` | `/etc/wpa_supplicant.conf` |
| `BRCM_CTRL_DIR` | `/var/run/wpa_supplicant` |
| `NO_TUI` | unset |

Example with a non-default interface and isolated test configuration:

```sh
sudo env WLANIF=wlan1 WLDEV=bcm43130 \
    BRCM_RC_CONF=/etc/rc.conf.local \
    BRCM_WPA_CONF=/etc/wpa_supplicant_bcm4313.conf \
    brcm-fbsd-configurator connect --ask-password --boot 'MyNetwork'
```

## Tests

```sh
make test
```

The test suite mocks FreeBSD network commands and exercises scanning, open and WPA joins, DHCP, boot persistence, permission handling, interface recreation, and failure paths without touching Wi-Fi hardware.

## License

ISC. See [LICENSE](LICENSE).
