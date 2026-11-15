import os
import time

from flask import Flask, request
from flask_cors import CORS
from flask_migrate import Migrate
from sqlalchemy import text

from .cloudwatch_metrics import emit_health_check_failure, emit_request_metrics
from .config import Config
from .logging_config import setup_logging
from .models import db
from .routes import api_bp, leaderboard_bp, quiz_bp, topic_bp, wiki_bp

migrate = Migrate()
logger = setup_logging()

SKIP_METRICS_PATHS = {"/health"}


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    if os.getenv("ALLOWED_ORIGINS"):
        allowed_origins = os.getenv("ALLOWED_ORIGINS").split(",")
        logger.info("CORS allowing specific origins", extra={"origins": allowed_origins})
        CORS(app, origins=allowed_origins, supports_credentials=True)
    else:
        logger.info("CORS allowing all origins (development mode)")
        CORS(app)

    db.init_app(app)
    migrate.init_app(app, db)

    app.register_blueprint(topic_bp)
    app.register_blueprint(quiz_bp)
    app.register_blueprint(leaderboard_bp)
    app.register_blueprint(wiki_bp)
    app.register_blueprint(api_bp)

    @app.before_request
    def before_request():
        request.start_time = time.time()

    @app.after_request
    def after_request(response):
        if request.path not in SKIP_METRICS_PATHS:
            duration_ms = (time.time() - request.start_time) * 1000
            endpoint = request.endpoint or "unknown"

            emit_request_metrics(
                method=request.method,
                endpoint=endpoint,
                status=response.status_code,
                duration_ms=duration_ms,
            )

            logger.info(
                "request processed",
                extra={
                    "method": request.method,
                    "path": request.path,
                    "endpoint": endpoint,
                    "status": response.status_code,
                    "duration_ms": round(duration_ms, 2),
                },
            )

        return response

    @app.route("/health", methods=["GET"])
    def health_check():
        try:
            db.session.execute(text("SELECT 1"))
            return {"status": "healthy", "database": "connected"}, 200
        except Exception as exc:
            emit_health_check_failure()
            logger.error(
                "health check failed",
                extra={"error": str(exc)},
            )
            return {"status": "unhealthy", "database": "disconnected"}, 503

    return app
