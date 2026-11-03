// Talks to the TubeVault Mac app: first through its local server (127.0.0.1:47823),
// falling back to the tubevault:// URL scheme to launch the app when it isn't running.

const API = "http://127.0.0.1:47823";

const VIDEO_PATTERNS = [
  "*://*.youtube.com/watch*",
  "*://*.youtube.com/shorts/*",
  "*://*.youtube.com/live/*",
  "*://youtu.be/*",
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "tubevault-link",
      title: "Download with TubeVault",
      contexts: ["link", "image"],
      targetUrlPatterns: VIDEO_PATTERNS,
    });
    chrome.contextMenus.create({
      id: "tubevault-page",
      title: "Download this video with TubeVault",
      contexts: ["page", "frame"],
      documentUrlPatterns: VIDEO_PATTERNS,
    });
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const url = info.menuItemId === "tubevault-link" ? info.linkUrl : info.pageUrl || tab?.url;
  if (url) startDownload(url, tab?.id);
});

chrome.action.onClicked.addListener((tab) => {
  if (tab.url && /youtube\.com\/(watch|shorts|live)|youtu\.be\//.test(tab.url)) {
    startDownload(tab.url, tab.id);
  }
});

// Messages from the in-player button (content.js).
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const tabId = sender.tab?.id;
  if (msg.type === "download") {
    // The in-player button launches the app itself (it has the click), so no fallback here.
    api(`/download?url=${encodeURIComponent(cleanURL(msg.url))}`)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "status") {
    api(`/status?v=${encodeURIComponent(msg.v)}`)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "open") {
    openScheme("tubevault://open", tabId);
    sendResponse({});
  }
  return true; // keep the channel open for async replies
});

async function api(path) {
  const res = await fetch(API + path, { headers: { "X-TubeVault": "1" } });
  return res.json();
}

function cleanURL(raw) {
  try {
    const u = new URL(raw, "https://www.youtube.com");
    const v = u.searchParams.get("v");
    if (v) return `https://www.youtube.com/watch?v=${v}`;
    return u.origin + u.pathname;
  } catch {
    return raw;
  }
}

async function startDownload(raw, tabId) {
  const url = cleanURL(raw);
  try {
    return await api(`/download?url=${encodeURIComponent(url)}`);
  } catch {
    // App isn't running: launch it with the link; it starts the download on launch.
    await openScheme("tubevault://download?url=" + encodeURIComponent(url), tabId);
    return { state: "starting" };
  }
}

async function openScheme(href, tabId) {
  if (tabId == null) return;
  try {
    await chrome.scripting.executeScript({
      target: { tabId },
      func: (h) => { window.location.href = h; },
      args: [href],
    });
  } catch {
    chrome.tabs.update(tabId, { url: href });
  }
}
