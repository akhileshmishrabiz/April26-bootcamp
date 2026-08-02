import os
import pytest

os.environ.setdefault("DB_LINK", "sqlite:///:memory:")

from app import create_app, db
from app.models.models import (
    User,
    Student,
    Attendance,
    Assignment,
    Retro,
    RetroCard,
    RetroLike,
    Ticket,
    Subtask,
    TicketComment,
    Team,
    TeamMember,
    Incident,
    Postmortem,
    OnCallSchedule,
    SpeakWheel,
    SpeakWheelName,
    SpeakWheelPick,
    GameScore,
    PlayerProfile,
)
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


def test_devops_retros_seeded(app):
    with app.app_context():
        retros = Retro.query.all()
        assert len(retros) >= 5
        titles = {r.title for r in retros}
        assert "ECS Day 9 — Terraform Ship Retro" in titles
        assert "Kubernetes Pod Crash Bingo" in titles

        ecs_retro = Retro.query.filter_by(
            title="ECS Day 9 — Terraform Ship Retro"
        ).first()
        assert ecs_retro.share_token is not None
        assert RetroCard.query.filter_by(retro_id=ecs_retro.id).count() >= 3


def test_regular_user_sees_seeded_retros(auth_client):
    response = auth_client.get("/retro", follow_redirects=True)
    assert response.status_code == 200
    assert b"ECS Day 9" in response.data
    assert b"No retros yet" not in response.data


