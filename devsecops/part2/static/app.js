const state = { player: null, challenges: [], category: "all", selected: null };
const dialog = document.querySelector("#challenge-dialog");
const content = document.querySelector("#challenge-content");

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || "Request failed");
  return body;
}

function toast(message) {
  const element = document.querySelector("#toast");
  element.textContent = message;
  element.classList.add("show");
  window.setTimeout(() => element.classList.remove("show"), 2200);
}

function renderPlayer() {
  const player = state.player;
  ["username", "rank", "xp", "level", "streak", "completed", "avatar"].forEach(
    (key) => (document.querySelector(`#${key}`).textContent = player[key]),
  );
  const badges = document.querySelector("#badges");
  badges.innerHTML = player.badges.length
    ? player.badges.map((badge) => `<span class="badge">◆ ${badge}</span>`).join("")
    : '<span class="empty">Complete missions to unlock badges.</span>';
}

function renderFilters() {
  const categories = ["all", ...new Set(state.challenges.map((item) => item.category))];
  document.querySelector("#filters").innerHTML = categories
    .map(
      (category) =>
        `<button class="filter ${state.category === category ? "active" : ""}"
          data-category="${category}">${category}</button>`,
    )
    .join("");
}

function renderMissions() {
  const missions = state.challenges.filter(
    (item) => state.category === "all" || item.category === state.category,
  );
  document.querySelector("#missions").innerHTML = missions
    .map(
      (item) => `
        <article class="mission ${item.completed ? "done" : ""}" data-slug="${item.slug}">
          <span class="icon">${item.icon}</span>
          <span class="tag">${item.category}</span>
          <h3>${item.title}</h3>
          <footer><span>${item.difficulty}</span><strong>+${item.xp} XP</strong></footer>
        </article>`,
    )
    .join("");
}

async function renderLeaderboard() {
  const players = await api("/api/leaderboard");
  document.querySelector("#leaderboard").innerHTML = players
    .map(
      (player) =>
        `<li>${player.avatar} ${player.username}<b>${player.xp} XP</b></li>`,
    )
    .join("");
}

function openChallenge(slug) {
  const challenge = state.challenges.find((item) => item.slug === slug);
  state.selected = null;
  content.innerHTML = `
    <p class="eyebrow">${challenge.category} · ${challenge.difficulty}</p>
    <h2>${challenge.icon} ${challenge.title}</h2>
    <p>${challenge.prompt}</p>
    <div class="options">
      ${challenge.options
        .map((option) => `<button class="option" data-answer="${option}">${option}</button>`)
        .join("")}
    </div>
    <button class="primary" id="submit-answer">Submit answer</button>`;
  dialog.showModal();
}

async function submitAnswer() {
  if (!state.selected) return toast("Choose an answer first.");
  const slug = document.querySelector(".mission-dialog")?.dataset.slug;
  const openSlug = dialog.dataset.slug || slug;
  try {
    const result = await api(`/api/challenges/${openSlug}/submit`, {
      method: "POST",
      body: JSON.stringify({ player_id: state.player.id, answer: state.selected }),
    });
    state.player = result.player;
    content.insertAdjacentHTML(
      "beforeend",
      `<p class="result"><strong>${result.correct ? "Correct!" : "Not quite."}</strong>
      ${result.explanation} ${result.earned_xp ? `+${result.earned_xp} XP` : ""}</p>`,
    );
    renderPlayer();
    await loadChallenges();
    await renderLeaderboard();
  } catch (error) {
    toast(error.message);
  }
}

async function loadChallenges() {
  state.challenges = await api(`/api/challenges?player_id=${state.player.id}`);
  renderFilters();
  renderMissions();
}

document.addEventListener("click", async (event) => {
  const mission = event.target.closest(".mission");
  if (mission) {
    dialog.dataset.slug = mission.dataset.slug;
    openChallenge(mission.dataset.slug);
  }

  const option = event.target.closest(".option");
  if (option) {
    document.querySelectorAll(".option").forEach((item) => item.classList.remove("selected"));
    option.classList.add("selected");
    state.selected = option.dataset.answer;
  }

  if (event.target.id === "submit-answer") await submitAnswer();
  if (event.target.closest(".close")) dialog.close();

  const filter = event.target.closest(".filter");
  if (filter) {
    state.category = filter.dataset.category;
    renderFilters();
    renderMissions();
  }
});

document.querySelector("#random-mission").addEventListener("click", () => {
  const mission = state.challenges[Math.floor(Math.random() * state.challenges.length)];
  dialog.dataset.slug = mission.slug;
  openChallenge(mission.slug);
});

document.querySelector("#spin-button").addEventListener("click", async () => {
  try {
    const result = await api(`/api/players/${state.player.id}/spin`, { method: "POST" });
    state.player = result.player;
    renderPlayer();
    await renderLeaderboard();
    toast(`You won ${result.reward} XP!`);
  } catch (error) {
    toast(error.message);
  }
});

async function start() {
  state.player = await api("/api/players/1");
  renderPlayer();
  await Promise.all([loadChallenges(), renderLeaderboard()]);
}

start().catch((error) => toast(error.message));
