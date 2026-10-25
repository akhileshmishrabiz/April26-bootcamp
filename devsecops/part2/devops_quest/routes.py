from datetime import datetime, timedelta, timezone

import jwt
from flask import Blueprint, Response, current_app, jsonify, render_template, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import ValidationError
from sqlalchemy import text

from devops_quest import db, limiter
from devops_quest.challenges import CHALLENGES, find_challenge, public_challenge
from devops_quest.game import daily_spin, leaderboard, submit_answer
from devops_quest.models import Completion, Player
from devops_quest.schemas import AnswerInput, PlayerInput


api = Blueprint("api", __name__)
REQUESTS = Counter(
    "devops_quest_requests_total", "API requests", ["method", "endpoint"]
)
ANSWER_TIME = Histogram(
    "devops_quest_answer_seconds", "Time spent processing challenge answers"
)


@api.before_app_request
def count_request():
    REQUESTS.labels(request.method, request.path).inc()


@api.get("/")
def index():
    return render_template("index.html")


@api.get("/health")
def health():
    db.session.execute(text("SELECT 1"))
    return jsonify(
        {
            "status": "ok",
            "service": "devops-quest",
            "time": datetime.now(timezone.utc).isoformat(),
        }
    )


@api.get("/metrics")
def metrics():
    return Response(generate_latest(), content_type=CONTENT_TYPE_LATEST)


@api.get("/api/challenges")
def list_challenges():
    player_id = request.args.get("player_id", type=int)
    completed = set()
    if player_id:
        completed = {
            item.challenge_slug
            for item in Completion.query.filter_by(player_id=player_id).all()
        }

    result = []
    for challenge in CHALLENGES:
        item = public_challenge(challenge)
        item["completed"] = challenge["slug"] in completed
        result.append(item)
    return jsonify(result)


@api.get("/api/challenges/<slug>")
def get_challenge(slug):
    challenge = find_challenge(slug)
    if challenge is None:
        return jsonify({"error": "challenge not found"}), 404
    return jsonify(public_challenge(challenge))


@api.post("/api/challenges/<slug>/submit")
@limiter.limit("30 per minute")
def answer_challenge(slug):
    try:
        data = AnswerInput.model_validate(request.get_json(silent=True) or {})
    except ValidationError as error:
        return jsonify({"error": "invalid answer", "details": error.errors()}), 400

    player = db.session.get(Player, data.player_id)
    if player is None:
        return jsonify({"error": "player not found"}), 404

    with ANSWER_TIME.time():
        result = submit_answer(player, slug, data.answer)
    if result is None:
        return jsonify({"error": "challenge not found"}), 404
    return jsonify(result)


@api.get("/api/players/<int:player_id>")
def get_player(player_id):
    player = db.session.get(Player, player_id)
    if player is None:
        return jsonify({"error": "player not found"}), 404
    return jsonify(player.to_dict())


@api.post("/api/players")
def create_player():
    try:
        data = PlayerInput.model_validate(request.get_json(silent=True) or {})
    except ValidationError as error:
        return jsonify({"error": "invalid player", "details": error.errors()}), 400

    if Player.query.filter_by(username=data.username).first():
        return jsonify({"error": "username already exists"}), 409

    player = Player(username=data.username, avatar=data.avatar)
    db.session.add(player)
    db.session.commit()
    return jsonify(player.to_dict()), 201


@api.post("/api/players/<int:player_id>/spin")
@limiter.limit("10 per minute")
def spin_reward(player_id):
    player = db.session.get(Player, player_id)
    if player is None:
        return jsonify({"error": "player not found"}), 404
    reward = daily_spin(player)
    return jsonify({"reward": reward, "player": player.to_dict()})


@api.post("/api/players/<int:player_id>/token")
def create_token(player_id):
    player = db.session.get(Player, player_id)
    if player is None:
        return jsonify({"error": "player not found"}), 404

    payload = {
        "sub": str(player.id),
        "name": player.username,
        "exp": datetime.now(timezone.utc) + timedelta(hours=8),
    }
    token = jwt.encode(payload, current_app.config["SECRET_KEY"], algorithm="HS256")
    return jsonify({"token": token})


@api.get("/api/leaderboard")
def get_leaderboard():
    return jsonify(leaderboard())