def test_register_new_user(client, app):
    response = client.post(
        "/register",
        data={
            "username": "alice",
            "email": "alice@example.com",
            "password": "Secure99",
        },
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


def test_retro_ajax_like_and_comment(auth_client, admin_client, app):
    admin_client.post(
        "/retro/create",
        data={"title": "Ajax Retro", "description": ""},
        follow_redirects=True,
    )

    with app.app_context():
        retro = Retro.query.filter_by(title="Ajax Retro").first()

    auth_client.post(
        f"/retro/{retro.id}/cards",
        data={"category": "went_well", "content": "Hot reload works!"},
        follow_redirects=True,
    )

    with app.app_context():
        card = RetroCard.query.filter_by(content="Hot reload works!").first()

    headers = {"X-Requested-With": "XMLHttpRequest", "Accept": "application/json"}

    like_response = auth_client.post(
        f"/retro/cards/{card.id}/like",
        headers=headers,
    )
    assert like_response.status_code == 200
    like_data = like_response.get_json()
    assert like_data["ok"] is True
    assert like_data["like_count"] == 1
    assert like_data["liked_by_me"] is True

    comment_response = auth_client.post(
        f"/retro/cards/{card.id}/comment",
        data={"content": "No page reload!"},
        headers=headers,
    )
    assert comment_response.status_code == 200
    comment_data = comment_response.get_json()
    assert comment_data["ok"] is True
    assert "No page reload!" in comment_data["html"]

    card_response = auth_client.post(
        f"/retro/{retro.id}/cards",
        data={"category": "action_items", "content": "Ship more AJAX"},
        headers=headers,
    )
    assert card_response.status_code == 200
    card_data = card_response.get_json()
    assert card_data["ok"] is True
    assert "Ship more AJAX" in card_data["html"]
    assert card_data["category"] == "action_items"


def test_non_admin_cannot_create_retro(auth_client):
    response = auth_client.get("/retro/create", follow_redirects=True)
    assert b"Admin access required" in response.data


# ── Ticket tests ──────────────────────────────────────────────────────────────


def test_devops_teams_and_tickets_seeded(app):
    with app.app_context():
        team = Team.query.filter_by(project_key="DEV").first()
        assert team is not None
        assert TeamMember.query.filter_by(team_id=team.id).count() >= 2

        tickets = Ticket.query.filter_by(team_id=team.id).all()
        assert len(tickets) >= 6
        dev1 = Ticket.query.filter_by(team_id=team.id, ticket_number=1).first()
        assert dev1 is not None
        assert dev1.key == "DEV-1"
        assert dev1.subtasks
        assert TicketComment.query.filter_by(ticket_id=dev1.id).count() >= 2


def _create_team(client, name="Test Squad", project_key="TST"):
    return client.post(
        "/teams/create",
        data={"name": name, "project_key": project_key, "description": "Test team"},
        follow_redirects=True,
    )


def test_create_team_add_member_and_ticket(auth_client, app):
    response = _create_team(auth_client)
    assert response.status_code == 200
    assert b"Test Squad" in response.data

    with app.app_context():
        team = Team.query.filter_by(project_key="TST").first()
        assert team is not None
        team_id = team.id

    auth_client.post(
        f"/teams/{team_id}/members",
        data={
            "email": "member@bootcamp.local",
            "password": "MemberPass1",
            "username": "teammember",
        },
        follow_redirects=True,
    )

    response = auth_client.post(
        "/tickets/create",
        data={
            "team_id": team_id,
            "title": "Fix flaky deploy script",
            "description": "Sometimes hangs on docker push",
            "issue_type": "bug",
            "priority": "high",
            "status": "todo",
        },
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"TST-1" in response.data

    with app.app_context():
        ticket = Ticket.query.filter_by(title="Fix flaky deploy script").first()
        assert ticket is not None
        assert ticket.team_id == team_id
        ticket_id = ticket.id
        ticket_title = ticket.title
        member = User.query.filter_by(username="teammember").first()
        assert member is not None

    auth_client.post(
        f"/tickets/{ticket_id}/update",
        data={
            "title": ticket_title,
            "status": "todo",
            "priority": "high",
            "issue_type": "bug",
            "assignee_id": member.id,
        },
        follow_redirects=True,
    )
    auth_client.post(
        f"/tickets/{ticket_id}/subtasks",
        data={"title": "Add timeout to docker push step", "assignee_id": member.id},
        follow_redirects=True,
    )
    auth_client.post(
        f"/tickets/{ticket_id}/comments",
        data={"content": "Seen this twice on slow networks."},
        follow_redirects=True,
    )

    with app.app_context():
        ticket = Ticket.query.filter_by(title="Fix flaky deploy script").first()
        assert ticket.assignee_id == member.id
        assert Subtask.query.filter_by(ticket_id=ticket.id).count() == 1
        assert (
            TicketComment.query.filter_by(ticket_id=ticket.id, subtask_id=None).count()
            == 1
        )


def test_bulk_upload_team_members(auth_client, app):
    _create_team(auth_client, name="Bulk Squad", project_key="BLK")
    with app.app_context():
        team = Team.query.filter_by(project_key="BLK").first()
        team_id = team.id

    bulk_data = """email,password,username
bulk1@bootcamp.local,BulkPass1!,bulk1
bulk2@bootcamp.local,BulkPass2!,bulk2
"""
    response = auth_client.post(
        f"/teams/{team_id}/members/bulk",
        data={"bulk_data": bulk_data},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Imported 2 member" in response.data

    with app.app_context():
        assert User.query.filter_by(username="bulk1").first() is not None
        assert TeamMember.query.filter_by(team_id=team_id).count() == 3


def test_ticket_list_scoped_to_user_teams(app):
    with app.app_context():
        user = User(username="scopeduser", email="scoped@example.com")
        user.set_password("Password1")
        db.session.add(user)
        db.session.commit()

    user_client = app.test_client()
    user_client.post(
        "/login",
        data={"username": "scopeduser", "password": "Password1"},
    )
    _create_team(user_client, name="Private Squad", project_key="PRV")

    auth_response = user_client.get("/tickets")
    assert auth_response.status_code == 200
    assert b"ECS task fails health check" not in auth_response.data

    admin_client = app.test_client()
    admin_client.post(
        "/login",
        data={"username": "livingdevops", "password": "LivingDevops1!"},
    )
    admin_response = admin_client.get("/tickets")
    assert admin_response.status_code == 200
    assert b"ECS task fails health check" in admin_response.data


def test_ticket_list_and_filters(admin_client):
    response = admin_client.get("/tickets")
    assert response.status_code == 200
    assert b"ECS task fails health check" in response.data

    response = admin_client.get("/tickets?status=done")
    assert response.status_code == 200
    assert b"Prometheus metrics" in response.data


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


# ── Incident & Postmortem tests ───────────────────────────────────────────────


def test_devops_incidents_seeded(app):
    with app.app_context():
        team = Team.query.filter_by(project_key="DEV").first()
        assert team is not None
        incidents = Incident.query.filter_by(team_id=team.id).all()
        assert len(incidents) >= 3
        inc1 = Incident.query.filter_by(team_id=team.id, incident_number=1).first()
        assert inc1 is not None
        assert inc1.key == "DEV-INC-1"
        assert inc1.postmortem is not None
        assert len(inc1.events) >= 5
        assert OnCallSchedule.query.filter_by(team_id=team.id).count() >= 2


def test_incident_list_and_detail(admin_client):
    response = admin_client.get("/incidents")
    assert response.status_code == 200
    assert b"Production API 502" in response.data

    with admin_client.application.app_context():
        inc = Incident.query.filter_by(incident_number=1).first()
        inc_id = inc.id

    response = admin_client.get(f"/incidents/{inc_id}")
    assert response.status_code == 200
    assert b"Response Timeline" in response.data
    assert b"Postmortem" in response.data


def test_declare_incident_and_timeline(auth_client, app):
    _create_team(auth_client, name="SRE Squad", project_key="SRE")
    with app.app_context():
        team = Team.query.filter_by(project_key="SRE").first()

    response = auth_client.post(
        "/incidents/create",
        data={
            "team_id": team.id,
            "title": "Database latency spike",
            "summary": "P99 latency above 2s",
            "severity": "sev3",
            "service_name": "postgres",
        },
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"SRE-INC-1" in response.data

    with app.app_context():
        incident = Incident.query.filter_by(title="Database latency spike").first()
        assert incident is not None
        assert incident.status == "triggered"
        inc_id = incident.id

    auth_client.post(
        f"/incidents/{inc_id}/events",
        data={"event_type": "note", "description": "Checking slow query log"},
        follow_redirects=True,
    )
    auth_client.post(
        f"/incidents/{inc_id}/update",
        data={
            "title": "Database latency spike",
            "status": "investigating",
            "severity": "sev3",
        },
        follow_redirects=True,
    )

    with app.app_context():
        incident = db.session.get(Incident, inc_id)
        assert incident.status == "investigating"
        assert incident.acknowledged_at is not None
        assert len(incident.events) >= 3


def test_postmortem_flow(auth_client, app):
    _create_team(auth_client, name="PM Squad", project_key="PMX")
    with app.app_context():
        team = Team.query.filter_by(project_key="PMX").first()

    auth_client.post(
        "/incidents/create",
        data={
            "team_id": team.id,
            "title": "Cache stampede",
            "severity": "sev4",
        },
        follow_redirects=True,
    )
    with app.app_context():
        incident = Incident.query.filter_by(title="Cache stampede").first()
        inc_id = incident.id

    auth_client.post(
        f"/incidents/{inc_id}/update",
        data={"title": "Cache stampede", "status": "investigating", "severity": "sev4"},
        follow_redirects=True,
    )
    auth_client.post(
        f"/incidents/{inc_id}/update",
        data={"title": "Cache stampede", "status": "resolved", "severity": "sev4"},
        follow_redirects=True,
    )

    response = auth_client.post(
        "/postmortems/create",
        data={
            "incident_id": inc_id,
            "title": "Postmortem: Cache stampede",
            "root_cause": "TTL expired on hot keys simultaneously",
            "lessons_learned": "Add jitter to cache TTL",
        },
        query_string={"incident_id": inc_id},
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"Blameless postmortem" in response.data

    with app.app_context():
        incident = db.session.get(Incident, inc_id)
        assert incident.postmortem is not None
        pm_id = incident.postmortem.id

    auth_client.post(
        f"/postmortems/{pm_id}/action-items",
        data={"title": "Add cache TTL jitter"},
        follow_redirects=True,
    )
    with app.app_context():
        from app.models.models import PostmortemActionItem

        item = PostmortemActionItem.query.filter_by(postmortem_id=pm_id).first()
        assert item is not None
        item_id = item.id

    auth_client.post(
        f"/postmortems/action-items/{item_id}/promote",
        follow_redirects=True,
    )

    response = auth_client.get("/postmortems")
    assert response.status_code == 200


def test_simulate_alert(admin_client):
    response = admin_client.get("/incidents/simulate-alert", follow_redirects=True)
    assert response.status_code == 200
    assert b"Alert received" in response.data
    assert b"High error rate" in response.data


# ── Speak Wheel tests ─────────────────────────────────────────────────────────


def test_devops_wheel_seeded(app):
    with app.app_context():
        wheel = SpeakWheel.query.filter_by(
            title="Platform DevOps Standup — Who Speaks First?"
        ).first()
        assert wheel is not None
        assert wheel.share_token is not None
        assert SpeakWheelName.query.filter_by(wheel_id=wheel.id).count() >= 2


def test_create_wheel_add_names_and_spin(auth_client, app):
    response = auth_client.post(
        "/wheel/create",
        data={
            "title": "Class Call Wheel",
            "mode": "elimination",
            "names": "Alice\nBob\nCharlie\nDiana",
        },
        follow_redirects=True,
    )
    assert response.status_code == 200
    assert b"SPIN!" in response.data

    with app.app_context():
        wheel = SpeakWheel.query.filter_by(title="Class Call Wheel").first()
        assert wheel is not None
        assert SpeakWheelName.query.filter_by(wheel_id=wheel.id).count() == 4
        wheel_id = wheel.id

    headers = {"X-Requested-With": "XMLHttpRequest", "Accept": "application/json"}
    spin = auth_client.post(f"/wheel/{wheel_id}/spin", headers=headers)
    assert spin.status_code == 200
    data = spin.get_json()
    assert data["ok"] is True
    assert data["winner"]["name"] in {"Alice", "Bob", "Charlie", "Diana"}
    assert data["segment_count"] == 4

    with app.app_context():
        assert SpeakWheelPick.query.filter_by(wheel_id=wheel_id).count() == 1
        assert (
            SpeakWheelName.query.filter_by(wheel_id=wheel_id, status="spoken").count()
            == 1
        )


def test_wheel_watch_state_public(client, app):
    with app.app_context():
        wheel = SpeakWheel.query.filter_by(
            title="Platform DevOps Standup — Who Speaks First?"
        ).first()
        wheel_id = wheel.id

    response = client.get(f"/wheel/{wheel_id}/state")
    assert response.status_code == 200
    data = response.get_json()
    assert data["ok"] is True
    assert data["total"] >= 2
    assert len(data["active"]) >= 2

    watch = client.get(f"/wheel/watch/{wheel.share_token}")
    assert watch.status_code == 200
    assert b"speak-wheel-canvas" in watch.data


def test_wheel_bulk_add_names(auth_client, app):
    auth_client.post(
        "/wheel/create",
        data={"title": "Bulk Wheel", "mode": "repeat", "names": "One"},
        follow_redirects=True,
    )
    with app.app_context():
        wheel = SpeakWheel.query.filter_by(title="Bulk Wheel").first()
        wheel_id = wheel.id

    headers = {"X-Requested-With": "XMLHttpRequest", "Accept": "application/json"}
    response = auth_client.post(
        f"/wheel/{wheel_id}/names",
        data={"names": "Two\nThree\nFour"},
        headers=headers,
    )
    assert response.status_code == 200
    data = response.get_json()
    assert data["added"] == 3
    assert data["state"]["total"] == 4


# ── DevOps Games tests ────────────────────────────────────────────────────────


GAME_SLUGS = [
    "pipeline-puzzle",
    "incident-commander",
    "dockerfile-builder",
    "k8s-yaml-fixer",
    "log-detective",
    "deploy-rollback",
]


def test_games_requires_login(client):
    response = client.get("/games/")
    assert response.status_code == 302
    assert "/login" in response.location


def test_games_home_and_pages(auth_client):
    response = auth_client.get("/games/")
    assert response.status_code == 200
    assert b"On-Call Arcade" in response.data
    assert b"Daily Challenge" in response.data

    for slug in GAME_SLUGS:
        page = auth_client.get(f"/games/{slug}")
        assert page.status_code == 200, slug

    assert auth_client.get("/games/leaderboard").status_code == 200
    assert auth_client.get("/games/achievements").status_code == 200


def test_games_invalid_slug_returns_404(auth_client):
    response = auth_client.get("/games/not-a-real-game")
    assert response.status_code == 404


def test_games_submit_score_and_leaderboard(auth_client, app):
    headers = {"Content-Type": "application/json"}
    response = auth_client.post(
        "/games/api/score",
        json={"game_type": "pipeline_puzzle", "score": 600, "details": "pytest"},
        headers=headers,
    )
    assert response.status_code == 200
    data = response.get_json()
    assert data["ok"] is True
    assert data["score"] >= 600

    with app.app_context():
        user = User.query.filter_by(username="testuser").first()
        label = user.label
        assert GameScore.query.filter_by(player_name=label).count() >= 1
        assert PlayerProfile.query.filter_by(player_name=label).first() is not None

    lb = auth_client.get("/games/leaderboard")
    assert lb.status_code == 200
    assert label.encode() in lb.data

    api_lb = auth_client.get("/games/api/leaderboard")
    assert api_lb.status_code == 200
    assert len(api_lb.get_json()) >= 1

