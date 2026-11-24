#!/bin/sh
# SPDX-License-Identifier: ISC
set -eu

HOST_OS=$(uname -s)
REAL_CHMOD=$(command -v chmod)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=$ROOT/brcm-fbsd-configurator
TESTROOT=$(mktemp -d "${TMPDIR:-/tmp}/brcm-fbsd-tests.XXXXXXXX")
trap 'rm -rf "$TESTROOT"' 0 1 2 15
MOCKBIN=$TESTROOT/bin
mkdir -p "$MOCKBIN"

fail()
{
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_contains()
{
	grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_not_contains()
{
	if grep -Fq -- "$2" "$1"; then
		fail "$1 unexpectedly contains: $2"
	fi
}

assert_mode()
{
    file=$1
    if [ "$HOST_OS" = FreeBSD ]; then
        perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file")
        [ "$perms" = 600 ] || fail "$file mode is $perms, expected 600"
    else
        grep -Eq '^chmod 600 ' "$MOCK_CHMOD_LOG" ||
            fail "no chmod 600 request for $file"
    fi
}

expect_fail()
{
	if "$@" > "$TESTROOT/failure.out" 2>&1; then
		fail "command unexpectedly succeeded: $*"
	fi
}

cat > "$MOCKBIN/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
-s) echo "${MOCK_UNAME:-FreeBSD}" ;;
-r) echo 15.1-RELEASE ;;
-m) echo amd64 ;;
*) echo "FreeBSD 15.1-RELEASE amd64" ;;
esac
EOF

cat > "$MOCKBIN/id" <<'EOF'
#!/bin/sh
echo "${MOCK_UID:-0}"
EOF

cat > "$MOCKBIN/kldstat" <<'EOF'
#!/bin/sh
[ "${MOCK_DRIVER_LOADED:-1}" = 1 ]
EOF

cat > "$MOCKBIN/sysctl" <<'EOF'
#!/bin/sh
case "$*" in
"-n net.wlan.devices") echo "${MOCK_WLDEVICES:-bcm43130}" ;;
"net.wlan.devices") echo "net.wlan.devices: ${MOCK_WLDEVICES:-bcm43130}" ;;
"-a")
	printf '%s\n' \
		'dev.bcm4313.0.rxframes: 100' \
		'dev.bcm4313.0.txframes: 80' \
		'dev.bcm4313.0.txdone: 75' \
		'dev.bcm4313.0.txnomatch: 0'
	;;
*rxframes*) echo 'dev.bcm4313.0.rxframes: 100' ;;
*txframes*) echo 'dev.bcm4313.0.txframes: 80' ;;
*txdone*) echo 'dev.bcm4313.0.txdone: 75' ;;
*txnomatch*) echo 'dev.bcm4313.0.txnomatch: 0' ;;
*) echo "${MOCK_WLDEVICES:-bcm43130}" ;;
esac
EOF

cat > "$MOCKBIN/ifconfig" <<'EOF'
#!/bin/sh
printf 'ifconfig %s\n' "$*" >> "$MOCK_LOG"
iface=${MOCK_WLANIF:-wlan0}
case "$*" in
"$iface destroy")
	rm -f "$MOCK_STATE"
	exit 0
	;;
"$iface create wlandev "*)
	: > "$MOCK_STATE"
	exit 0
	;;
"$iface wlandev")
	[ -f "$MOCK_STATE" ] || exit 1
	[ "${MOCK_WLANDEV_FAIL:-0}" = 0 ] || exit 1
	echo "${MOCK_PARENT:-bcm43130}"
	exit 0
	;;
"$iface list scan")
	[ -f "$MOCK_STATE" ] || exit 1
	[ "${MOCK_SCAN_EMPTY:-0}" = 0 ] || exit 0
	cat <<'SCAN'
SSID/MESH BSSID CHAN RATE SIGNAL DBM NOISE SECURITY
Test Net aa:bb:cc:dd:ee:01 6 54 -42 0 RSN BSSLOAD HTCAP WME
Open Net aa:bb:cc:dd:ee:02 11 54 -55 0 OPEN
SCAN
	exit 0
	;;
