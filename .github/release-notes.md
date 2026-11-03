## ⬇️ What to download

| File | What it is |
| --- | --- |
| **TubeVault.zip** | The Mac app |
| **TubeVault-Chrome-Extension.zip** | Adds the download button to the YouTube player in Chrome |

## Quick setup

1. In Terminal, run `brew install yt-dlp ffmpeg deno`.
2. Unzip **TubeVault.zip** and drag **TubeVault.app** into **Applications**.
3. **If macOS blocks it** ("Apple could not verify…" or "damaged"): click **Done**, then go to **System Settings › Privacy & Security**, scroll to **Security**, and click **Open Anyway**. If it's still blocked, run `xattr -dr com.apple.quarantine /Applications/TubeVault.app` in Terminal.
4. Unzip the extension and move the **TubeVault Chrome Extension** folder somewhere permanent. In Chrome, go to `chrome://extensions`, turn on **Developer mode** (top-right toggle), click **Load unpacked**, and select that folder.
5. Open any YouTube video and click the **⬇** icon in the player's bottom bar. When it's saved, click **Open TubeVault** to watch it, paused at the same spot.

**Upgrading from 1.1 or earlier:** remove the old TubeVault extension in `chrome://extensions` and load the new folder once. Videos you already downloaded move into TubeVault's own folder automatically.

The app shows these steps on first launch, and you can reopen them from **Help › TubeVault Setup Guide**. The full guide is in the [README](https://github.com/SyedInayatShah/TubeVault#-setup-about-5-minutes).
