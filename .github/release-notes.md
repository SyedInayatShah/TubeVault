## What's new in 1.5.7

- **Much faster downloads, same quality.** YouTube slows down each single connection, so TubeVault now fetches every video in pieces over 8 connections at once. It's the same file at the same resolution (up to 4K), roughly twice as fast or more, up to the speed of your internet.
- **Your videos come first.** While a video you clicked is downloading, **Save all** Shorts wait, so the video gets your whole connection.
- **Shorts download faster too:** each one uses the 8 connections, and Save all runs up to 5 at a time.
- **Save all saves Shorts you haven't reached yet.** It now skips the next 150 Shorts in your feed (you'd scroll through those on YouTube anyway) and saves the 500 after them, so TubeVault doesn't end up with the same Shorts you just watched. Shorts you scroll to on YouTube while it runs are left out too.
- **Save all goes up to 500** (was 400).

**Updating the extension:** TubeVault updates itself. Then in `chrome://extensions`, click **↻ reload** on the TubeVault card and refresh your YouTube tabs.

## What's new in 1.5.6

- **Shorts controls size themselves to the Short.** Buttons and text are bigger in full screen and shrink to fit in a small window, so they no longer overlap or cover the video.

## What's new in 1.5.5

- **Everything on a Short is 1.8× bigger:** play/pause, volume, ⋯, the up/down arrows, and the channel name and title at the bottom.

## What's new in 1.5.4

- **Bigger buttons on Shorts.** Play/pause, volume and ⋯ are larger and easier to hit.

## What's new in 1.5.3

- **Scroll Shorts like YouTube.** A small flick on the trackpad, or one notch of the mouse wheel, moves to the next or previous Short. No more dragging halfway down.
- **Save all skips ads.** Sponsored Shorts in your feed are no longer saved.
- **Volume slider opens from the speaker button**, growing to the right inside its pill instead of sliding in from the edge of the video.

## What's new in 1.5.2

- **Pause Shorts.** Clicking a Short in TubeVault now pauses and plays it (clicks weren't getting through before). Space or **K** works too, and there's a ⏸ button at the top left.
- **Volume slider on Shorts**, like YouTube's: hover the speaker at the top left of a Short and a slider slides out. Click the speaker or press **M** to mute. The volume is remembered.
- The buttons over a Short now have a dark background, so they're visible on bright videos.

## What's new in 1.5.0

- **Save all Shorts from your feed.** A new **Save all** button sits under **Save** on every Short. One click saves the Shorts that come after the one you're on, the same ones your own feed would show you next, up to 400.
  - Nothing needs to play (no sound): it reads the upcoming list from YouTube with your sign-in.
  - It keeps TubeVault topped up a few at a time and keeps going until 400 are saved, you click **Stop**, or you close that YouTube tab.
  - A card in the bottom-left corner shows the count and what's downloading now. **Stop** finishes the ones in progress and drops the rest.
  - Your Mac won't idle-sleep while TubeVault is downloading. It stops on its own if the disk gets low (under 2 GB free).
- **Shorts feed in YouTube's order.** Saved Shorts now scroll oldest-first, in the order YouTube showed them, and the feed reopens on the Short you watched last.
- No notification for every Short during **Save all**.

**Updating the extension:** TubeVault updates itself. Then in `chrome://extensions`, click **↻ reload** on the TubeVault card and refresh your YouTube tabs.

## What's new in 1.4.0

- **Download whole playlists.** On any playlist there's a new ⬇ button next to loop and shuffle (or next to **Save** and **Share** on the playlist page). It opens a picker right on YouTube:
  - Click videos in the order you want them. The number next to each one is the order it downloads in and plays in.
  - **Select All** adds the rest in playlist order; **Clear** starts over.
  - Each video is saved separately, all inside one playlist in TubeVault, so a 100-song playlist doesn't flood **All Videos**.
- **Playlists in the app.** Saved playlists get their own **Playlists** section in the sidebar. Videos are numbered in your order, **Play All** plays them straight through, and the player shows what's next.
- **Download progress on YouTube.** A small card in the bottom-left corner shows how far the playlist has got (for example *3 of 12*). Minimize it to a little progress ring, or close it; the download carries on. When it's done, **Open in TubeVault** takes you straight to the playlist.
- **One notification per playlist**, sent when the whole playlist is saved, instead of one for every video.
- **Shorts button moved.** The Shorts **Save** button now sits above the like button instead of over the volume control. It fills up red from the bottom while the Short downloads and turns into ✓ **Saved**.

**Updating the extension:** TubeVault updates itself. Then in `chrome://extensions`, click **↻ reload** on the TubeVault card and refresh your YouTube tabs. If you didn't load it from **Documents › TubeVault Chrome Extension**, load the new folder from the extension zip.

## What's new in 1.3.1

- **Delete several at once.** Right-click **All Videos** or **Shorts** in the sidebar and choose **Delete Videos…** or **Delete Shorts…** (also in the **Edit** menu). Click the thumbnails you want to remove, or **Select All** (⌘A), then **Delete**.

## What's new in 1.3.0

- **YouTube Shorts.** A ⬇ button now sits at the top right of the Shorts player, next to ⋮. Saved Shorts get their own **Shorts** feed in TubeVault: one Short at a time, looping, scroll or press ↑ ↓ to move between them.
- **Best quality, always.** Videos download at the highest resolution YouTube offers, up to 4K. Previously they were capped at 1080p, and could drop to 360p when YouTube bot-checked the download.
- **Resume in the app.** Close a video in TubeVault and it carries on from the same spot when you open it again.
- **Automatic updates.** TubeVault now checks for new versions, shows a notification and a banner, and installs the update itself when you click **Update Now**. This is the last time you need to download TubeVault by hand.
- Downloads run three at a time, so YouTube doesn't throttle big batches.

**Updating the extension:** in `chrome://extensions`, click **↻ reload** on the TubeVault card. If you loaded it from **Documents › TubeVault Chrome Extension**, TubeVault has already refreshed that folder; otherwise load the new folder from the extension zip.

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
5. Open any YouTube video and click the **⬇** icon in the player's bottom bar. When it's saved, click **Open TubeVault** to watch it, paused at the same spot. On a playlist, use the **⬇** next to loop and shuffle; on a Short, **Save** above the like button.

**Upgrading from 1.1 or earlier:** remove the old TubeVault extension in `chrome://extensions` and load the new folder once. Videos you already downloaded move into TubeVault's own folder automatically.

The app shows these steps on first launch, and you can reopen them from **Help › TubeVault Setup Guide**. The full guide is in the [README](https://github.com/SyedInayatShah/TubeVault#-setup-about-5-minutes).