"$iface scan")
	[ -f "$MOCK_STATE" ] || exit 1
	exit 0
	;;
"$iface")
	[ -f "$MOCK_STATE" ] || exit 1
	cat <<'STATUS'
wlan0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST> metric 0 mtu 1500
	ether 02:00:00:00:00:01
	inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
	parent interface: bcm43130
	status: associated
STATUS
	exit 0
	;;
*) exit 0 ;;
esac
EOF

cat > "$MOCKBIN/wpa_passphrase" <<'EOF'
#!/bin/sh
[ $# -ge 1 ] || exit 1
ssid=$1
if [ $# -ge 2 ]; then
	pass=$2
else
	pass=$(cat)
fi
printf 'network={\n\tssid="%s"\n\t#psk=%s\n\tpsk=derived-key\n}\n' "$ssid" "$pass"
EOF

cat > "$MOCKBIN/wpa_supplicant" <<'EOF'
#!/bin/sh
printf 'wpa_supplicant %s\n' "$*" >> "$MOCK_LOG"
[ "${MOCK_WPA_FAIL:-0}" = 0 ]
EOF

cat > "$MOCKBIN/wpa_cli" <<'EOF'
#!/bin/sh
echo 'ssid=Test Net'
EOF

cat > "$MOCKBIN/dhclient" <<'EOF'
#!/bin/sh
printf 'dhclient %s\n' "$*" >> "$MOCK_LOG"
EOF

cat > "$MOCKBIN/netstat" <<'EOF'
#!/bin/sh
printf '%s\n' 'default 192.0.2.1 UGS 0 0'
EOF

cat > "$MOCKBIN/ping" <<'EOF'
#!/bin/sh
printf 'ping %s\n' "$*" >> "$MOCK_LOG"
[ "${MOCK_PING_FAIL:-0}" = 0 ]
EOF

cat > "$MOCKBIN/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$MOCKBIN/stty" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$MOCKBIN/dmesg" <<'EOF'
#!/bin/sh
echo 'bcm43130: attached'
EOF

cat > "$MOCKBIN/pciconf" <<'EOF'
#!/bin/sh
echo 'bcm4313_pci0@pci0:1:0:0: class=0x028000 card=0x472714e4 chip=0x472714e4 rev=0x01 hdr=0x00'
EOF

cat > "$MOCKBIN/chmod" <<EOF
#!/bin/sh
printf 'chmod %s\n' "\$*" >> "\$MOCK_CHMOD_LOG"
exec "$REAL_CHMOD" "\$@"
EOF

chmod +x "$MOCKBIN"/*

export PATH=$MOCKBIN:$PATH
export MOCK_LOG=$TESTROOT/commands.log
export MOCK_CHMOD_LOG=$TESTROOT/chmod.log
export MOCK_STATE=$TESTROOT/iface.state
export MOCK_WLANIF=wlan0
export WLANIF=wlan0
export WLDEV=bcm43130
export TIMEOUT=1
export NO_TUI=1
export BRCM_RC_CONF=$TESTROOT/rc.conf
export BRCM_WPA_CONF=$TESTROOT/wpa.conf
export BRCM_CTRL_DIR=$TESTROOT/ctrl
: > "$MOCK_LOG"
: > "$MOCK_CHMOD_LOG"
: > "$MOCK_STATE"
: > "$BRCM_RC_CONF"

sh -n "$APP"
sh -n "$ROOT/tests/run.sh"

sh "$APP" --help > "$TESTROOT/help.out"
assert_contains "$TESTROOT/help.out" 'Passwords are never accepted as positional command-line arguments.'

sh "$APP" version > "$TESTROOT/version.out"
assert_contains "$TESTROOT/version.out" 'brcm-fbsd-configurator 1.0.0'

sh "$APP" status > "$TESTROOT/status.out"
assert_contains "$TESTROOT/status.out" 'Driver module: loaded (bhnd/if_bcm4313)'
assert_contains "$TESTROOT/status.out" 'Parent device: bcm43130'
MOCK_WLANDEV_FAIL=1 sh "$APP" status > "$TESTROOT/status-fallback.out"
assert_contains "$TESTROOT/status-fallback.out" 'Interface: wlan0 (parent bcm43130)'

sh "$APP" scan > "$TESTROOT/scan.out"
assert_contains "$TESTROOT/scan.out" 'aa:bb:cc:dd:ee:01'
assert_contains "$TESTROOT/scan.out" 'Test Net'
assert_contains "$TESTROOT/scan.out" 'Open Net'
assert_contains "$TESTROOT/scan.out" 'WPA'

sh "$APP" connect --open --ping 'Open Net' > "$TESTROOT/open.out"
assert_contains "$TESTROOT/open.out" 'Connected to Open Net on wlan0.'
assert_contains "$TESTROOT/open.out" 'Ping: ok'
assert_contains "$MOCK_LOG" 'ifconfig wlan0 ssid Open Net up'
assert_contains "$MOCK_LOG" 'dhclient wlan0'

printf '%s\n' 'correct horse battery staple' > "$TESTROOT/pass.txt"
chmod 600 "$TESTROOT/pass.txt"
sh "$APP" connect --boot --ping --password-file "$TESTROOT/pass.txt" \
	'Test Net' > "$TESTROOT/wpa.out"
assert_contains "$TESTROOT/wpa.out" 'Connected to Test Net on wlan0.'
assert_contains "$BRCM_WPA_CONF" 'ssid="Test Net"'
assert_contains "$BRCM_WPA_CONF" 'psk=derived-key'
assert_not_contains "$BRCM_WPA_CONF" '#psk='
[ "$(grep -c '^network={' "$BRCM_WPA_CONF")" -eq 1 ] || fail 'WPA config has the wrong network block count'
assert_mode "$BRCM_WPA_CONF"
assert_contains "$BRCM_RC_CONF" 'wlans_if_bcm43130="wlan0"'
assert_contains "$BRCM_RC_CONF" 'ifconfig_wlan0="WPA DHCP"'
assert_contains "$BRCM_RC_CONF" 'wpa_supplicant_enable="YES"'
assert_contains "$MOCK_LOG" 'wpa_supplicant -B -Dbsd -i wlan0'

cat > "$TESTROOT/existing.conf" <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
network={
    ssid="Existing"
    psk=derived-key
}
EOF
BRCM_WPA_CONF=$TESTROOT/existing-installed.conf \
	sh "$APP" wpa --boot "$TESTROOT/existing.conf" > "$TESTROOT/existing.out"
assert_contains "$TESTROOT/existing-installed.conf" 'ssid="Existing"'
assert_mode "$TESTROOT/existing-installed.conf"

expect_fail env MOCK_PARENT=other0 sh "$APP" connect --open 'Open Net'
assert_contains "$TESTROOT/failure.out" 'belongs to'
env MOCK_PARENT=other0 sh "$APP" connect --open --recreate 'Open Net' > "$TESTROOT/recreate.out"
assert_contains "$MOCK_LOG" 'ifconfig wlan0 destroy'
assert_contains "$MOCK_LOG" 'ifconfig wlan0 create wlandev bcm43130'

expect_fail env MOCK_DRIVER_LOADED=0 sh "$APP" connect --open 'Open Net'
assert_contains "$TESTROOT/failure.out" 'not loaded'
expect_fail env MOCK_UNAME=Linux sh "$APP" connect --open 'Open Net'
assert_contains "$TESTROOT/failure.out" 'FreeBSD only'
expect_fail env MOCK_UID=1000 sh "$APP" connect --open 'Open Net'
assert_contains "$TESTROOT/failure.out" 'as root'
expect_fail env MOCK_WPA_FAIL=1 sh "$APP" connect --password-file "$TESTROOT/pass.txt" 'Test Net'
assert_contains "$TESTROOT/failure.out" 'wpa_supplicant failed'
expect_fail env MOCK_SCAN_EMPTY=1 sh "$APP" scan
assert_contains "$TESTROOT/failure.out" 'no networks found'
expect_fail sh "$APP" connect --open --password-file "$TESTROOT/pass.txt" 'Open Net'
assert_contains "$TESTROOT/failure.out" '--open cannot be combined'

printf '%s\n' 'All companion app tests passed.'
