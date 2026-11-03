<div align="center">

<img src="docs/icon.png" width="128" alt="TubeVault icon">

# TubeVault

**Save YouTube videos to your Mac in one click and watch them offline.**

[![Build](https://github.com/SyedInayatShah/TubeVault/actions/workflows/build.yml/badge.svg)](https://github.com/SyedInayatShah/TubeVault/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/SyedInayatShah/TubeVault?color=e62117)](https://github.com/SyedInayatShah/TubeVault/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)

### ⬇️ Download

[**TubeVault.zip**](https://github.com/SyedInayatShah/TubeVault/releases/latest/download/TubeVault.zip) — the Mac app &nbsp;·&nbsp;
[**TubeVault-Chrome-Extension.zip**](https://github.com/SyedInayatShah/TubeVault/releases/latest/download/TubeVault-Chrome-Extension.zip) — the Chrome download button

<br>

<img src="docs/library.png" width="760" alt="TubeVault library window">

</div>

---

## ✨ Features

- **Download button in the YouTube player.** It sits in the video's bottom control bar, next to the subtitles and settings icons, with a live progress bar beside it.
- **Offline library.** Open TubeVault from your Dock to see only your downloaded videos. It works with no internet.
- **Downloading tab** with progress, speed, time left, cancel and retry.
- **Libraries.** Make your own collections and drag videos into them.
- **Built-in player** with full screen and Picture in Picture.
- Files are plain `.mp4`s in **Downloads › TubeVault**, so you can also open them in Finder.

---

## 🚀 Setup (about 5 minutes)

### 1. Install the download engine

TubeVault uses the free tools [yt-dlp](https://github.com/yt-dlp/yt-dlp) and ffmpeg. If you don't have [Homebrew](https://brew.sh), install that first. Then paste this into **Terminal**:

```bash
brew install yt-dlp ffmpeg deno
```

### 2. Install the app

1. Download **[TubeVault.zip](https://github.com/SyedInayatShah/TubeVault/releases/latest/download/TubeVault.zip)** and double-click it to unzip.
2. Drag **TubeVault.app** into your **Applications** folder.
3. Open it. To keep it in your Dock, right-click its Dock icon › **Options** › **Keep in Dock**.

### 3. 🔒 If macOS blocks TubeVault

TubeVault isn't from the App Store, so the first time you open it macOS may say **"Apple could not verify TubeVault is free of malware"** or **"TubeVault is damaged and can't be opened"**. To allow it:

1. On the warning, click **Done** (not *Move to Trash*).
2. Open  **System Settings** › **Privacy & Security**.
3. Scroll down to the **Security** section. Next to *"TubeVault" was blocked to protect your Mac*, click **Open Anyway**.
4. Enter your Mac password, then click **Open Anyway** again.

<details>
<summary><b>Still blocked, or it says "damaged"?</b></summary>

Paste this into Terminal, then open TubeVault again:

```bash
xattr -dr com.apple.quarantine /Applications/TubeVault.app
```

This removes the "downloaded from the internet" flag macOS adds to files from the web. You only need to do it once per update.
</details>

### 4. 🧩 Add the download button to Chrome

The extension isn't on the Chrome Web Store, so you load it with Chrome's **Developer mode**.

1. Download **[TubeVault-Chrome-Extension.zip](https://github.com/SyedInayatShah/TubeVault/releases/latest/download/TubeVault-Chrome-Extension.zip)** and unzip it. You'll get a folder called **TubeVault Chrome Extension**. Move it somewhere permanent, like your Documents folder. Chrome loads it from there, so don't delete it.
   > Or, in TubeVault, open **Help › TubeVault Setup Guide** and click **Save Extension**. That puts the folder in **Downloads › TubeVault** for you.
2. In Chrome, type **`chrome://extensions`** in the address bar and press Return.
3. **Turn on Developer mode** with the toggle in the **top-right corner** of the page. Three new buttons appear on the left.
4. Click **Load unpacked**, select the **TubeVault Chrome Extension** folder, and click **Select**.
5. *(Optional)* Click the 🧩 puzzle icon in Chrome's toolbar and **pin** TubeVault.

You're done. Open any YouTube video and look for the **⬇ download icon** in the player's bottom bar.

> You'll see a "Developer mode extensions" notice now and then when Chrome starts. That's normal for extensions not from the Web Store. Just close it.

**All of these steps are also in the app.** TubeVault shows them the first time you open it, and you can reopen them from **Help › TubeVault Setup Guide** or the **?** button at the bottom of the sidebar.

---

## 🎬 Using it

| Want to… | Do this |
| --- | --- |
| Download the video you're watching | Click the **⬇** icon in the YouTube player's bottom bar. A red progress bar shows next to it, and it turns into a ✓ when saved. |
| Download from a thumbnail | Right-click the thumbnail › **Download with TubeVault** |
| Download from Safari or another app | Right-click a YouTube link › **Services › Download with TubeVault** |
| Paste a link | Press **⌘D** in TubeVault |
| Watch offline | Open **TubeVault** from your Dock and click any video |
| Organise | Click **New Library**, then drag videos onto it (or right-click › **Move to Library**) |
| Check progress | Click **Downloading** in the sidebar |

Downloads keep running if you close the window. Deleting a video in Finder also removes it from the library.

### Updating the extension

After updating, open `chrome://extensions` and click the **↻ reload** arrow on the TubeVault card.

---

## 🛠 Build from source

Requires Xcode 15+ (or the Swift 5.10 toolchain).

```bash
git clone https://github.com/SyedInayatShah/TubeVault.git
cd TubeVault
./scripts/build-app.sh
cp -R build/TubeVault.app /Applications/
```

Then load the `extension/chrome` folder in Chrome as described above.

### How it works

| Piece | Where |
| --- | --- |
| SwiftUI app | `Sources/TubeVault` |
| Download engine (runs yt-dlp, reads progress) | `Sources/TubeVault/DownloadManager.swift` |
| Local server the extension talks to (`127.0.0.1:47823`, only accepts the extension) | `Sources/TubeVault/LocalServer.swift` |
| In-app setup guide | `Sources/TubeVault/SetupGuideView.swift` |
| Chrome extension (player button, right-click menu) | `extension/chrome` |
| Library data | `~/Library/Application Support/TubeVault/library.json` |
| Video files | `~/Downloads/TubeVault/` |
| CI build and releases | `.github/workflows/build.yml`. Push a `v*` tag to publish a release. |

Videos download as H.264/AAC MP4 (up to 1080p) so they play natively on any Mac.

---

<sub>Only download videos you have the right to save, and respect YouTube's Terms of Service.</sub>
