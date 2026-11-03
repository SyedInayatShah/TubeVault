// Sends YouTube links to the TubeVault Mac app through its tubevault:// URL scheme.

const VIDEO_PATTERNS = [
  "*://*.youtube.com/watch*",
  "*://*.youtube.com/shorts/*",
  "*://*.youtube.com/live/*",
  "*://youtu.be/*",
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    // Right-clicking a video link or thumbnail anywhere.
    chrome.contextMenus.create({
      id: "tubevault-link",
      title: "Download with TubeVault",
      contexts: ["link", "image"],
      targetUrlPatterns: VIDEO_PATTERNS,
    });
    // Right-clicking on a video page itself.
    chrome.contextMenus.create({
      id: "tubevault-page",
      title: "Download this video with TubeVault",
      contexts: ["page", "video", "frame"],
      documentUrlPatterns: VIDEO_PATTERNS,
    });
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const url = info.menuItemId === "tubevault-link" ? info.linkUrl : info.pageUrl || tab?.url;
  if (url) sendToApp(url, tab);
});

chrome.action.onClicked.addListener((tab) => {
  if (tab.url && /youtube\.com\/(watch|shorts|live)|youtu\.be\//.test(tab.url)) {
    sendToApp(tab.url, tab);
  }
});

function cleanURL(raw) {
  try {
    const u = new URL(raw, "https://www.youtube.com");
    // Keep only the video id so playlists/timestamps don't leak into the download.
    const v = u.searchParams.get("v");
    if (v) return `https://www.youtube.com/watch?v=${v}`;
    return u.origin + u.pathname;
  } catch {
    return raw;
  }
}

async function sendToApp(raw, tab) {
  const appURL = "tubevault://download?url=" + encodeURIComponent(cleanURL(raw));
  try {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: (href) => { window.location.href = href; },
      args: [appURL],
    });
  } catch {
    chrome.tabs.update(tab.id, { url: appURL });
  }
}
