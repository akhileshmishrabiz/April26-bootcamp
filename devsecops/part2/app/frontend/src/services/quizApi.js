import API_URL from '../config/api';

async function parseJsonResponse(response, fallbackMessage) {
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('application/json')) {
    throw new Error(
      response.ok
        ? fallbackMessage
        : `${fallbackMessage} (HTTP ${response.status})`
    );
  }
  return response.json();
}

export async function startQuiz(topicSlug, playerName) {
  const response = await fetch(`${API_URL}/api/quiz/${topicSlug}/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ player_name: playerName }),
  });
  const data = await parseJsonResponse(response, 'Failed to start quiz');
  if (!response.ok) {
    throw new Error(data.error || 'Failed to start quiz');
  }
  return data;
}

export async function submitQuiz(sessionId, answers, timeTakenSeconds) {
  const response = await fetch(`${API_URL}/api/quiz/submit`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      session_id: sessionId,
      answers,
      time_taken_seconds: timeTakenSeconds,
    }),
  });
  const data = await parseJsonResponse(response, 'Failed to submit quiz');
  if (!response.ok) {
    throw new Error(data.error || 'Failed to submit quiz');
  }
  return data;
}

export async function fetchLeaderboard({ scope = 'global', topic = null, limit = 50 } = {}) {
  const params = new URLSearchParams({ scope, limit: String(limit) });
  if (topic) {
    params.set('topic', topic);
  }
  const response = await fetch(`${API_URL}/api/leaderboard?${params}`);
  const data = await parseJsonResponse(response, 'Failed to load leaderboard');
  if (!response.ok) {
    throw new Error(data.error || 'Failed to load leaderboard');
  }
  return data;
}

export async function fetchLeaderboardStats() {
  const response = await fetch(`${API_URL}/api/leaderboard/stats`);
  const data = await parseJsonResponse(response, 'Failed to load stats');
  if (!response.ok) {
    throw new Error(data.error || 'Failed to load stats');
  }
  return data;
}

export async function fetchPlayerHistory(playerName, limit = 20) {
  const response = await fetch(
    `${API_URL}/api/leaderboard/player/${encodeURIComponent(playerName)}/history?limit=${limit}`
  );
  const data = await parseJsonResponse(response, 'Failed to load player history');
  if (!response.ok) {
    throw new Error(data.error || 'Failed to load player history');
  }
  return data;
}

export async function fetchTopics() {
  const response = await fetch(`${API_URL}/api/topics`);
  const data = await parseJsonResponse(response, 'Failed to load topics');
  if (!response.ok) {
    throw new Error(data.error || 'Failed to load topics');
  }
  return data;
}
