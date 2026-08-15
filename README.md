# dellmon — switch a Dell U2724DE (or any Dell KVM monitor) between machines from the keyboard

Talks DDC/CI to the monitor so you never touch the OSD joystick. Same script on both machines:

| OS    | backend                                                     |
|-------|-------------------------------------------------------------|
| macOS | `macos/ddcvcp` (tiny Swift tool, private IOAVService I2C – Apple Silicon, DP-alt-mode/TB link) |
| Linux | `ddcutil` (needs `i2c-dev` + permission on `/dev/i2c-*`)   |

## Install (both machines)

```sh
git clone <this repo> ~/code/dell-control && ~/code/dell-control/install.sh
```

## One-time monitor setup (so USB follows the video input)

On the monitor OSD: **Menu → USB → USB assignment** (Dell calls it "KVM" / "USB Switch") and bind each video
input to the upstream port that computer's keyboard/mouse hub is on
(e.g. *Thunderbolt/USB-C ⇄ Mac*, *DisplayPort ⇄ USB-C upstream from Linux*).
Once that is done, changing the video input also moves keyboard+mouse — which is all `dellmon` needs to do.

## Use

```sh
dellmon status          # what input is active, brightness, contrast
dellmon linux           # switch to Linux setup (== dellmon switch linux)
dellmon mac             # switch back
dellmon toggle          # flip to the other one
dellmon brightness 60   # or +10 / -10 ;  dellmon contrast 75
```

Bind `dellmon toggle` to a hotkey (macOS: Shortcuts/Raycast/skhd; Linux: your DE keyboard shortcuts)
and to a keyboard-macro if you want a true "KVM button".

## Config

`config.json` (repo) — or `~/.config/dellmon/config.json` / `$DELLMON_CONFIG` if present.

```json
{
  "setups": {
    "mac":   { "input": "0x19" },          // U2724DE: 0x19 = Thunderbolt/USB-C, 0x0f = DP, 0x11 = HDMI, 0x1b = USB-C on other Dells
    "linux": { "input": "0x0f" }
  },
  "usb_vcp": "0xE7",     // only used if a setup also has "usb": "<hex>" (explicit KVM switch, model specific)
  "ddcutil_args": [],    // linux: ["--bus","7"] if you have several DDC displays
  "mac_display": 1       // macos: index from  macos/ddcvcp list
}
```

The `mac` value was read from the actual monitor. **On Linux run `dellmon status` (or `dellmon learn linux`)
once to confirm/record the input value** the Linux box is on (`0x0f` = DP is the guess).

## Poking at the monitor

```sh
dellmon get 0x60             # raw read
dellmon set 0xE7 0xff00      # raw 16-bit write (Dell USB switch codes: try/observe, they vary per model)
dellmon scan 0xE0 0xFF       # dump vendor codes
```

Notes
- Only the machine currently *shown* on the monitor can reliably talk DDC (the I2C channel rides on the video link),
  so each machine only ever needs to switch *away* from itself — that's what the design assumes.
- macOS: the DDC helper only works for displays on USB-C/Thunderbolt/DP on Apple Silicon (not the built-in HDMI port of base M1/M2).
- Linux: if `ddcutil detect` shows nothing, `sudo modprobe i2c-dev` and add yourself to the `i2c` group / relogin.
