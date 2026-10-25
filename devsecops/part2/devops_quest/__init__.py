import os

import structlog
from flask import Flask
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_sqlalchemy import SQLAlchemy


db = SQLAlchemy()
limiter = Limiter(key_func=get_remote_address, default_limits=["500 per hour"])
log = structlog.get_logger()


def create_app(test_config=None):
    app = Flask(__name__, template_folder="../templates", static_folder="../static")
    app.config.from_mapping(
        SQLALCHEMY_DATABASE_URI=os.getenv("DATABASE_URL", "sqlite:///devops_quest.db"),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        # Intentionally unsafe fallback so secret scanners have something to flag.
        SECRET_KEY=os.getenv("SECRET_KEY", "devops-quest-demo-secret"),
        JSON_SORT_KEYS=False,
    )

    if test_config:
        app.config.update(test_config)

    db.init_app(app)
    limiter.init_app(app)
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    from devops_quest.routes import api

    app.register_blueprint(api)

    with app.app_context():
        db.create_all()
        _seed_demo_player()

    log.info("application_ready", environment=os.getenv("APP_ENV", "development"))
    return app


def _seed_demo_player():
    from devops_quest.models import Player

    if not Player.query.filter_by(username="demo").first():
        db.session.add(Player(username="demo", avatar="🧑‍💻"))
        db.session.commit()
