# Reviving an Apple TV HD bricked mid software-update (Linux, no Mac needed)

**TL;DR:** if a software update on an Apple TV HD (4th gen, `AppleTV5,3`) gets
interrupted (power cut, unplugged, etc.) and the device is left on a black
screen with a slowly-blinking white LED, it is almost always recoverable —
even if an official Apple Store / Apple Authorized Service Provider tells you
it "has no fix" and needs replacing. This happened to me: the official
service said it was unrecoverable; it took about an hour of USB/DFU wrangling
on a Linux desktop to fully restore it with **no data loss** (kept its name,
Wi-Fi, and Apple ID activation).

This repo documents the exact process and the one real gotcha that will burn
hours if you don't know about it: **the `idevicerestore` build shipped by
Ubuntu/Debian is too old and fails during the DFU→Recovery handshake.** You
need to build it from source.

No Mac, no Apple Configurator, no iTunes required. Everything here runs on
Linux with free/open-source tools (`libimobiledevice` project).

## Symptoms this applies to

- Apple TV HD / Apple TV 4 (`AppleTV5,3`, the 2015 model with the A8 chip)
- Screen is black, nothing responds to the remote
- Small LED on the front panel blinks slowly
- It happened right after / during a tvOS software update
- Apple's official "If you see a warning symbol" support page
  ([support.apple.com/108807](https://support.apple.com/en-us/108807)) applies,
  but you don't have (or don't want to use) a Mac

This should also broadly apply to Apple TV 4K (1st/2nd gen, same A8/A10-ish
USB restore protocol), with different `idevicerestore` device identifiers.

## How it actually works, in short

1. Force the Apple TV into **DFU mode** using the Siri Remote (no software
   involved yet — this is a hardware-level bootrom mode).
2. From Linux, use `idevicerestore` (part of the `libimobiledevice` project)
   to download the latest signed tvOS firmware straight from Apple's servers
   and push it to the device over USB.
3. The tool walks the device through DFU → Recovery → full OS restore.
   It updates in place; it does **not** erase user data if it's just doing a
   version-matching repair restore.

The only real obstacle is that step 3 can fail with:

```
ERROR: Device did not disconnect. Possibly invalid iBSS. Reset device and try again.
ERROR: Unable to place device into recovery mode from DFU mode
```

This is a long-standing, well-documented issue
([idevicerestore#356](https://github.com/libimobiledevice/idevicerestore/issues/356),
[#563](https://github.com/libimobiledevice/idevicerestore/issues/563)) in how
`libusb` detects the device's disconnect/reconnect during the DFU→Recovery
boot-stage transfer. It's **not your hardware's fault**. Building the latest
`idevicerestore` + `libirecovery` from git source (instead of using the
Ubuntu-packaged `idevicerestore 1.0.0-3build2`, from ~2016-2020) fixed it
here. It may still take 2-3 attempts even with the new build — that's normal,
just retry the last command.

## Step-by-step

### 0. Install dependencies (needs sudo once)

```bash
sudo apt install -y git build-essential autoconf automake libtool \
  pkg-config meson ninja-build libssl-dev libzip-dev liblzma-dev \
  libglib2.0-dev libreadline-dev libcurl4-openssl-dev libusb-1.0-0-dev \
  cmake check usbmuxd libusbmuxd-utils libimobiledevice-utils \
  libirecovery-1.0-3 libirecovery-common
```

### 1. Build an up-to-date idevicerestore

```bash
bash scripts/build_idevicerestore.sh
```

This clones and builds, in order: `libplist`, `libimobiledevice-glue`,
`libusbmuxd`, `libtatsu`, `libirecovery`, `libimobiledevice`,
`idevicerestore`, all installed under `~/apple-restore-tools` (no `sudo`
needed, doesn't touch system files). Takes a few minutes.

Use the result with:

```bash
export PATH="$HOME/apple-restore-tools/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/apple-restore-tools/lib:$LD_LIBRARY_PATH"
```

### 2. Force the Apple TV into DFU mode

Keep the Apple TV connected to **power**, and connect it to your Linux
machine with a **USB-C cable** (the same port used for Apple Configurator
syncing — it's on the back of the unit).

On the **Siri Remote**:

1. Press and hold **Menu + Play/Pause** together.
2. Keep holding until the small LED on the Apple TV's front panel starts
   **blinking rapidly** (about 6 seconds).
3. Release both buttons.

Verify it worked:

```bash
lsusb | grep -i apple
# Bus 001 Device 0NN: ID 05ac:1227 Apple, Inc. Mobile Device (DFU Mode)
```

If you see `idProduct=1227` / "DFU Mode", you're in business.

### 3. Run the restore

```bash
idevicerestore --latest
```

(`--latest` downloads the newest signed firmware for your device from
Apple's own CDN and verifies/updates in place, keeping user data.)

Watch for:

```
Found device in DFU mode
Identified device as j42dap, AppleTV5,3
...
Sending iBSS (XXXXXX bytes)...
Uploading: 100.0%
```

**If it stops here** with `Device did not disconnect` / `did not reconnect`
— that's the known bug. Just put the device back in DFU (step 2) and run the
exact same command again. It's non-deterministic; it commonly takes 2-4
attempts to get past this specific transition, but once it does, the rest of
the restore (sending the OS image, personalizing components, installing
Recovery OS files) is very reliable and finishes cleanly with:

```
Got status message
Status: Restore Finished
DONE
```

### 4. Confirm it's alive

```bash
idevicepair pair
ideviceinfo
```

You should see `ActivationState: Activated`, `BrickState: false`, and your
device's `BuildVersion` / `DeviceName`. Reconnect the HDMI cable — tvOS
should boot normally with all your existing data intact.

## Troubleshooting things that turned out NOT to be the problem

In case you hit the same wall and want to skip some dead ends:

- **`usbmuxd` contention** — stopping the `usbmuxd` service
  (`sudo systemctl stop usbmuxd`) before running `idevicerestore` did **not**
  change the outcome. Not the cause here.
- **USB 3.0 vs USB 2.0 port** — switching physical ports made no difference
  when both ports are negotiated through the same xHCI controller (very
  common on modern boards — there's often no separate legacy EHCI
  controller to even test against).
- **USB autosuspend** — check `/sys/bus/usb/devices/.../power/control`;
  if it's already `on` (not `auto`), autosuspend isn't the issue.
- **A process crash in `libusb`** (`general protection fault ... in
  libusb-1.0.so`) was observed once via `dmesg`/`coredumpctl` on the first
  attempt with the old Ubuntu-packaged binary — another sign the packaged
  build is simply too old/buggy for current firmware personalization flows.

What **did** fix it: building current git `idevicerestore` + `libirecovery`,
then just retrying the DFU→Recovery step a few times.

## Credits / references

- [libimobiledevice/idevicerestore](https://github.com/libimobiledevice/idevicerestore)
- [libimobiledevice/libirecovery](https://github.com/libimobiledevice/libirecovery)
- Apple's own doc for context: [If you see a warning symbol on Apple TV](https://support.apple.com/en-us/108807)
- [theapplewiki.com DFU Mode reference](https://theapplewiki.com/wiki/DFU_Mode)

## License

MIT — see `LICENSE`.
