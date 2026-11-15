from flask import Blueprint, jsonify

topic_bp = Blueprint("topics", __name__, url_prefix="/api/topics")
quiz_bp = Blueprint("quizzes", __name__, url_prefix="/api/quiz")
wiki_bp = Blueprint("wiki", __name__, url_prefix="/api/wiki")
leaderboard_bp = Blueprint("leaderboard", __name__, url_prefix="/api/leaderboard")

api_bp = Blueprint("api", __name__, url_prefix="/api")


@api_bp.route("", methods=["GET"])
def api_health_check():
    return jsonify({"status": "healthy", "message": "API is operational"}), 200


from . import leaderboard_routes, quiz_routes, topic_routes, wiki_routes  # noqa: E402, F401
