import re

PLAYER_NAME_PATTERN = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,28}[a-zA-Z0-9]$|^[a-zA-Z0-9]$")


def validate_player_name(name):
    if not name or not isinstance(name, str):
        return None, "Player name is required"
    cleaned = name.strip()
    if len(cleaned) < 2 or len(cleaned) > 30:
        return None, "Player name must be 2–30 characters"
    if not PLAYER_NAME_PATTERN.match(cleaned):
        return None, "Use letters, numbers, spaces, hyphens, or underscores only"
    return cleaned, None
