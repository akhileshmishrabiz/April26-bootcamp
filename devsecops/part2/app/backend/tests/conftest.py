import pytest

from app import create_app
from app.models import db


class TestConfig:
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite://"
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {}
    MAX_QUIZ_QUESTIONS = 5
    PASS_THRESHOLD = 70
    QUIZ_SESSION_TTL_MINUTES = 60
    LEADERBOARD_DEFAULT_LIMIT = 50


@pytest.fixture()
def app():
    application = create_app(TestConfig)
    with application.app_context():
        db.create_all()
        yield application
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()
