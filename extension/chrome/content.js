// Adds a TubeVault download button (with a live progress bar) to the YouTube player controls.
(() => {
  const NS = "http://www.w3.org/2000/svg";
  const ICONS = {
    download: ["M12 4v10", "M7.5 10 12 14.5 16.5 10", "M5 19h14"],
    done: ["M5 12.5 9.5 17 19 7.5"],
    failed: ["M12 7v6", "M12 17h.01"],
  };

  let videoId = null;
  let state = "none";
  let pollTimer = null;
  let ui = null;

  function currentVideoId() {
    const u = new URL(location.href);
    return u.pathname === "/watch" ? u.searchParams.get("v") : null;
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

    const button = document.createElement("button");
    button.className = "ytp-button tubevault-btn";
    button.addEventListener("click", onClick);

    wrap.append(pill, button);
    return { wrap, pill, fill, label, button };
  }

  function mount() {
    if (ui && document.contains(ui.wrap)) return;
    const host =
      document.querySelector("#movie_player .ytp-right-controls-left") ||
      document.querySelector("#movie_player .ytp-right-controls");
    if (!host) return;
    ui = build();
    host.insertBefore(ui.wrap, host.querySelector(".ytp-subtitles-button") || host.firstChild);
    render({ state });
  }

  function render(s) {
    state = s.state;
    if (!ui) return;
    const pct = Math.round((s.progress || 0) * 100);
    const active = ["starting", "downloading", "finishing"].includes(state);

    ui.wrap.classList.toggle("is-active", active || state === "offline" || state === "failed");
    ui.wrap.classList.toggle("is-starting", state === "starting");
    ui.wrap.classList.toggle("is-message", state === "offline" || state === "failed");
    ui.fill.style.width = (state === "starting" ? 100 : pct) + "%";
    ui.label.textContent =
      state === "offline" ? "Open TubeVault" :
      state === "failed" ? "Failed – retry" :
      state === "starting" ? "Starting…" :
      state === "finishing" ? "Saving…" : `${pct}%`;

    const iconName = state === "done" ? "done" : state === "failed" ? "failed" : "download";
    ui.button.replaceChildren(icon(iconName));
    const tip = {
      done: "Saved in TubeVault – click to open",
      failed: "Download failed – click to retry" + (s.error ? `\n${s.error}` : ""),
      offline: "TubeVault isn’t running – click to open it and download",
      none: "Download with TubeVault",
    }[state] || `Downloading… ${pct}%`;
    ui.button.title = tip;
    ui.button.setAttribute("aria-label", tip);
  }

  function onClick(e) {
    e.stopPropagation();
    if (!videoId) return;
    if (state === "done") {
      chrome.runtime.sendMessage({ type: "open" });
      return;
    }
    if (["starting", "downloading", "finishing"].includes(state)) return;
    const url = `https://www.youtube.com/watch?v=${videoId}`;

    if (state === "offline") {
      // Launch the app straight from this click (Chrome only opens apps on a user gesture).
      render({ state: "starting" });
      window.location.href = "tubevault://download?url=" + encodeURIComponent(url);
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
    });
  }

  function refreshStatus() {
    const id = videoId;
    if (!id) return;
    chrome.runtime.sendMessage({ type: "status", v: id }, (s) => {
      if (chrome.runtime.lastError || !s || id !== videoId) return;
      // While the app is still launching it reports nothing yet; keep showing "Starting…".
      if (state === "starting" && (s.state === "none" || s.state === "offline")) return;
      render(s);
      if (!["starting", "downloading", "finishing"].includes(s.state)) stopPolling();
    });
  }

  function startPolling() {
    stopPolling();
    let ticks = 0;
    pollTimer = setInterval(() => {
      refreshStatus();
      // Give up on a launch that never reported back (about 2 minutes).
      if (++ticks > 120 && state === "starting") {
        render({ state: "failed", error: "Couldn’t reach TubeVault. Is it installed?" });
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
          render(s);
          if (["starting", "downloading", "finishing"].includes(s.state)) startPolling();
        });
      }
    }
    if (videoId) mount();
  }, 1000);
})();
