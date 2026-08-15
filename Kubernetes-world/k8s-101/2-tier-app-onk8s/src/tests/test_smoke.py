"""
Smoke tests — fast checks that the app is alive and core routes respond.

Run locally:
    cd src
    pytest -m smoke -v

These differ from full unit tests: they only cover critical paths and should
complete in seconds.
"""

import os
import pytest

os.environ.setdefault("DB_LINK", "sqlite:///:memory:")

from app import create_app, db
from app.models.models import User
from app.seed import ADMIN_EMAIL


@pytest.fixture
def app():
    os.environ["DB_LINK"] = "sqlite:///:memory:"
    application = create_app()
    application.config["TESTING"] = True
    application.config["WTF_CSRF_ENABLED"] = False

    with application.app_context():
        db.create_all()
        yield application
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def admin_client(client, app):
    with app.app_context():
        admin = User.query.filter_by(email=ADMIN_EMAIL).first()
        assert admin is not None

    client.post(
        "/login",
        data={"username": "livingdevops", "password": "LivingDevops1!"},
    )
    return client


# ── Public endpoints (no auth) ───────────────────────────────────────────────


@pytest.mark.smoke
def test_smoke_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"


@pytest.mark.smoke
def test_smoke_metrics(client):
    response = client.get("/metrics")
    assert response.status_code == 200


@pytest.mark.smoke
def test_smoke_login_page(client):
    response = client.get("/login")
    assert response.status_code == 200
    assert b"Login" in response.data or b"Sign in" in response.data


@pytest.mark.smoke
def test_smoke_register_page(client):
    response = client.get("/register")
    assert response.status_code == 200
    assert b"Register" in response.data or b"account" in response.data


# ── Auth + core modules ──────────────────────────────────────────────────────


@pytest.mark.smoke
def test_smoke_admin_login_and_dashboard(admin_client):
    response = admin_client.get("/", follow_redirects=True)
    assert response.status_code == 200
    assert b"Dashboard" in response.data or b"dashboard" in response.data.lower()


@pytest.mark.smoke
def test_smoke_retro_list(admin_client):
    response = admin_client.get("/retro")
    assert response.status_code == 200


@pytest.mark.smoke
def test_smoke_teams_list(admin_client):
    response = admin_client.get("/teams")
    assert response.status_code == 200


@pytest.mark.smoke
def test_smoke_tickets_list(admin_client):
    response = admin_client.get("/tickets")
    assert response.status_code == 200


@pytest.mark.smoke
def test_smoke_incidents_list(admin_client):
    response = admin_client.get("/incidents")
    assert response.status_code == 200


@pytest.mark.smoke
def test_smoke_seed_data_present(app):
    with app.app_context():
        assert User.query.filter_by(email=ADMIN_EMAIL).count() == 1
