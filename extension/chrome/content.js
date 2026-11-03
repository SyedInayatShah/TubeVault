// Adds a TubeVault download button (with a live progress bar) to the YouTube player controls,
// and to the like/comment/share column of Shorts.
// Once saved it becomes an "Open TubeVault" button, and pausing the video tells the app
// where you stopped so it opens paused at the same spot.
(() => {
  const NS = "http://www.w3.org/2000/svg";
  const ICONS = {
    download: ["M12 4v10", "M7.5 10 12 14.5 16.5 10", "M5 19h14"],
    done: ["M5 12.5 9.5 17 19 7.5"],
    failed: ["M12 7v6", "M12 17h.01"],
  };
  const ACTIVE = ["starting", "downloading", "finishing"];

  let videoId = null;
  let state = "none";
  let pollTimer = null;
  let ui = null;

  function isShorts() {
    return location.pathname.startsWith("/shorts/");
  }

  function currentVideoId() {
    const u = new URL(location.href);
    if (u.pathname === "/watch") return u.searchParams.get("v");
    if (isShorts()) return u.pathname.split("/")[2] || null;
    return null;
  }

  function videoElement() {
    return document.querySelector(isShorts() ? "#shorts-player video" : "#movie_player video");
  }

  function isAdPlaying() {
    return !!document.querySelector("#movie_player.ad-showing");
  }

  function icon(name) {
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("width", "24");
    svg.setAttribute("height", "24");
    svg.setAttribute("fill", "none");
    for (const d of ICONS[name]) {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", d);
      p.setAttribute("stroke", "#fff");
      p.setAttribute("stroke-width", "2");
      p.setAttribute("stroke-linecap", "round");
      p.setAttribute("stroke-linejoin", "round");
      svg.appendChild(p);
    }
    return svg;
  }

  function build() {
    const wrap = document.createElement("div");
    wrap.className = "tubevault-wrap";

    const pill = document.createElement("div");
    pill.className = "tubevault-pill";
    const track = document.createElement("div");
    track.className = "tubevault-track";
    const fill = document.createElement("div");
    fill.className = "tubevault-fill";
    track.appendChild(fill);
    const label = document.createElement("span");
    label.className = "tubevault-label";
    pill.append(track, label);
    pill.addEventListener("click", onClick);

    const button = document.createElement("button");
    button.className = "ytp-button tubevault-btn";
    button.addEventListener("click", onClick);

    wrap.append(pill, button);
    return { wrap, pill, fill, label, button, iconHost: button };
  }

  // Shorts: a round button with a label under it, like the like/comment/share buttons,
  // that fills up with red as the Short downloads.
  function buildShorts() {
    const wrap = document.createElement("div");
    wrap.className = "tubevault-short";

    const button = document.createElement("button");
    button.className = "tubevault-short-btn";
    button.addEventListener("click", onClick);
    // The red fill carries a white copy of the icon, so the icon turns white wherever the red has reached.
    const iconHost = document.createElement("span");
    iconHost.className = "tubevault-short-icon";
    const fill = document.createElement("div");
    fill.className = "tubevault-short-fill";
    const fillIcon = document.createElement("span");
    fillIcon.className = "tubevault-short-icon";
    fill.appendChild(fillIcon);
    button.append(iconHost, fill);

    const label = document.createElement("span");
    label.className = "tubevault-short-label";
    label.addEventListener("click", onClick);

    wrap.append(button, label);
    return { wrap, pill: button, fill, label, button, iconHost, fillIcon, shorts: true };
  }

  // Take the colours from YouTube's own like button, so it fits light and dark mode alike.
  function matchTheme(bar) {
    const like = bar.querySelector("like-button-view-model button");
    if (!like || !ui?.shorts) return;
    const style = getComputedStyle(like);
    ui.wrap.style.setProperty("--tubevault-bg", style.backgroundColor);
    ui.wrap.style.setProperty("--tubevault-fg", style.color);
  }

  function mount() {
    const shorts = isShorts();
    const host = shorts
      ? document.querySelector("ytd-reel-video-renderer[is-active] reel-action-bar-view-model") ||
        document.querySelector("reel-action-bar-view-model")
      : document.querySelector("#movie_player .ytp-right-controls-left") ||
        document.querySelector("#movie_player .ytp-right-controls");
    if (!host) return;
    if (shorts) matchTheme(host);
    if (ui && ui.wrap.parentNode === host) return;
    ui?.wrap.remove();
    ui = shorts ? buildShorts() : build();
    if (shorts) {
      host.insertBefore(ui.wrap, host.firstChild);
      matchTheme(host);
    } else {
      host.insertBefore(ui.wrap, host.querySelector(".ytp-subtitles-button") || host.firstChild);
    }
    render({ state });
  }

  function render(s) {
    state = s.state;
    if (!ui) return;
    const pct = Math.round((s.progress || 0) * 100);
    const active = ACTIVE.includes(state);
    const message = state === "offline" || state === "failed" || state === "done";

    ui.wrap.classList.toggle("is-active", active || message);
    ui.wrap.classList.toggle("is-starting", state === "starting");
    ui.wrap.classList.toggle("is-message", message);
    ui.wrap.classList.toggle("is-done", state === "done");
    ui.wrap.classList.toggle("is-failed", state === "failed");
    const level = state === "done" || (state === "starting" && !ui.shorts) ? 100 : active ? pct : 0;
    ui.fill.style[ui.shorts ? "height" : "width"] = level + "%";
    ui.label.textContent = ui.shorts ? (
      state === "done" ? "Saved" :
      state === "offline" ? "Open app" :
      state === "failed" ? "Retry" :
      state === "starting" ? "Starting" :
      state === "finishing" ? "Saving" :
      active ? `${pct}%` : "Save"
    ) :
      state === "done" ? "Open TubeVault" :
      state === "offline" ? "Open TubeVault" :
      state === "failed" ? "Failed – retry" :
      state === "starting" ? "Starting…" :
      state === "finishing" ? "Saving…" : `${pct}%`;

    const iconName = state === "done" ? "done" : state === "failed" ? "failed" : "download";
    ui.iconHost.replaceChildren(icon(iconName));
    ui.fillIcon?.replaceChildren(icon(iconName));
    const tip = {
      done: "Saved – open it in TubeVault, paused right here",
      failed: "Download failed – click to retry" + (s.error ? `\n${s.error}` : ""),
      offline: "TubeVault isn’t running – click to open it and download",
      none: "Download with TubeVault",
    }[state] || `Downloading… ${pct}%`;
    ui.button.title = tip;
    ui.pill.title = tip;
    ui.button.setAttribute("aria-label", tip);
  }

  // Apps can only be opened from a click, so these run directly inside the click handler.
  function openScheme(href) {
    window.location.href = href;
  }

  function onClick(e) {
    e.stopPropagation();
    if (!videoId) return;
    const url = isShorts()
      ? `https://www.youtube.com/shorts/${videoId}`
      : `https://www.youtube.com/watch?v=${videoId}`;

    if (state === "done") {
      const video = videoElement();
      const t = video && !isAdPlaying() ? Math.floor(video.currentTime) : 0;
      if (video && !video.paused) video.pause();
      openScheme(`tubevault://open?v=${encodeURIComponent(videoId)}&t=${t}`);
      return;
    }
    if (ACTIVE.includes(state)) return;

    if (state === "offline") {
      render({ state: "starting" });
      openScheme("tubevault://download?url=" + encodeURIComponent(url));
      startPolling();
      return;
    }

    render({ state: "starting" });
    chrome.runtime.sendMessage({ type: "download", url }, (s) => {
      if (chrome.runtime.lastError || !s || s.state === "offline") {
        render({ state: "offline" });
        return;
      }
      startPolling();
      reportPosition();
    });
  }

  // Tell the app where the video is paused, for videos it's downloading or has saved.
  function reportPosition() {
    const video = videoElement();
    if (!videoId || !video || !video.paused || isAdPlaying()) return;
    if (!ACTIVE.includes(state) && state !== "done") return;
    chrome.runtime.sendMessage({ type: "position", v: videoId, t: Math.floor(video.currentTime) });
  }

  function watchVideoElement() {
    const video = videoElement();
    if (!video || video.dataset.tubevault) return;
    video.dataset.tubevault = "1";
    video.addEventListener("pause", reportPosition);
    video.addEventListener("seeked", reportPosition);
  }

  function refreshStatus() {
    const id = videoId;
    if (!id) return;
    chrome.runtime.sendMessage({ type: "status", v: id }, (s) => {
      if (chrome.runtime.lastError || !s || id !== videoId) return;
      // While the app is still launching it reports nothing yet; keep showing "Starting…".
      if (state === "starting" && (s.state === "none" || s.state === "offline")) return;
      render(s);
      if (!ACTIVE.includes(s.state)) stopPolling();
    });
  }

  function startPolling() {
    stopPolling();
    let ticks = 0;
    pollTimer = setInterval(() => {
      refreshStatus();
      // Give up on a launch that never reported back (about 1 minute).
      if (++ticks > 60 && state === "starting") {
        render({ state: "offline" });
        stopPolling();
      }
    }, 1000);
  }

  function stopPolling() {
    clearInterval(pollTimer);
    pollTimer = null;
  }

  // YouTube is a single-page app: keep the button mounted and follow video changes.
  setInterval(() => {
    const id = currentVideoId();
    if (id !== videoId) {
      videoId = id;
      stopPolling();
      render({ state: "none" });
      if (id) {
        chrome.runtime.sendMessage({ type: "status", v: id }, (s) => {
          if (chrome.runtime.lastError || !s || id !== videoId) return;
          render(s.state === "offline" ? { state: "none" } : s);
          if (ACTIVE.includes(s.state)) startPolling();
        });
      }
    }
    if (videoId) {
      mount();
      watchVideoElement();
    }
  }, 1000);
})();
