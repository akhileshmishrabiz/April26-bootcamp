(function () {
  const COLORS = [
    "#5b21b6", "#ec4899", "#f97316", "#34d399", "#38bdf8",
    "#fde047", "#ef4444", "#8b5cf6", "#14b8a6", "#f59e0b",
    "#6366f1", "#84cc16",
  ];

  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  class SpeakWheelUI {
    constructor(canvas, options) {
      this.canvas = canvas;
      this.ctx = canvas.getContext("2d");
      this.names = options.names || [];
      this.rotation = 0;
      this.spinning = false;
      this.onSpinStart = options.onSpinStart || (() => {});
      this.size = options.size || 420;
      this.resize();
      window.addEventListener("resize", () => this.resize());
    }

    resize() {
      const parent = this.canvas.parentElement;
      const max = Math.min(parent.clientWidth - 24, 480);
      this.size = Math.max(280, max);
      const dpr = window.devicePixelRatio || 1;
      this.canvas.width = this.size * dpr;
      this.canvas.height = this.size * dpr;
      this.canvas.style.width = this.size + "px";
      this.canvas.style.height = this.size + "px";
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.draw();
    }

    setNames(names) {
      this.names = names;
      this.draw();
    }

    draw(rotation) {
      const rot = rotation !== undefined ? rotation : this.rotation;
      const ctx = this.ctx;
      const n = this.names.length;
      const cx = this.size / 2;
      const cy = this.size / 2;
      const radius = this.size / 2 - 8;

      ctx.clearRect(0, 0, this.size, this.size);

      if (n === 0) {
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.fillStyle = "#ede9fe";
        ctx.fill();
        ctx.strokeStyle = "#5b21b6";
        ctx.lineWidth = 4;
        ctx.stroke();
        ctx.fillStyle = "#6366f1";
        ctx.font = "bold 18px Comic Sans MS, cursive, sans-serif";
        ctx.textAlign = "center";
        ctx.fillText("Add names to spin", cx, cy);
        return;
      }

      const slice = (Math.PI * 2) / n;

      for (let i = 0; i < n; i++) {
        const start = rot + i * slice;
        const end = start + slice;
        const color = COLORS[this.names[i].color_index % COLORS.length];

        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.arc(cx, cy, radius, start, end);
        ctx.closePath();
        ctx.fillStyle = color;
        ctx.fill();
        ctx.strokeStyle = "rgba(255,255,255,0.85)";
        ctx.lineWidth = 2;
        ctx.stroke();

        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(start + slice / 2);
        ctx.textAlign = "right";
        ctx.fillStyle = "#fff";
        ctx.font = `bold ${n > 12 ? 11 : n > 8 ? 13 : 15}px Comic Sans MS, cursive, sans-serif`;
        ctx.shadowColor = "rgba(0,0,0,0.35)";
        ctx.shadowBlur = 3;
        const label = this.names[i].name;
        const maxLen = n > 10 ? 10 : 14;
        ctx.fillText(label.length > maxLen ? label.slice(0, maxLen - 1) + "…" : label, radius - 14, 5);
        ctx.restore();
      }

      // center hub
      ctx.beginPath();
      ctx.arc(cx, cy, 28, 0, Math.PI * 2);
      ctx.fillStyle = "#fff";
      ctx.fill();
      ctx.strokeStyle = "#5b21b6";
      ctx.lineWidth = 4;
      ctx.stroke();

      // pointer at top
      ctx.beginPath();
      ctx.moveTo(cx, 4);
      ctx.lineTo(cx - 14, 36);
      ctx.lineTo(cx + 14, 36);
      ctx.closePath();
      ctx.fillStyle = "#ef4444";
      ctx.fill();
      ctx.strokeStyle = "#991b1b";
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    spinToSegment(segmentIndex, segmentCount, duration, onComplete) {
      if (this.spinning || segmentCount === 0) return;
      this.spinning = true;
      this.onSpinStart();

      const slice = (Math.PI * 2) / segmentCount;
      // pointer is at top (-PI/2); land winner segment center under pointer
      const target =
        Math.PI * 1.5 - (segmentIndex + 0.5) * slice;
      const extra = Math.PI * 2 * (4 + Math.random() * 3);
      const startRot = this.rotation;
      let delta = target - (startRot % (Math.PI * 2));
      while (delta < 0) delta += Math.PI * 2;
      const finalRot = startRot + extra + delta;
      const start = performance.now();

      const tick = (now) => {
        const t = Math.min(1, (now - start) / duration);
        const eased = easeOutCubic(t);
        this.rotation = startRot + (finalRot - startRot) * eased;
        this.draw(this.rotation);
        if (t < 1) {
          requestAnimationFrame(tick);
        } else {
          this.rotation = finalRot;
          this.spinning = false;
          if (onComplete) onComplete();
        }
      };
      requestAnimationFrame(tick);
    }
  }

  function confettiBurst(container) {
    const colors = COLORS;
    for (let i = 0; i < 48; i++) {
      const el = document.createElement("span");
      el.className = "wheel-confetti";
      el.style.background = colors[i % colors.length];
      el.style.left = 40 + Math.random() * 20 + "%";
      el.style.animationDelay = Math.random() * 0.3 + "s";
      el.style.transform = `rotate(${Math.random() * 360}deg)`;
      container.appendChild(el);
      setTimeout(() => el.remove(), 2200);
    }
  }

  async function postJson(url, body) {
    const opts = {
      method: "POST",
      headers: {
        "X-Requested-With": "XMLHttpRequest",
        Accept: "application/json",
      },
      credentials: "same-origin",
    };
    if (body instanceof FormData) {
      opts.body = body;
    } else if (body) {
      opts.headers["Content-Type"] = "application/x-www-form-urlencoded";
      opts.body = new URLSearchParams(body);
    }
    const res = await fetch(url, opts);
    const data = await res.json().catch(() => ({}));
    if (!res.ok || !data.ok) throw new Error(data.error || "Request failed");
    return data;
  }

  function renderNameLists(state, root) {
    const waitingEl = root.querySelector("[data-waiting-list]");
    const spokenEl = root.querySelector("[data-spoken-list]");
    const progressEl = root.querySelector("[data-progress-text]");
    const progressBar = root.querySelector("[data-progress-bar]");
    const picksEl = root.querySelector("[data-picks-list]");

    if (progressEl) {
      progressEl.textContent = `${state.spoken_count} / ${state.total} spoken`;
    }
    if (progressBar && state.total) {
      progressBar.style.width = `${Math.round((state.spoken_count / state.total) * 100)}%`;
    }

    if (waitingEl) {
      const items = state.mode === "elimination"
        ? state.active
        : state.waiting.filter((n) => n.status !== "spoken");
      waitingEl.innerHTML = items.length
        ? items.map((n) => `<li><span class="wheel-name-chip">${escapeHtml(n.name)}</span></li>`).join("")
        : '<li class="empty-state">Everyone has spoken!</li>';
    }

    if (spokenEl) {
      spokenEl.innerHTML = state.spoken.length
        ? state.spoken.map((n) => `<li>✅ ${escapeHtml(n.name)}${n.pick_count > 1 ? ` (${n.pick_count}×)` : ""}</li>`).join("")
        : '<li class="empty-state">No one picked yet</li>';
    }

    if (picksEl) {
      picksEl.innerHTML = state.recent_picks.length
        ? state.recent_picks.map((p) => `<li><strong>${escapeHtml(p.name)}</strong> <span class="comment-time">${p.picked_at}</span></li>`).join("")
        : '<li class="empty-state">Spin to begin</li>';
    }
  }

  function escapeHtml(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function showWinner(overlay, name) {
    overlay.querySelector("[data-winner-name]").textContent = name;
    overlay.classList.add("open");
    confettiBurst(overlay);
    setTimeout(() => overlay.classList.remove("open"), 4500);
  }

  function initBoard(root) {
    const canvas = root.querySelector("#speak-wheel-canvas");
    if (!canvas) return;

    const wheelId = root.dataset.wheelId;
    const spinUrl = root.dataset.spinUrl;
    const canFacilitate = root.dataset.canFacilitate === "true";
    const overlay = root.querySelector("#wheel-winner-overlay");
    const spinBtn = root.querySelector("#wheel-spin-btn");
    let state = JSON.parse(root.dataset.initialState || "{}");

    const ui = new SpeakWheelUI(canvas, {
      names: state.active || [],
      onSpinStart: () => {
        if (spinBtn) spinBtn.disabled = true;
      },
    });

    function applyState(newState) {
      state = newState;
      ui.setNames(newState.active || []);
      renderNameLists(newState, root);
      if (spinBtn) {
        spinBtn.disabled = !canFacilitate || !newState.can_spin;
        spinBtn.textContent = newState.can_spin ? "🎡 SPIN!" : "All done 🎉";
      }
    }

    applyState(state);

    if (spinBtn && canFacilitate) {
      spinBtn.addEventListener("click", async () => {
        if (ui.spinning) return;
        try {
          const data = await postJson(spinUrl);
          ui.spinToSegment(data.segment_index, data.segment_count, 4200, () => {
            showWinner(overlay, data.winner.name);
            applyState(data.state);
            if (spinBtn) spinBtn.disabled = !data.state.can_spin;
          });
        } catch (err) {
          alert(err.message);
          if (spinBtn) spinBtn.disabled = false;
        }
      });
    }

    root.querySelectorAll("[data-wheel-action]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        if (!confirm(btn.dataset.confirm || "Continue?")) return;
        try {
          const data = await postJson(btn.dataset.wheelAction);
          applyState(data.state);
          ui.setNames(data.state.active || []);
        } catch (err) {
          alert(err.message);
        }
      });
    });

    const addForm = root.querySelector("#wheel-add-names-form");
    if (addForm) {
      addForm.addEventListener("submit", async (e) => {
        e.preventDefault();
        const fd = new FormData(addForm);
        try {
          const data = await postJson(addForm.action, fd);
          applyState(data.state);
          ui.setNames(data.state.active || []);
          addForm.reset();
        } catch (err) {
          alert(err.message);
        }
      });
    }
  }

  function initWatch(root) {
    const canvas = root.querySelector("#speak-wheel-canvas");
    const stateUrl = root.dataset.stateUrl;
    const overlay = root.querySelector("#wheel-winner-overlay");
    let lastPick = "";
    let state = JSON.parse(root.dataset.initialState || "{}");

    const ui = new SpeakWheelUI(canvas, { names: state.active || [] });
    renderNameLists(state, root);

    let animFrom = null;
    async function poll() {
      try {
        const res = await fetch(stateUrl, { credentials: "same-origin" });
        const data = await res.json();
        if (!data.ok) return;

        const pickKey = data.recent_picks[0]
          ? data.recent_picks[0].name + data.recent_picks[0].picked_at
          : "";

        if (pickKey && pickKey !== lastPick) {
          lastPick = pickKey;
          const winnerName = data.recent_picks[0].name;
          if (!animFrom && !ui.spinning) {
            animFrom = pickKey;
            const count = Math.max(data.active.length, 1);
            const fakeIdx = Math.floor(Math.random() * count);
            ui.spinToSegment(fakeIdx, count, 3500, () => {
              showWinner(overlay, winnerName);
              animFrom = null;
              ui.setNames(data.active || []);
              renderNameLists(data, root);
            });
            return;
          } else {
            showWinner(overlay, winnerName);
          }
        }

        if (!ui.spinning) {
          ui.setNames(data.active || []);
          renderNameLists(data, root);
        }
      } catch (_) {}
    }

    setInterval(poll, 2000);
  }

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-wheel-board]").forEach(initBoard);
    document.querySelectorAll("[data-wheel-watch]").forEach(initWatch);
  });

  window.SpeakWheelUI = SpeakWheelUI;
})();
