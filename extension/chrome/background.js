// Talks to the TubeVault Mac app. First through Chrome native messaging (the app's built-in helper,
// which also launches TubeVault if it's closed), then directly to its local server (127.0.0.1:47823),
// and finally the tubevault:// URL scheme.

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
    // The native host opens TubeVault if needed; "offline" lets the button offer to open it.
    api(`/download?url=${encodeURIComponent(cleanURL(msg.url))}`, true)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "status") {
    api(`/status?v=${encodeURIComponent(msg.v)}`)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "playlist") {
    // Opening the picker counts as a click, so TubeVault is launched if needed.
    api(`/playlist?list=${encodeURIComponent(msg.list)}&v=${encodeURIComponent(msg.v || "")}`, true)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "playlist-download") {
    const q = `list=${encodeURIComponent(msg.list)}&title=${encodeURIComponent(msg.title || "")}&ids=${encodeURIComponent(msg.ids)}`;
    api(`/playlist-download?${q}`, true)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "playlist-status" || msg.type === "playlist-retry") {
    api(`/${msg.type}?list=${encodeURIComponent(msg.list)}`)
      .then(sendResponse)
      .catch(() => sendResponse({ state: "offline" }));
  } else if (msg.type === "position") {
    api(`/position?v=${encodeURIComponent(msg.v)}&t=${encodeURIComponent(msg.t)}`)
      .then(sendResponse)
      .catch(() => sendResponse({}));
  }
  return true; // keep the channel open for async replies
});

const HOST = "com.tubevault.host";

// launch: open TubeVault if it isn't running (only for actions the user clicked).
async function api(path, launch = false) {
  try {
    const reply = await chrome.runtime.sendNativeMessage(HOST, { path, launch });
    if (reply && !reply.error) return reply;
    if (reply?.state === "offline") throw new Error("offline");
  } catch (e) {
    console.warn("TubeVault native messaging:", e?.message || e);
  }
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
    return await api(`/download?url=${encodeURIComponent(url)}`, true);
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
