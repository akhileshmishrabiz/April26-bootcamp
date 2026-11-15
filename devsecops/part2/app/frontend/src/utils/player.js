const PLAYER_STORAGE_KEY = 'devopsdojo_player_name';

export function getPlayerName() {
  return localStorage.getItem(PLAYER_STORAGE_KEY) || '';
}

export function setPlayerName(name) {
  const trimmed = name.trim();
  if (trimmed) {
    localStorage.setItem(PLAYER_STORAGE_KEY, trimmed);
  } else {
    localStorage.removeItem(PLAYER_STORAGE_KEY);
  }
  return trimmed;
}

export function validatePlayerName(name) {
  const trimmed = name.trim();
  if (trimmed.length < 2 || trimmed.length > 30) {
    return 'Name must be 2–30 characters';
  }
  if (!/^[a-zA-Z0-9][a-zA-Z0-9 _-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$/.test(trimmed)) {
    return 'Use letters, numbers, spaces, hyphens, or underscores';
  }
  return null;
}
