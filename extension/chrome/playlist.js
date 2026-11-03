// Playlists: a download button next to the playlist's loop/shuffle buttons (or its Save/Share buttons on
// the playlist page). It opens a picker where the videos are ticked in the order they should download and
// play in, and a small card in the bottom-left corner follows the download.
(() => {
  const NS = "http://www.w3.org/2000/svg";
  const STORE = "tubevault.playlists";
  const ICONS = {
    playlist: ["M4 6h10", "M4 11h10", "M4 16h6", "M18 8v11", "M14.5 15.5 18 19l3.5-3.5"],
    close: ["M6 6l12 12", "M18 6 6 18"],
    minimize: ["M6 12h12"],
    done: ["M5 12.5 9.5 17 19 7.5"],
  };

  let picker = null;
  const cards = new Map(); // list id -> card
  let dock = null;

  // MARK: Helpers

  function icon(name, size = 24) {
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("width", size);
    svg.setAttribute("height", size);
    svg.setAttribute("fill", "none");
    for (const d of ICONS[name]) {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", d);
      p.setAttribute("stroke", "currentColor");
      p.setAttribute("stroke-width", "2");
      p.setAttribute("stroke-linecap", "round");
      p.setAttribute("stroke-linejoin", "round");
      svg.appendChild(p);
    }
    return svg;
  }

  function el(tag, className, text) {
    const e = document.createElement(tag);
    if (className) e.className = className;
    if (text != null) e.textContent = text;
    return e;
  }

  function send(msg) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(msg, (reply) => {
          resolve(chrome.runtime.lastError ? { state: "offline" } : reply || { state: "offline" });
        });
      } catch {
        resolve({ state: "offline" }); // the extension was reloaded; this page needs a refresh
      }
    });
  }

  function duration(seconds) {
    if (!seconds) return "";
    const s = Math.round(seconds), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    const ss = String(s % 60).padStart(2, "0");
    return h ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
  }

  function currentList() {
    const u = new URL(location.href);
    if (u.pathname !== "/watch" && u.pathname !== "/playlist") return null;
    return u.searchParams.get("list");
  }

  const visible = (e) => e && e.getBoundingClientRect().width > 0;

  // Apps can only be opened from a click, so this runs directly inside click handlers.
  function openApp(href = "tubevault://open") {
    window.location.href = href;
  }

  // MARK: Button

  function mountButton() {
    const list = currentList();
    const panelRow = [...document.querySelectorAll(
      "ytd-playlist-panel-renderer #playlist-action-menu #top-level-buttons-computed"
    )].find(visible);
    const headerRow = [...document.querySelectorAll("yt-flexible-actions-view-model .ytFlexibleActionsViewModelActionRow")]
      .find(visible);
    const host = location.pathname === "/watch" ? panelRow : location.pathname === "/playlist" ? headerRow : null;

    const existing = document.querySelectorAll(".tubevault-pl-btn");
    for (const b of existing) if (!list || b.parentElement !== host) b.remove();
    if (!list || !host || host.querySelector(".tubevault-pl-btn")) return;

    const wrap = el("div", "tubevault-pl-btn " + (host === panelRow ? "is-panel" : "is-header"));
    const button = el("button");
    button.title = "Download this playlist with TubeVault";
    button.setAttribute("aria-label", button.title);
    button.append(icon("playlist"));
    button.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      openPicker(currentList());
    });
    wrap.append(button);

    // Match the neighbouring YouTube buttons in light and dark mode.
    const neighbour = host.querySelector("button");
    if (neighbour) {
      const style = getComputedStyle(neighbour);
      wrap.style.setProperty("--tubevault-fg", style.color);
      if (host === headerRow) wrap.style.setProperty("--tubevault-bg", style.backgroundColor);
    }

    if (host === headerRow) host.insertBefore(wrap, host.lastElementChild);
    else host.append(wrap);
  }

  // MARK: Picker

  // Videos already on the page, for when TubeVault can't read the playlist itself (private playlists, Watch Later).
  function entriesFromPage() {
    const rows = document.querySelectorAll(
      "ytd-playlist-panel-renderer#playlist ytd-playlist-panel-video-renderer, ytd-playlist-video-renderer"
    );
    const seen = new Set();
    const entries = [];
    for (const row of rows) {
      const link = row.querySelector("a[href*='watch?v=']");
      const id = link && new URL(link.href).searchParams.get("v");
      if (!id || seen.has(id)) continue;
      seen.add(id);
      entries.push({
        id,
        title: row.querySelector("#video-title")?.textContent.trim() || "Video",
        channel: row.querySelector("#byline, ytd-channel-name")?.textContent.trim() || "",
      });
    }
    return entries;
  }

  function pageTitle() {
    return (
      document.querySelector("ytd-playlist-panel-renderer#playlist .title")?.textContent.trim() ||
      document.querySelector("yt-page-header-renderer h1, ytd-tabbed-page-header h1")?.textContent.trim() ||
      ""
    );
  }

  function openPicker(list) {
    if (!list) return;
    closePicker();
    const video = new URL(location.href).searchParams.get("v");
    const state = { list, video, title: pageTitle(), entries: [], order: [] };

    const backdrop = el("div", "tubevault-pl-backdrop");
    const dialog = el("div", "tubevault-pl-dialog");
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    backdrop.append(dialog);
    backdrop.addEventListener("click", (e) => { if (e.target === backdrop) closePicker(); });

    // Header
    const header = el("div", "tubevault-pl-header");
    const heading = el("div", "tubevault-pl-heading");
    const h = el("h2", null, "Download playlist");
    const sub = el("div", "tubevault-pl-sub", state.title || "Loading…");
    heading.append(h, sub);
    const close = el("button", "tubevault-pl-icon-btn");
    close.title = "Close";
    close.append(icon("close", 20));
    close.addEventListener("click", closePicker);
    header.append(heading, close);

    const hint = el("div", "tubevault-pl-hint",
      "Click the videos in the order you want them. That’s the order they’ll download in, and play in TubeVault.");

    // Toolbar
    const toolbar = el("div", "tubevault-pl-toolbar");
    const selectAll = el("button", "tubevault-pl-chip", "Select All");
    const clear = el("button", "tubevault-pl-chip", "Clear");
    const count = el("div", "tubevault-pl-count");
    toolbar.append(selectAll, clear, count);

    const listBox = el("div", "tubevault-pl-list");

    // Footer
    const footer = el("div", "tubevault-pl-footer");
    const cancel = el("button", "tubevault-pl-text-btn", "Cancel");
    cancel.addEventListener("click", closePicker);
    const go = el("button", "tubevault-pl-primary", "Download");
    footer.append(cancel, go);

    dialog.append(header, hint, toolbar, listBox, footer);
    document.body.append(backdrop);

    const rows = new Map();

    function refresh() {
      for (const [id, row] of rows) {
        const n = state.order.indexOf(id);
        row.classList.toggle("is-selected", n >= 0);
        row.querySelector(".tubevault-pl-num").textContent = n >= 0 ? n + 1 : "";
      }
      const picked = state.entries.filter((e) => state.order.includes(e.id));
      const total = picked.reduce((t, e) => t + (e.duration || 0), 0);
      count.textContent = state.entries.length
        ? `${state.order.length} of ${state.entries.length} selected` + (total ? ` · ${duration(total)}` : "")
        : "";
      const all = state.entries.length > 0 && state.order.length === state.entries.length;
      selectAll.disabled = all || !state.entries.length;
      clear.disabled = !state.order.length;
      go.disabled = !state.order.length;
      go.textContent = state.order.length
        ? `Download ${state.order.length} video${state.order.length === 1 ? "" : "s"}`
        : "Download";
    }

    function toggle(id) {
      const i = state.order.indexOf(id);
      if (i >= 0) state.order.splice(i, 1);
      else state.order.push(id);
      refresh();
    }

    function showEntries(entries, title) {
      state.entries = entries;
      if (title) state.title = title;
      sub.textContent = `${state.title || "Playlist"} · ${entries.length} video${entries.length === 1 ? "" : "s"}`;
      listBox.replaceChildren();
      rows.clear();
      for (const entry of entries) {
        const row = el("button", "tubevault-pl-row");
        const num = el("span", "tubevault-pl-num");
        const thumb = el("span", "tubevault-pl-thumb");
        const img = el("img");
        img.loading = "lazy";
        img.alt = "";
        img.src = `https://i.ytimg.com/vi/${entry.id}/mqdefault.jpg`;
        thumb.append(img);
        if (entry.duration) thumb.append(el("span", "tubevault-pl-dur", duration(entry.duration)));
        const text = el("span", "tubevault-pl-text");
        text.append(el("span", "tubevault-pl-title", entry.title));
        const meta = el("span", "tubevault-pl-meta", entry.channel);
        if (entry.saved) meta.append(el("span", "tubevault-pl-saved", "In TubeVault"));
        text.append(meta);
        row.append(num, thumb, text);
        row.addEventListener("click", () => toggle(entry.id));
        rows.set(entry.id, row);
        listBox.append(row);
      }
      refresh();
    }

    function showMessage(message, action) {
      listBox.replaceChildren();
      const box = el("div", "tubevault-pl-message");
      box.append(el("div", null, message));
      if (action) {
        const b = el("button", "tubevault-pl-chip", action.label);
        b.addEventListener("click", action.run);
        box.append(b);
      }
      listBox.append(box);
      refresh();
    }

    async function load() {
      const box = el("div", "tubevault-pl-message");
      box.append(el("div", "tubevault-pl-spinner"), el("div", null, "Getting the playlist from TubeVault…"));
      listBox.replaceChildren(box);
      for (let i = 0; i < 90 && picker === backdrop; i++) {
        const r = await send({ type: "playlist", list, v: video });
        if (picker !== backdrop) return;
        if (r.state === "ready") return showEntries(r.entries, r.title);
        if (r.state === "failed" || r.state === "offline") {
          const fromPage = entriesFromPage();
          if (fromPage.length) return showEntries(fromPage);
          return r.state === "offline"
            ? showMessage("TubeVault isn’t running.", { label: "Open TubeVault", run: () => { openApp(); setTimeout(load, 2500); } })
            : showMessage(`Couldn’t get this playlist. ${r.error || ""}`.trim(), { label: "Try Again", run: load });
        }
        await new Promise((r) => setTimeout(r, 1000));
      }
    }

    selectAll.addEventListener("click", () => {
      for (const e of state.entries) if (!state.order.includes(e.id)) state.order.push(e.id);
      refresh();
    });
    clear.addEventListener("click", () => { state.order = []; refresh(); });
    go.addEventListener("click", async () => {
      if (!state.order.length) return;
      go.disabled = true;
      go.textContent = "Starting…";
      const r = await send({ type: "playlist-download", list, title: state.title, ids: state.order.join(",") });
      if (r.state === "offline") {
        go.disabled = false;
        refresh();
        return showMessage("TubeVault isn’t running.", { label: "Open TubeVault", run: () => openApp() });
      }
      closePicker();
      track(list, r.title || state.title);
    });

    picker = backdrop;
    document.addEventListener("keydown", onPickerKey, true);
    refresh();
    load();
  }

  // Keep YouTube's shortcuts (space, k, f…) from firing behind the picker.
  function onPickerKey(e) {
    if (!picker) return;
    if (e.key === "Escape") closePicker();
    e.stopPropagation();
  }

  function closePicker() {
    picker?.remove();
    picker = null;
    document.removeEventListener("keydown", onPickerKey, true);
  }

  // MARK: Progress card

  function saved() {
    try { return JSON.parse(localStorage.getItem(STORE)) || []; } catch { return []; }
  }

  function remember(jobs) {
    try { localStorage.setItem(STORE, JSON.stringify(jobs)); } catch {}
  }

  function track(list, title) {
    const jobs = saved().filter((j) => j.list !== list);
    jobs.push({ list, title, minimized: false });
    remember(jobs);
    showCard(list, title);
  }

  function forget(list) {
    remember(saved().filter((j) => j.list !== list));
    const card = cards.get(list);
    clearInterval(card?.timer);
    card?.root.remove();
    cards.delete(list);
  }

  function setMinimized(list, minimized) {
    remember(saved().map((j) => (j.list === list ? { ...j, minimized } : j)));
    cards.get(list)?.root.classList.toggle("is-minimized", minimized);
  }

  function showCard(list, title, minimized = false) {
    if (cards.has(list)) return;
    if (!dock) {
      dock = el("div", "tubevault-pl-dock");
      document.body.append(dock);
    }
    const root = el("div", "tubevault-pl-card" + (minimized ? " is-minimized" : ""));

    // Minimized: a small ring that fills as it downloads.
    const ring = el("button", "tubevault-pl-ring");
    ring.title = "Show download";
    ring.append(icon("playlist", 20));
    ring.addEventListener("click", () => setMinimized(list, false));

    const body = el("div", "tubevault-pl-card-body");
    const top = el("div", "tubevault-pl-card-top");
    const label = el("div", "tubevault-pl-card-label", "Saving to TubeVault");
    const counter = el("div", "tubevault-pl-card-count");
    const min = el("button", "tubevault-pl-icon-btn small");
    min.title = "Minimize";
    min.append(icon("minimize", 16));
    min.addEventListener("click", () => setMinimized(list, true));
    const close = el("button", "tubevault-pl-icon-btn small");
    close.title = "Hide (the download carries on in TubeVault)";
    close.append(icon("close", 16));
    close.addEventListener("click", () => forget(list));
    top.append(label, counter, min, close);

    const name = el("div", "tubevault-pl-card-title", title || "Playlist");
    const now = el("div", "tubevault-pl-card-now");
    const bar = el("div", "tubevault-pl-card-bar");
    const fill = el("div", "tubevault-pl-card-fill");
    bar.append(fill);
    const actions = el("div", "tubevault-pl-card-actions");
    body.append(top, name, now, bar, actions);
    root.append(ring, body);
    dock.append(root);

    const card = { root, timer: null };
    cards.set(list, card);

    function action(text, run, primary) {
      const b = el("button", primary ? "tubevault-pl-primary small" : "tubevault-pl-chip small", text);
      b.addEventListener("click", run);
      return b;
    }

    async function poll() {
      const s = await send({ type: "playlist-status", list });
      if (!cards.has(list)) return;
      if (s.state === "offline") {
        now.textContent = "TubeVault isn’t running";
        actions.replaceChildren(action("Open TubeVault", () => openApp()));
        return;
      }
      if (s.state === "none") return forget(list);
      // A video downloads as picture then sound, so the raw figure can dip; the bar only moves forward.
      const pct = Math.max(card.pct || 0, Math.round((s.progress || 0) * 100));
      card.pct = pct;
      root.style.setProperty("--tubevault-progress", pct + "%");
      fill.style.width = pct + "%";
      name.textContent = s.title || title;
      counter.textContent = `${s.saved} of ${s.total}`;
      root.classList.toggle("is-done", s.state === "done");
      root.classList.toggle("is-failed", s.state === "failed");
      ring.title = `${s.title}: ${s.saved} of ${s.total} saved`;

      if (s.state === "done") {
        label.textContent = "Saved to TubeVault";
        now.textContent = `All ${s.total} video${s.total === 1 ? "" : "s"} are ready to watch offline.`;
        actions.replaceChildren(action("Open in TubeVault", () => openApp(`tubevault://open?list=${encodeURIComponent(list)}`), true));
        ring.replaceChildren(icon("done", 20));
        clearInterval(card.timer);
        // Finished: stays until closed, but doesn't come back after a reload.
        remember(saved().filter((j) => j.list !== list));
      } else if (s.state === "failed") {
        label.textContent = "Saving to TubeVault";
        now.textContent = `${s.failed} video${s.failed === 1 ? "" : "s"} couldn’t download.`;
        actions.replaceChildren(
          action("Retry", async () => { await send({ type: "playlist-retry", list }); poll(); }, true),
          action("Open in TubeVault", () => openApp(`tubevault://open?list=${encodeURIComponent(list)}`))
        );
      } else {
        label.textContent = "Saving to TubeVault";
        now.textContent = s.current ? `Now: ${s.current}` : "Starting…";
        actions.replaceChildren();
      }
    }

    poll();
    card.timer = setInterval(poll, 1500);
  }

  // MARK: Start

  for (const job of saved()) showCard(job.list, job.title, job.minimized);
  setInterval(mountButton, 1000);
  mountButton();
})();
