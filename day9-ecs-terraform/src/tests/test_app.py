import os
import pytest

os.environ.setdefault("DB_LINK", "sqlite:///:memory:")

from app import create_app, db
from app.models.models import User, Student, Attendance, Assignment, Retro, RetroCard, RetroLike
from app.seed import ADMIN_EMAIL
from datetime import date, timedelta


@pytest.fixture
def app():
    os.environ["DB_LINK"] = "sqlite:///:memory:"
    app = create_app()
    app.config["TESTING"] = True
    app.config["WTF_CSRF_ENABLED"] = False

    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def auth_client(client, app):
    """A test client that is already logged in."""
    with app.app_context():
        user = User(username="testuser", email="test@example.com")
        user.set_password("Password1")
        db.session.add(user)
        db.session.commit()

    client.post("/login", data={"username": "testuser", "password": "Password1"})
    return client


@pytest.fixture
def admin_client(client, app):
    with app.app_context():
        admin = User.query.filter_by(email=ADMIN_EMAIL).first()
        assert admin is not None
        assert admin.is_admin is True

    client.post(
        "/login",
        data={"username": "livingdevops", "password": "LivingDevops1!"},
    )
    return client


# ── Auth tests ────────────────────────────────────────────────────────────────

def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"
    assert data["database"] == "connected"


def test_admin_user_seeded(app):
    with app.app_context():
        admin = User.query.filter_by(email=ADMIN_EMAIL).first()
        assert admin is not None
        assert admin.is_admin is True
        assert admin.check_password("LivingDevops1!")


def test_register_new_user(client, app):
    response = client.post(
        "/register",
        data={"username": "alice", "email": "alice@example.com", "password": "Secure99"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    with app.app_context():
        assert User.query.filter_by(username="alice").first() is not None


def test_login_valid_credentials(client, app):
    with app.app_context():
        user = User(username="bob", email="bob@example.com")
        user.set_password("Hello123")
        db.session.add(user)
        db.session.commit()

    response = client.post(
        "/login",
        data={"username": "bob", "password": "Hello123"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"dashboard" in response.data.lower() or response.request.path == "/"


def test_login_invalid_credentials(client):
    response = client.post(
        "/login",
        data={"username": "nobody", "password": "wrongpass"},
        follow_redirects=True,
    )
    assert b"Invalid username or password" in response.data


# ── Student tests ─────────────────────────────────────────────────────────────

def test_add_student(auth_client, app):
    response = auth_client.post(
        "/add_student",
        data={"name": "Jane Doe"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    with app.app_context():
        student = Student.query.filter_by(name="Jane Doe").first()
        assert student is not None


def test_delete_student(auth_client, app):
    with app.app_context():
        student = Student(name="To Delete")
        db.session.add(student)
        db.session.commit()
        student_id = student.id

    response = auth_client.post(f"/delete_student/{student_id}")
    assert response.status_code == 204
    with app.app_context():
        assert db.session.get(Student, student_id) is None


# ── Attendance tests ──────────────────────────────────────────────────────────

def test_mark_attendance(auth_client, app):
    with app.app_context():
        student = Student(name="Attend Me")
        db.session.add(student)
        db.session.commit()
        student_id = student.id

    today = date.today().isoformat()
    response = auth_client.post(
        "/mark_attendance",
        data={"date": today, f"status_{student_id}": "Present"},
        follow_redirects=True,
    )
    assert response.status_code == 200

    with app.app_context():
        saved = Attendance.query.filter_by(
            student_id=student_id, status="Present"
        ).first()
        assert saved is not None
        assert saved.status == "Present"


# ── Assignment tests ──────────────────────────────────────────────────────────

def test_add_assignment(auth_client, app):
    due = (date.today() + timedelta(days=7)).isoformat()
    response = auth_client.post(
        "/add_assignment",
        data={"title": "HW1", "description": "Do it", "due_date": due, "link": ""},
        follow_redirects=True,
    )
    assert response.status_code == 200
    with app.app_context():
        assignment = Assignment.query.filter_by(title="HW1").first()
        assert assignment is not None
        assert assignment.is_completed is False


def test_toggle_assignment(auth_client, app):
    with app.app_context():
        user = User.query.filter_by(username="testuser").first()
        due = date.today() + timedelta(days=3)
        assignment = Assignment(title="Toggle Me", due_date=due, created_by=user.id)
        db.session.add(assignment)
        db.session.commit()
        assignment_id = assignment.id

    auth_client.post(f"/toggle_assignment/{assignment_id}", follow_redirects=True)
    with app.app_context():
        assert db.session.get(Assignment, assignment_id).is_completed is True


# ── Retro tests ───────────────────────────────────────────────────────────────

def test_admin_can_create_retro(admin_client, app):
    response = admin_client.post(
        "/retro/create",
        data={
            "title": "Sprint 9 Retro",
            "description": "ECS deploy went... mostly fine",
        },
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Sprint 9 Retro" in response.data

    with app.app_context():
        retro = Retro.query.filter_by(title="Sprint 9 Retro").first()
        assert retro is not None
        assert retro.status == "open"


def test_user_can_add_card_like_and_comment(auth_client, admin_client, app):
    admin_client.post(
        "/retro/create",
        data={"title": "Team Retro", "description": ""},
        follow_redirects=True,
    )

    with app.app_context():
        retro = Retro.query.filter_by(title="Team Retro").first()

    response = auth_client.post(
        f"/retro/{retro.id}/cards",
        data={"category": "went_well", "content": "CI pipeline is green!"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"CI pipeline is green!" in response.data

    with app.app_context():
        card = RetroCard.query.filter_by(content="CI pipeline is green!").first()
        assert card is not None

    auth_client.post(f"/retro/cards/{card.id}/like", follow_redirects=True)
    with app.app_context():
        assert RetroLike.query.filter_by(card_id=card.id).count() == 1

    response = auth_client.post(
        f"/retro/cards/{card.id}/comment",
        data={"content": "Finally!"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Finally!" in response.data


def test_non_admin_cannot_create_retro(auth_client):
    response = auth_client.get("/retro/create", follow_redirects=True)
    assert b"Admin access required" in response.data


def test_share_link_and_guest_join(app):
    with app.app_context():
        admin_user = User.query.filter_by(username="livingdevops").first()
        retro = Retro(
            title="Shared Retro",
            description="Join us",
            created_by=admin_user.id,
            share_token="abc123sharetoken456789012345678",
        )
        db.session.add(retro)
        db.session.commit()
        token = retro.share_token

    guest_client = app.test_client()
    landing = guest_client.get(f"/retro/join/{token}")
    assert landing.status_code == 200
    assert b"Join as Guest" in landing.data
    assert b"Shared Retro" in landing.data

    response = guest_client.post(
        f"/retro/join/{token}/guest",
        data={"display_name": "Guest Dev"},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Shared Retro" in response.data

    with app.app_context():
        guest = User.query.filter_by(display_name="Guest Dev").first()
        assert guest is not None
        assert guest.is_guest is True
