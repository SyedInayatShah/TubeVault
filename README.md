# TubeVault

A clean, native macOS app for saving YouTube videos and watching them **offline**.

- **Right-click → Download with TubeVault** on any YouTube video in Chrome (or Safari via the Services menu)
- Videos save to `~/Downloads/TubeVault` as regular `.mp4` files
- A library window (from the Dock) that shows **only downloaded videos** and works with no internet
- A **Downloading** section with live progress, speed, time left and cancel/retry
- Create **libraries** and move videos between them (drag onto a library in the sidebar, or right-click → Move to Library)
- Search, sort, built-in player with full screen and Picture in Picture

## Requirements

- macOS 14 Sonoma or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) and ffmpeg (does the actual downloading):

```bash
brew install yt-dlp ffmpeg deno
```

## Install

**From GitHub:** grab `TubeVault.zip` from the [Releases](../../releases) page, unzip, and drag `TubeVault.app` into Applications. The app is ad-hoc signed, so the first time right-click it → **Open**.

**From source:**

```bash
./scripts/build-app.sh
cp -R build/TubeVault.app /Applications/
```

Then drag TubeVault from Applications into your Dock.

## Right-click in Chrome

1. Open `chrome://extensions` and turn on **Developer mode**
2. Click **Load unpacked** and choose the `extension/chrome` folder
3. Right-click any YouTube video, thumbnail or watch page → **Download with TubeVault**
4. The first time, Chrome asks to open TubeVault — tick **Always allow** and click **Open**

You can also click the TubeVault toolbar button while on a video page.

## Right-click in Safari / other apps

Right-click a YouTube link → **Services → Download with TubeVault**. (If it doesn't appear, log out and back in once so macOS picks up the new service.)

## Other ways to download

- Press **⌘D** in the app and paste a link (it auto-fills from your clipboard)
- Open `tubevault://download?url=<encoded YouTube URL>` from anywhere

## How it works

| Piece | Where |
| --- | --- |
| SwiftUI app | `Sources/TubeVault` |
| Download engine (wraps yt-dlp, parses progress) | `Sources/TubeVault/DownloadManager.swift` |
| Library data | `~/Library/Application Support/TubeVault/library.json` |
| Video files | `~/Downloads/TubeVault/` |
| Chrome extension | `extension/chrome` |
| CI build + releases | `.github/workflows/build.yml` — push a `v*` tag to publish a release |

Videos are downloaded as H.264/AAC MP4 (up to 1080p) so they play natively. Deleting a file in Finder removes it from the library automatically.

Please only download videos you have the right to save, and respect YouTube's Terms of Service.
