import hashlib
import random
from datetime import date

from flask import Blueprint, jsonify, render_template, request
from flask_login import current_user, login_required
from sqlalchemy import desc, func

from app import db
from app.games_data import (
    ACHIEVEMENTS,
    DEPLOY_SCENARIOS,
    DOCKERFILE_CHALLENGES,
    GAME_TYPE_LABELS,
    GAMES,
    INCIDENT_SCENARIOS,
    K8S_YAML_CHALLENGES,
    LOG_CHALLENGES,
    PIPELINE_CORRECT_ORDER,
    PIPELINE_STAGES,
    SLUG_TO_GAME_TYPE,
)
from app.models.models import GameScore, PlayerAchievement, PlayerProfile

games_bp = Blueprint("games", __name__, url_prefix="/games")

GAME_TEMPLATES = {
    "pipeline-puzzle": "games/pipeline_puzzle.html",
    "incident-commander": "games/incident_commander.html",
    "dockerfile-builder": "games/dockerfile_builder.html",
    "k8s-yaml-fixer": "games/k8s_yaml_fixer.html",
    "log-detective": "games/log_detective.html",
    "deploy-rollback": "games/deploy_rollback.html",
}

RESERVED_SLUGS = {"leaderboard", "achievements", "api"}


def get_player_name():
    return current_user.label


def ensure_player(name):
    profile = PlayerProfile.query.filter_by(player_name=name).first()
    if not profile:
        profile = PlayerProfile(player_name=name)
        db.session.add(profile)
        db.session.commit()
    return profile


def award_badge(player_name, badge_id):
    if badge_id not in ACHIEVEMENTS:
        return False
    existing = PlayerAchievement.query.filter_by(
        player_name=player_name, badge_id=badge_id
    ).first()
    if existing:
        return False
    db.session.add(PlayerAchievement(player_name=player_name, badge_id=badge_id))
    db.session.commit()
    return True


def get_daily_game():
    seed = int(hashlib.md5(date.today().isoformat().encode()).hexdigest(), 16)
    return GAMES[seed % len(GAMES)]


def get_personal_bests(player_name):
    bests = {}
    for slug, game_type in SLUG_TO_GAME_TYPE.items():
        best = (
            db.session.query(func.max(GameScore.score))
            .filter_by(player_name=player_name, game_type=game_type)
            .scalar()
        )
        bests[slug] = best
    return bests


def get_badge_progress(player_name):
    earned_ids = {
        a.badge_id
        for a in PlayerAchievement.query.filter_by(player_name=player_name).all()
    }
    played_games = {
        row.game_type
        for row in GameScore.query.filter_by(player_name=player_name).all()
    }
    best_scores = {}
    for game_type in SLUG_TO_GAME_TYPE.values():
        best = (
            db.session.query(func.max(GameScore.score))
            .filter_by(player_name=player_name, game_type=game_type)
            .scalar()
        )
        if best is not None:
            best_scores[game_type] = best

    progress = {}
    for badge_id, badge in ACHIEVEMENTS.items():
        if badge_id in earned_ids:
            progress[badge_id] = {
                "earned": True,
                "current": badge["threshold"],
                "percent": 100,
            }
            continue
        if badge["game"] == "all":
            current = len(played_games)
            threshold = badge["threshold"]
        else:
            current = best_scores.get(badge["game"], 0)
            threshold = badge["threshold"]
        percent = min(100, int((current / threshold) * 100)) if threshold else 0
        progress[badge_id] = {"earned": False, "current": current, "percent": percent}
    return progress


def check_achievements(player_name, game_type, score):
    earned = []
    if game_type == "pipeline_puzzle" and score >= 600:
        if award_badge(player_name, "pipeline_master"):
            earned.append("pipeline_master")
    if game_type == "deploy_rollback" and score >= 300:
        if award_badge(player_name, "zero_downtime_hero"):
            earned.append("zero_downtime_hero")
    if game_type == "log_detective" and score >= 450:
        if award_badge(player_name, "log_sleuth"):
            earned.append("log_sleuth")
    if game_type == "incident_commander" and score >= 350:
        if award_badge(player_name, "incident_warlord"):
            earned.append("incident_warlord")
    if game_type == "dockerfile_builder" and score >= 450:
        if award_badge(player_name, "docker_whisperer"):
            earned.append("docker_whisperer")
    if game_type == "k8s_yaml_fixer" and score >= 450:
        if award_badge(player_name, "yaml_yoda"):
            earned.append("yaml_yoda")

    played_games = {
        row.game_type
        for row in GameScore.query.filter_by(player_name=player_name).all()
    }
    if len(played_games) >= 6:
        if award_badge(player_name, "devops_legend"):
            earned.append("devops_legend")
    return earned


