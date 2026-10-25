import pytest

from devops_quest import create_app, db


@pytest.fixture()
def app():
    application = create_app(
        {
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
            "RATELIMIT_ENABLED": False,
        }
    )

    yield application

    with application.app_context():
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()
