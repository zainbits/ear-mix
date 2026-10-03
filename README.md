# EarMix

A small macOS menu bar app that plays the same audio on several outputs at once
(two wired earphones and a Bluetooth pair, for example) while keeping a separate
volume slider for each one.

- Every physical output is detected automatically; earphones are ticked the first time they appear.
- Flip **Combine** to play on all ticked outputs. Flip it off to go back to the output you had before.
- Each output has its own volume slider and mute button, whether or not you are combining.
- Plug or unplug something while combined and the mix rebuilds itself.

## How it works

EarMix creates a standard macOS Multi-Output Device (a stacked CoreAudio
aggregate, the same thing Audio MIDI Setup makes) and sets it as the system
output. A wired device is the clock master; every other member gets drift
correction so they stay in sync. Volumes are set on each real device, so they
also stick when you use that device on its own.

Quitting EarMix removes the combined device and restores your previous output.

## Limits

- Bluetooth audio lags wired audio by roughly 150-250 ms. macOS cannot align that.
- The keyboard volume keys do nothing while combined (a macOS limit for
  multi-output devices). Use the sliders.
- Outputs without a software volume control (most displays) show "Fixed volume".

## Requirements

- macOS 14 or later
- Xcode or the Xcode Command Line Tools (`xcode-select --install`)

## Build and install

```sh
./scripts/build-app.sh            # builds build.noindex/EarMix.app
./scripts/build-app.sh --install  # also copies it to /Applications and launches it
```
