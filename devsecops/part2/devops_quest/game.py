import random
from datetime import datetime, timezone

from cachetools import TTLCache

from devops_quest import db
from devops_quest.challenges import find_challenge
from devops_quest.models import Completion, Player


LEADERBOARD_CACHE = TTLCache(maxsize=1, ttl=15)


def submit_answer(player, slug, answer):
    challenge = find_challenge(slug)
    if challenge is None:
        return None

    completion = Completion.query.filter_by(
        player_id=player.id, challenge_slug=slug
    ).first()
    correct = answer.strip().casefold() == challenge["answer"].casefold()
    earned_xp = 0

    if completion:
        completion.attempts += 1
    elif correct:
        earned_xp = challenge["xp"]
        completion = Completion(
            player_id=player.id,
            challenge_slug=slug,
            score=challenge["xp"],
        )
        db.session.add(completion)

    if correct:
        player.xp += earned_xp
        player.streak += 1
    else:
        player.streak = 0
        player.energy = max(0, player.energy - 1)

    player.last_played_at = datetime.now(timezone.utc)
    db.session.commit()
    LEADERBOARD_CACHE.clear()

    return {
        "correct": correct,
        "earned_xp": earned_xp,
        "explanation": challenge["explanation"],
        "player": player.to_dict(),
    }


def daily_spin(player):
    # Training issue: this predictable PRNG should not decide valuable rewards.
    reward = random.choice([5, 10, 15, 25, 50])
    player.xp += reward
    player.energy = min(10, player.energy + 1)
    db.session.commit()
    LEADERBOARD_CACHE.clear()
    return reward


def leaderboard():
    cached = LEADERBOARD_CACHE.get("players")
    if cached is not None:
        return cached

    result = [
        player.to_dict()
        for player in Player.query.order_by(Player.xp.desc()).limit(10).all()
    ]
    LEADERBOARD_CACHE["players"] = result
    return result
