// "Save all" on YouTube Shorts: saves Shorts from your own feed (it asks YouTube for them with your
// sign-in, so nothing has to play), skipping the next 150 you'd scroll through on YouTube anyway.
// It keeps TubeVault topped up a few at a time, up to 500, until it's stopped or this tab is closed.
(() => {
  const NS = "http://www.w3.org/2000/svg";
  const LIMIT = 500;
  const SKIP = 150; // upcoming Shorts left for YouTube, since you'd watch those there anyway
  const AHEAD = 20; // Shorts queued in TubeVault at a time
  const ICONS = {
    all: ["M8 3.5h8", "M12 7.5v9", "M8.5 13 12 16.5l3.5-3.5", "M5 20.5h14"],
    stop: ["M8 8h8v8H8z"],
    done: ["M5 12.5 9.5 17 19 7.5"],
    close: ["M6 6l12 12", "M18 6 6 18"],
    minimize: ["M6 12h12"],
  };

  let job = null;
  let ui = null;

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
        resolve({ state: "offline" });
      }
    });
  }

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function currentShort() {
    return location.pathname.startsWith("/shorts/") ? location.pathname.split("/")[2] || null : null;
  }

  // MARK: Reading the feed from YouTube

  function cookie(name) {
    return document.cookie.split("; ").find((c) => c.startsWith(name + "="))?.slice(name.length + 1);
  }

  async function sha1(text) {
    const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text));
    return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  }

  // Signs the request the way youtube.com does, so the feed is your own rather than a signed-out one.
  async function authHeaders() {
    const sapisid = cookie("SAPISID") || cookie("__Secure-3PAPISID");
    if (!sapisid) return {};
    const ts = Math.floor(Date.now() / 1000);
    const hash = await sha1(`${ts} ${sapisid} ${location.origin}`);
    return { Authorization: `SAPISIDHASH ${ts}_${hash}`, "X-Origin": location.origin, "X-Goog-AuthUser": "0" };
  }

  // The current Short's page carries the starting point of its feed and the client details.
  async function startFeed(id) {
    const html = await (await fetch(`${location.origin}/shorts/${id}`, { credentials: "include" })).text();
    const pick = (re) => html.match(re)?.[1];
    const token = pick(/"sequenceParams":"([^"]+)"/);
    if (!token) throw new Error("YouTube didn’t give a feed for this Short.");
    return {
      token,
      client: {
        clientName: "WEB",
        clientVersion: pick(/"INNERTUBE_CLIENT_VERSION":"([^"]+)"/) || "2.20260101.00.00",
        hl: pick(/"HL":"([^"]+)"/) || "en",
        gl: pick(/"GL":"([^"]+)"/) || "US",
        visitorData: pick(/"VISITOR_DATA":"([^"]+)"/),
      },
    };
  }

  // Each visit to /shorts starts from a fresh Short picked for you, so every one leads to a different
  // run of recommendations instead of the Shorts already lined up after the one you're on.
  async function seedFeed() {
    const html = await (await fetch(`${location.origin}/shorts`, { credentials: "include" })).text();
    const seed = html.match(/"reelWatchEndpoint":\{"videoId":"([^"]+)"/)?.[1];
    if (!seed) throw new Error("YouTube didn’t recommend any Shorts.");
    const feed = await startFeed(seed);
    return Object.assign(feed, { seed, pages: 0, fresh: 0 });
  }

  async function nextPage(feed) {
    const res = await fetch(`${location.origin}/youtubei/v1/reel/reel_watch_sequence?prettyPrint=false`, {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/json",
        "X-Youtube-Client-Name": "1",
        "X-Youtube-Client-Version": feed.client.clientVersion,
        ...(await authHeaders()),
      },
      body: JSON.stringify({ context: { client: feed.client }, sequenceParams: feed.token }),
    });
    if (!res.ok) throw new Error(`YouTube answered ${res.status}`);
    const json = await res.json();
    feed.token = json.continuationEndpoint?.continuationCommand?.token || null;
    // Sponsored Shorts (ads) are marked isAd; leave them out.
    return (json.entries || [])
      .map((e) => e.command?.reelWatchEndpoint)
      .filter((ep) => ep?.videoId && !ep.adClientParams?.isAd)
      .map((ep) => ep.videoId);
  }

  // MARK: The job

  async function start() {
    const first = currentShort();
    if (!first || job?.running) return;
    job = { running: true, stopping: false, ids: [], buffer: [], seen: new Set(), excluded: new Set([first]),
            skipped: 0, saved: 0, pending: 0, failed: 0, current: "", feed: null, dryRuns: 0, error: "",
            startedAt: Date.now() };
    render();
    // The next SKIP Shorts are the ones you're about to scroll through on YouTube anyway, so they're
    // left out; saving starts after them, with Shorts of the same kind you haven't reached yet.
    try {
      job.feed = Object.assign(await startFeed(first), { fresh: 0 });
      while (job.skipped < SKIP && job.feed.token && job.running) {
        for (const id of await nextPage(job.feed)) {
          if (job.excluded.has(id)) continue;
          if (job.skipped < SKIP) { job.excluded.add(id); job.skipped++; } else take(id);
        }
        render();
      }
    } catch (e) {
      return finish(e.message);
    }
    if (job.running) loop();
  }

  function take(id) {
    if (job.excluded.has(id) || job.seen.has(id)) return;
    job.seen.add(id);
    job.buffer.push(id);
    job.feed.fresh++;
  }

  // When this feed runs out, carry on from a fresh starting point YouTube picks for you.
  async function nextSeed() {
    job.dryRuns = job.feed.fresh ? 0 : job.dryRuns + 1;
    job.feed = await seedFeed();
    take(job.feed.seed);
  }

  async function loop() {
    while (job?.running) {
      await tick();
      await sleep(2000);
    }
  }

  async function tick() {
    // Anything you scroll to on YouTube while this runs isn't needed in TubeVault too.
    const here = currentShort();
    if (here) job.excluded.add(here);
    job.buffer = job.buffer.filter((id) => !job.excluded.has(id));

    // Top up the buffer from the feed, a page at a time.
    const room = job.stopping ? 0 : Math.min(AHEAD - job.pending, LIMIT - job.ids.length);
    for (let pages = 0; job.buffer.length < room && job.dryRuns < 5 && pages < 3; pages++) {
      try {
        if (!job.feed.token) await nextSeed();
        else for (const id of await nextPage(job.feed)) take(id);
      } catch (e) {
        job.error = e.message;
        break;
      }
    }
    const add = room > 0 ? job.buffer.splice(0, room) : [];
    job.ids.push(...add);

    const r = await send({ type: "shorts-batch", add: add.join(","), ids: job.ids.join(",") });
    if (!job) return;
    if (r.state === "offline") {
      job.buffer.unshift(...add);
      job.ids.splice(job.ids.length - add.length, add.length);
      job.current = "Waiting for TubeVault…";
      return render();
    }
    Object.assign(job, { saved: r.saved, pending: r.pending, failed: r.failed, current: r.current || "" });

    const fedAll = job.ids.length >= LIMIT || (job.dryRuns >= 5 && !job.buffer.length);
    if (r.full) return finish("Your Mac is almost out of space.");
    if ((fedAll || job.stopping) && job.pending === 0) return finish();
    render();
  }

  async function stop() {
    if (!job?.running) return;
    job.stopping = true;
    render();
    // Drop the queued ones that haven't started; the ones downloading now finish.
    const r = await send({ type: "shorts-batch", cancel: job.ids.join(","), ids: job.ids.join(",") });
    const dropped = new Set(r.cancelled || []);
    job.ids = job.ids.filter((id) => !dropped.has(id));
  }

  function finish(error) {
    job.running = false;
    if (error) job.error = error;
    render();
  }

  // MARK: Button above the like button (under TubeVault's own Save)

  function mountButton() {
    const bar = document.querySelector("ytd-reel-video-renderer[is-active] reel-action-bar-view-model") ||
      document.querySelector("reel-action-bar-view-model");
    const save = bar?.querySelector(":scope > .tubevault-short");
    document.querySelectorAll(".tubevault-short.is-all").forEach((b) => {
      if (b.parentElement !== bar) b.remove();
    });
    if (!bar || !save || bar.querySelector(".tubevault-short.is-all")) return;

    const wrap = el("div", "tubevault-short is-all");
    const button = el("button", "tubevault-short-btn");
    const iconHost = el("span", "tubevault-short-icon");
    const fill = el("div", "tubevault-short-fill");
    const fillIcon = el("span", "tubevault-short-icon");
    fill.append(fillIcon);
    button.append(iconHost, fill);
    const label = el("span", "tubevault-short-label");
    wrap.append(button, label);
    for (const target of [button, label]) {
      target.addEventListener("click", (e) => {
        e.stopPropagation();
        job?.running ? stop() : start();
      });
    }
    // Same colours as YouTube's like button.
    const like = bar.querySelector("like-button-view-model button");
    if (like) {
      const style = getComputedStyle(like);
      wrap.style.setProperty("--tubevault-bg", style.backgroundColor);
      wrap.style.setProperty("--tubevault-fg", style.color);
    }
    save.after(wrap);
    ui = { ...ui, wrap, fill, label, iconHost, fillIcon, button };
    render();
  }

  // MARK: Progress card in the bottom-left corner

  function card() {
    if (ui?.card?.isConnected) return ui.card;
    let dock = document.querySelector(".tubevault-pl-dock");
    if (!dock) {
      dock = el("div", "tubevault-pl-dock");
      document.body.append(dock);
    }
    const root = el("div", "tubevault-pl-card");
    const ring = el("button", "tubevault-pl-ring");
    ring.title = "Show";
    ring.append(icon("all", 20));
    ring.addEventListener("click", () => root.classList.remove("is-minimized"));

    const body = el("div", "tubevault-pl-card-body");
    const top = el("div", "tubevault-pl-card-top");
    const label = el("div", "tubevault-pl-card-label");
    const count = el("div", "tubevault-pl-card-count");
    const min = el("button", "tubevault-pl-icon-btn small");
    min.title = "Minimize";
    min.append(icon("minimize", 16));
    min.addEventListener("click", () => root.classList.add("is-minimized"));
    const close = el("button", "tubevault-pl-icon-btn small");
    close.title = "Hide (saving carries on while this tab is open)";
    close.append(icon("close", 16));
    close.addEventListener("click", () => {
      root.remove();
      if (!job?.running) job = null;
    });
    top.append(label, count, min, close);
    const title = el("div", "tubevault-pl-card-title");
    const now = el("div", "tubevault-pl-card-now");
    const bar = el("div", "tubevault-pl-card-bar");
    const fill = el("div", "tubevault-pl-card-fill");
    bar.append(fill);
    const actions = el("div", "tubevault-pl-card-actions");
    body.append(top, title, now, bar, actions);
    root.append(ring, body);
    dock.append(root);
    ui = { ...ui, card: root, cardParts: { label, count, title, now, fill, actions, ring } };
    return root;
  }

  function action(text, run, primary) {
    const b = el("button", primary ? "tubevault-pl-primary small" : "tubevault-pl-chip small", text);
    b.addEventListener("click", run);
    return b;
  }

  function render() {
    // Button
    if (ui?.wrap) {
      const running = job?.running;
      const pct = job ? Math.round((job.saved / LIMIT) * 100) : 0;
      ui.wrap.classList.toggle("is-active", !!running);
      ui.wrap.classList.toggle("is-done", !!job && !running && job.saved > 0);
      ui.fill.style.height = (job && !running && job.saved > 0 ? 100 : running ? Math.max(pct, 4) : 0) + "%";
      ui.label.textContent = running ? (job.stopping ? "Stopping" : `${job.saved} saved`) : job?.saved ? "All saved" : "Save all";
      const name = running ? "stop" : job?.saved ? "done" : "all";
      ui.iconHost.replaceChildren(icon(name));
      ui.fillIcon.replaceChildren(icon(name));
      ui.button.title = running
        ? `Saving Shorts from your feed: ${job.saved} saved. Click to stop.`
        : `Save ${LIMIT} Shorts from your feed to TubeVault, after the next ${SKIP} you’d see here`;
    }
    if (!job) return;

    // Card
    const root = card();
    const p = ui.cardParts;
    const sent = job.ids.length;
    p.count.textContent = `${job.saved} of ${LIMIT}`;
    p.title.textContent = "Shorts from your feed";
    p.fill.style.width = Math.round((job.saved / LIMIT) * 100) + "%";
    root.style.setProperty("--tubevault-progress", Math.round((job.saved / LIMIT) * 100) + "%");
    root.classList.toggle("is-done", !job.running);
    const open = () => {
      const first = job.ids.find(Boolean);
      window.location.href = first ? `tubevault://open?v=${encodeURIComponent(first)}` : "tubevault://open";
    };

    if (job.running) {
      p.label.textContent = job.stopping ? "Stopping…" : "Saving to TubeVault";
      p.now.textContent = job.stopping
        ? "Finishing the ones already downloading"
        : job.current ? `Now: ${job.current}` : sent ? "Starting…" : job.skipped < SKIP ? `Skipping ahead… ${job.skipped}/${SKIP}` : "Reading your feed…";
      p.actions.replaceChildren(...(job.stopping ? [] : [action("Stop", stop)]));
    } else {
      p.label.textContent = "Saved to TubeVault";
      const failed = job.failed ? ` · ${job.failed} couldn’t download` : "";
      p.now.textContent = job.error
        ? `${job.saved} saved. Stopped: ${job.error}`
        : `${job.saved} Short${job.saved === 1 ? "" : "s"} ready to watch offline${failed}`;
      p.actions.replaceChildren(...(job.saved ? [action("Watch in TubeVault", open, true)] : []));
    }
  }

  // Stopping is only for a click; leaving the page (closing the tab) simply ends it.
  setInterval(() => { if (currentShort()) mountButton(); }, 1000);
})();