@games_bp.route("/")
@login_required
def home():
    player = get_player_name()
    profile = PlayerProfile.query.filter_by(player_name=player).first()
    badges = PlayerAchievement.query.filter_by(player_name=player).all()
    top_scores = (
        db.session.query(
            GameScore.player_name,
            func.sum(GameScore.score).label("total"),
        )
        .group_by(GameScore.player_name)
        .order_by(desc("total"))
        .limit(5)
        .all()
    )
    recent_scores = GameScore.query.order_by(desc(GameScore.played_at)).limit(8).all()
    daily_game = get_daily_game()
    personal_bests = get_personal_bests(player)
    return render_template(
        "games/home.html",
        games=GAMES,
        player=player,
        profile=profile,
        badges=badges,
        top_scores=top_scores,
        achievements=ACHIEVEMENTS,
        recent_scores=recent_scores,
        daily_game=daily_game,
        personal_bests=personal_bests,
        game_type_labels=GAME_TYPE_LABELS,
    )


@games_bp.route("/leaderboard")
@login_required
def leaderboard():
    player = get_player_name()
    rows = (
        db.session.query(
            GameScore.player_name,
            func.sum(GameScore.score).label("total_score"),
            func.count(GameScore.id).label("games_played"),
        )
        .group_by(GameScore.player_name)
        .order_by(desc("total_score"))
        .limit(50)
        .all()
    )
    game_breakdown = (
        db.session.query(
            GameScore.game_type,
            GameScore.player_name,
            func.max(GameScore.score).label("best_score"),
        )
        .group_by(GameScore.game_type, GameScore.player_name)
        .order_by(desc("best_score"))
        .all()
    )
    return render_template(
        "games/leaderboard.html",
        rows=rows,
        game_breakdown=game_breakdown,
        games=GAMES,
        player=player,
        personal_bests=get_personal_bests(player),
        game_type_labels=GAME_TYPE_LABELS,
    )


@games_bp.route("/achievements")
@login_required
def achievements_page():
    player = get_player_name()
    earned = {
        a.badge_id: a.earned_at
        for a in PlayerAchievement.query.filter_by(player_name=player).all()
    }
    progress = get_badge_progress(player)
    return render_template(
        "games/achievements.html",
        achievements=ACHIEVEMENTS,
        earned=earned,
        progress=progress,
        player=player,
    )


@games_bp.route("/api/recent-scores")
@login_required
def api_recent_scores():
    rows = GameScore.query.order_by(desc(GameScore.played_at)).limit(10).all()
    return jsonify(
        [
            {
                **r.to_dict(),
                "game_label": GAME_TYPE_LABELS.get(r.game_type, r.game_type),
            }
            for r in rows
        ]
    )


@games_bp.route("/api/score", methods=["POST"])
@login_required
def submit_score():
    data = request.get_json(silent=True) or {}
    player = get_player_name()
    game_type = data.get("game_type", "")
    score = int(data.get("score", 0))
    details = data.get("details", "")

    if not game_type:
        return jsonify({"error": "game_type required"}), 400

    daily = get_daily_game()
    daily_type = SLUG_TO_GAME_TYPE.get(daily["slug"])
    bonus_applied = False
    if daily_type == game_type:
        score = score * 2
        bonus_applied = True
        details = (details + " [Daily 2×]").strip()

    ensure_player(player)
    record = GameScore(
        player_name=player,
        game_type=game_type,
        score=max(0, score),
        details=details,
    )
    db.session.add(record)

    profile = PlayerProfile.query.filter_by(player_name=player).first()
    if profile:
        profile.games_played += 1
        profile.total_score += max(0, score)

    db.session.commit()
    new_badges = check_achievements(player, game_type, score)
    return jsonify(
        {
            "ok": True,
            "score": score,
            "daily_bonus": bonus_applied,
            "new_badges": [{"id": b, **ACHIEVEMENTS[b]} for b in new_badges],
        }
    )


@games_bp.route("/api/leaderboard")
@login_required
def api_leaderboard():
    rows = (
        db.session.query(
            GameScore.player_name,
            func.sum(GameScore.score).label("total"),
        )
        .group_by(GameScore.player_name)
        .order_by(desc("total"))
        .limit(20)
        .all()
    )
    return jsonify([{"player": r[0], "score": int(r[1])} for r in rows])


@games_bp.route("/<slug>")
@login_required
def game_page(slug):
    if slug in RESERVED_SLUGS:
        return render_template("games/404.html", player=get_player_name()), 404

    game = next((g for g in GAMES if g["slug"] == slug), None)
    if not game:
        return render_template("games/404.html", player=get_player_name()), 404

    player = get_player_name()
    context = {
        "game": game,
        "player": player,
        "personal_best": get_personal_bests(player).get(slug),
        "is_daily": get_daily_game()["slug"] == slug,
    }

    if slug == "pipeline-puzzle":
        shuffled = PIPELINE_STAGES.copy()
        random.shuffle(shuffled)
        context["stages"] = shuffled
        context["correct_order"] = PIPELINE_CORRECT_ORDER
    elif slug == "incident-commander":
        context["scenarios"] = random.sample(
            INCIDENT_SCENARIOS, min(4, len(INCIDENT_SCENARIOS))
        )
    elif slug == "dockerfile-builder":
        context["challenges"] = DOCKERFILE_CHALLENGES
    elif slug == "k8s-yaml-fixer":
        context["challenges"] = K8S_YAML_CHALLENGES
    elif slug == "log-detective":
        context["challenges"] = LOG_CHALLENGES
    elif slug == "deploy-rollback":
        context["scenarios"] = DEPLOY_SCENARIOS

    return render_template(GAME_TEMPLATES[slug], **context)
