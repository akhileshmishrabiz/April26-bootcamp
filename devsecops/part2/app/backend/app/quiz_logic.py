import random

from flask import current_app

from app.models.models import QuizAttempt, QuizSession, Question, Topic


def create_quiz_session(topic, player_name):
    all_questions = Question.query.filter_by(topic_id=topic.id).all()
    max_questions = current_app.config.get("MAX_QUIZ_QUESTIONS", 15)
    selected = random.sample(all_questions, min(max_questions, len(all_questions)))

    question_data = []
    public_questions = []
    for question in selected:
        shuffled = question.shuffle_options()
        question_data.append(
            {
                "id": question.id,
                "correct_index": shuffled["correct_index"],
                "options": shuffled["options"],
            }
        )
        public_questions.append(
            {
                "id": question.id,
                "question": question.question_text,
                "options": shuffled["options"],
            }
        )

    session = QuizSession(
        topic_id=topic.id,
        player_name=player_name,
        question_data=question_data,
        expires_at=QuizSession.default_expiry(
            current_app.config.get("QUIZ_SESSION_TTL_MINUTES", 60)
        ),
    )
    return session, public_questions


def dedupe_leaderboard_attempts(attempts, limit=50):
    seen = set()
    leaderboard = []
    for attempt in attempts:
        key = attempt.player_name.lower()
        if key in seen:
            continue
        seen.add(key)
        leaderboard.append(attempt)
        if len(leaderboard) >= limit:
            break
    return leaderboard


def get_topic_leaderboard(topic_id, limit=None):
    limit = limit or current_app.config.get("LEADERBOARD_DEFAULT_LIMIT", 50)
    attempts = (
        QuizAttempt.query.filter_by(topic_id=topic_id)
        .order_by(
            QuizAttempt.score.desc(),
            QuizAttempt.time_taken_seconds.asc(),
            QuizAttempt.completed_at.asc(),
        )
        .all()
    )
    return dedupe_leaderboard_attempts(attempts, limit)


def get_global_leaderboard(limit=None):
    limit = limit or current_app.config.get("LEADERBOARD_DEFAULT_LIMIT", 50)
    topics = Topic.query.all()
    player_stats = {}

    for topic in topics:
        best_attempts = get_topic_leaderboard(topic.id, limit=1000)
        for attempt in best_attempts:
            key = attempt.player_name.lower()
            if key not in player_stats:
                player_stats[key] = {
                    "player_name": attempt.player_name,
                    "total_points": 0,
                    "quizzes_passed": 0,
                    "quizzes_taken": 0,
                    "best_scores": [],
                }
            stats = player_stats[key]
            stats["total_points"] += attempt.score
            stats["quizzes_taken"] += 1
            if attempt.passed:
                stats["quizzes_passed"] += 1
            stats["best_scores"].append(attempt.score)

    ranked = sorted(
        player_stats.values(),
        key=lambda s: (-s["total_points"], -s["quizzes_passed"], s["player_name"].lower()),
    )[:limit]

    results = []
    for index, stats in enumerate(ranked, start=1):
        avg = round(sum(stats["best_scores"]) / len(stats["best_scores"]), 1)
        results.append(
            {
                "rank": index,
                "player_name": stats["player_name"],
                "total_points": round(stats["total_points"], 1),
                "quizzes_taken": stats["quizzes_taken"],
                "quizzes_passed": stats["quizzes_passed"],
                "average_score": avg,
            }
        )
    return results


def get_player_rank(topic_id, player_name):
    attempts = get_topic_leaderboard(topic_id, limit=1000)
    for index, attempt in enumerate(attempts, start=1):
        if attempt.player_name.lower() == player_name.lower():
            return index
    return len(attempts) + 1
