# cloudet drag'n'drop

A floating cloud for macOS. Drop files onto it and they stay as copies: the original stays where it is, and the copy can be dragged somewhere else.

The app lives in the menu bar. The cloud floats above other windows, on every desktop, including full screen. Click it to open the shelf. Press Escape to close it. It remembers where you left it.

## What you can drop

- Files, folders, and packages from Finder.
- Images copied from a browser, a screenshot, or an image link (PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP, SVG, AVIF, and others).

Copies are kept in `~/Library/Application Support/cloudet`. Clearing the cloud, or removing one item, deletes only those copies.

Drag a row out to copy it into another app. Double-click a row to show that copy in Finder.

## Requirements

macOS 14 or later. Release builds are universal: Apple Silicon and Intel.

The interface follows the system language: English, Russian, German, French, Spanish, Portuguese, Brazilian Portuguese, Italian, Dutch, Polish, Ukrainian, Turkish, Arabic, Japanese, Korean, Simplified Chinese, and Traditional Chinese.

## Install

1. Open [Releases](../../releases) and download `cloudet-<version>.dmg`.
2. Open the disk image and drag **cloudet drag'n'drop** into Applications.
3. The first time, right-click the app and choose **Open**. Builds from GitHub are not signed with a Developer ID and are not notarized, so macOS asks you to confirm.

## Menu bar

- **Show Cloud** / **Hide Cloud**
- **Open Copies in Finder**
- **Clear Cloud** — removes copies only
- **Quit cloudet**

## Build

Xcode is required.

```bash
./build.sh                 # build and launch
./build.sh --test          # the same, plus checks
./build.sh --dmg           # dist/cloudet-<version>.dmg, without launching
```

The disk image version comes from `CLOUDET_VERSION` (default `1.0`).

## Release

Push a tag such as `v1.0.0`. Actions builds the DMG and attaches it to a GitHub Release. A build that is not a release is kept as an artifact on every push to `main`.

## Credits

The cloud silhouette is drawn from [Tabler Icons](https://github.com/tabler/tabler-icons) `cloud-filled` (MIT, Paweł Kuna).
