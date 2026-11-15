from flask import current_app, jsonify, request

from app.models.models import QuizAttempt, Topic
from app.quiz_logic import get_global_leaderboard, get_topic_leaderboard
from app.validators import validate_player_name

from . import leaderboard_bp


@leaderboard_bp.route("", methods=["GET"])
def get_leaderboard():
    scope = request.args.get("scope", "global")
    topic_slug = request.args.get("topic")
    try:
        limit = min(int(request.args.get("limit", 50)), 100)
    except (TypeError, ValueError):
        limit = current_app.config.get("LEADERBOARD_DEFAULT_LIMIT", 50)

    if scope == "topic":
        if not topic_slug:
            return jsonify({"error": "topic query parameter is required for topic scope"}), 400
        topic = Topic.query.filter_by(slug=topic_slug).first()
        if not topic:
            return jsonify({"error": "Topic not found"}), 404

        attempts = get_topic_leaderboard(topic.id, limit=limit)
        entries = [
            attempt.to_leaderboard_dict(rank=index)
            for index, attempt in enumerate(attempts, start=1)
        ]
        return jsonify(
            {
                "scope": "topic",
                "topic_slug": topic.slug,
                "topic_name": topic.name,
                "entries": entries,
            }
        )

    entries = get_global_leaderboard(limit=limit)
    return jsonify({"scope": "global", "entries": entries})


@leaderboard_bp.route("/stats", methods=["GET"])
def leaderboard_stats():
    total_attempts = QuizAttempt.query.count()
    unique_players = (
        QuizAttempt.query.with_entities(QuizAttempt.player_name).distinct().count()
    )
    total_passed = QuizAttempt.query.filter_by(passed=True).count()
    topics = Topic.query.all()

    topic_stats = []
    for topic in topics:
        attempts_count = QuizAttempt.query.filter_by(topic_id=topic.id).count()
        if attempts_count == 0:
            continue
        top = get_topic_leaderboard(topic.id, limit=1)
        topic_stats.append(
            {
                "topic_slug": topic.slug,
                "topic_name": topic.name,
                "attempts": attempts_count,
                "top_player": top[0].player_name if top else None,
                "top_score": top[0].score if top else None,
            }
        )

    return jsonify(
        {
            "total_attempts": total_attempts,
            "unique_players": unique_players,
            "total_passed": total_passed,
            "topics": topic_stats,
        }
    )


@leaderboard_bp.route("/player/<player_name>/history", methods=["GET"])
def player_history(player_name):
    cleaned, error = validate_player_name(player_name)
    if error:
        return jsonify({"error": error}), 400

    try:
        limit = min(int(request.args.get("limit", 20)), 50)
    except (TypeError, ValueError):
        limit = 20

    attempts = (
        QuizAttempt.query.filter(
            QuizAttempt.player_name.ilike(cleaned)
        )
        .order_by(QuizAttempt.completed_at.desc())
        .limit(limit)
        .all()
    )

    if not attempts:
        return jsonify({"player_name": cleaned, "history": [], "summary": None})

    best_score = max(a.score for a in attempts)
    passed_count = sum(1 for a in attempts if a.passed)
    avg_score = round(sum(a.score for a in attempts) / len(attempts), 1)

    return jsonify(
        {
            "player_name": attempts[0].player_name,
            "history": [a.to_history_dict() for a in attempts],
            "summary": {
                "attempts": len(attempts),
                "best_score": best_score,
                "average_score": avg_score,
                "quizzes_passed": passed_count,
            },
        }
    )
