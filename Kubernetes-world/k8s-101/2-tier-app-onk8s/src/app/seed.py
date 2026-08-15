import json
import os
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from sqlalchemy import inspect, text, func

from app import db
from app.models.models import (
    Retro,
    RetroCard,
    RetroParticipant,
    Subtask,
    Team,
    TeamMember,
    Ticket,
    TicketComment,
    User,
    Incident,
    IncidentEvent,
    Postmortem,
    PostmortemActionItem,
    SpeakWheel,
    SpeakWheelName,
    OnCallSchedule,
)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
ADMINS_FILE = DATA_DIR / "admins.json"
RETROS_FILE = DATA_DIR / "devops_retros.json"
TICKETS_FILE = DATA_DIR / "devops_tickets.json"
TEAMS_FILE = DATA_DIR / "devops_teams.json"
INCIDENTS_FILE = DATA_DIR / "devops_incidents.json"
WHEELS_FILE = DATA_DIR / "devops_wheels.json"

# Primary admin — kept for tests and backwards compatibility
ADMIN_EMAIL = "livingdevops@gmail.com"
ADMIN_USERNAME = "livingdevops"


def _load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _resolve_password(entry):
    env_key = entry.get("password_env")
    if env_key:
        env_value = os.getenv(env_key)
        if env_value:
            return env_value
    return entry["password"]


def load_admins():
    return _load_json(ADMINS_FILE)["admins"]


def load_devops_retros():
    return _load_json(RETROS_FILE)["retros"]


def load_devops_tickets():
    return _load_json(TICKETS_FILE)["tickets"]


def load_devops_teams():
    return _load_json(TEAMS_FILE)["teams"]


def load_devops_incidents():
    return _load_json(INCIDENTS_FILE)


def load_devops_wheels():
    return _load_json(WHEELS_FILE)


def seed_admin_users():
    for entry in load_admins():
        admin = User.query.filter_by(email=entry["email"]).first()
        password = _resolve_password(entry)

        if admin is None:
            admin = User(
                username=entry["username"],
                email=entry["email"],
                is_admin=True,
            )
            admin.set_password(password)
            db.session.add(admin)
        else:
            admin.is_admin = True
            if admin.username != entry["username"]:
                admin.username = entry["username"]

    db.session.commit()


def seed_admin_user():
    """Backwards-compatible alias used by tests and docs."""
    seed_admin_users()


def seed_devops_retros():
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return

    for retro_data in load_devops_retros():
        existing = Retro.query.filter_by(title=retro_data["title"]).first()
        if existing is not None:
            continue

        retro = Retro(
            title=retro_data["title"],
            description=retro_data.get("description"),
            created_by=admin.id,
            share_token=retro_data.get("share_token") or uuid.uuid4().hex,
            status="open",
        )
        db.session.add(retro)
        db.session.flush()

        db.session.add(RetroParticipant(retro_id=retro.id, user_id=admin.id))

        for card_data in retro_data.get("cards", []):
            author = User.query.filter_by(username=card_data["author"]).first()
            if author is None:
                author = admin

            db.session.add(
                RetroCard(
                    retro_id=retro.id,
                    category=card_data["category"],
                    content=card_data["content"],
                    author_id=author.id,
                )
            )

    db.session.commit()


def _user_by_username(username):
    if not username:
        return None
    return User.query.filter_by(username=username).first()


def seed_devops_teams():
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return {}

    team_by_key = {}
    for team_data in load_devops_teams():
        project_key = team_data["project_key"]
        team = Team.query.filter_by(project_key=project_key).first()
        if team is None:
            owner = _user_by_username(team_data.get("owner")) or admin
            team = Team(
                name=team_data["name"],
                description=team_data.get("description"),
                project_key=project_key,
                created_by=owner.id,
            )
            db.session.add(team)
            db.session.flush()

        team_by_key[project_key] = team

        member_usernames = team_data.get("members", [])
        if team_data.get("owner") and team_data["owner"] not in member_usernames:
            member_usernames = [team_data["owner"]] + member_usernames

        for username in member_usernames:
            user = _user_by_username(username)
            if user is None:
                continue
            role = "owner" if username == team_data.get("owner") else "member"
            existing = TeamMember.query.filter_by(
                team_id=team.id, user_id=user.id
            ).first()
            if existing is None:
                db.session.add(TeamMember(team_id=team.id, user_id=user.id, role=role))
            elif role == "owner" and existing.role != "owner":
                existing.role = "owner"

    db.session.commit()
    return team_by_key


def seed_devops_tickets(team_by_key=None):
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return

    dev_team = None
    if team_by_key:
        dev_team = team_by_key.get("DEV")
    if dev_team is None:
        dev_team = Team.query.filter_by(project_key="DEV").first()
    if dev_team is None:
        return

    for ticket_data in load_devops_tickets():
        existing = Ticket.query.filter_by(
            team_id=dev_team.id,
            ticket_number=ticket_data["ticket_number"],
        ).first()
        if existing is not None:
            continue

        reporter = _user_by_username(ticket_data.get("reporter")) or admin
        assignee = _user_by_username(ticket_data.get("assignee"))

        ticket = Ticket(
            team_id=dev_team.id,
            ticket_number=ticket_data["ticket_number"],
            title=ticket_data["title"],
            description=ticket_data.get("description"),
            status=ticket_data.get("status", "todo"),
            priority=ticket_data.get("priority", "medium"),
            issue_type=ticket_data.get("issue_type", "task"),
            reporter_id=reporter.id,
            assignee_id=assignee.id if assignee else None,
        )
        db.session.add(ticket)
        db.session.flush()

        for comment_data in ticket_data.get("comments", []):
            author = _user_by_username(comment_data.get("author")) or admin
            db.session.add(
                TicketComment(
                    ticket_id=ticket.id,
                    user_id=author.id,
                    content=comment_data["content"],
                )
            )

        for subtask_data in ticket_data.get("subtasks", []):
            sub_assignee = _user_by_username(subtask_data.get("assignee"))
            subtask = Subtask(
                ticket_id=ticket.id,
                title=subtask_data["title"],
                description=subtask_data.get("description"),
                status=subtask_data.get("status", "todo"),
                assignee_id=sub_assignee.id if sub_assignee else None,
            )
            db.session.add(subtask)
            db.session.flush()

            for comment_data in subtask_data.get("comments", []):
                author = _user_by_username(comment_data.get("author")) or admin
                db.session.add(
                    TicketComment(
                        ticket_id=ticket.id,
                        subtask_id=subtask.id,
                        user_id=author.id,
                        content=comment_data["content"],
                    )
                )

    db.session.commit()


def seed_devops_incidents(team_by_key=None):
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return

    dev_team = None
    if team_by_key:
        dev_team = team_by_key.get("DEV")
    if dev_team is None:
        dev_team = Team.query.filter_by(project_key="DEV").first()
    if dev_team is None:
        return

    data = load_devops_incidents()
    now = datetime.utcnow()

    for inc_data in data.get("incidents", []):
        existing = Incident.query.filter_by(
            team_id=dev_team.id,
            incident_number=inc_data["incident_number"],
        ).first()
        if existing is not None:
            continue

        reporter = _user_by_username(inc_data.get("reporter")) or admin
        commander = _user_by_username(inc_data.get("commander"))
        on_call = _user_by_username(inc_data.get("on_call"))

        detected_at = now
        if "detected_at_offset_hours" in inc_data:
            detected_at = now + timedelta(hours=inc_data["detected_at_offset_hours"])
        elif "detected_at_offset_minutes" in inc_data:
            detected_at = now + timedelta(
                minutes=inc_data["detected_at_offset_minutes"]
            )

        def _offset_time(minutes_key):
            if minutes_key not in inc_data:
                return None
            return now + timedelta(minutes=inc_data[minutes_key])

        ticket = None
        if inc_data.get("ticket_number"):
            ticket = Ticket.query.filter_by(
                team_id=dev_team.id,
                ticket_number=inc_data["ticket_number"],
            ).first()

        incident = Incident(
            team_id=dev_team.id,
            incident_number=inc_data["incident_number"],
            title=inc_data["title"],
            summary=inc_data.get("summary"),
            severity=inc_data.get("severity", "sev3"),
            status=inc_data.get("status", "triggered"),
            service_name=inc_data.get("service_name"),
            customer_impact=inc_data.get("customer_impact"),
            runbook_url=inc_data.get("runbook_url"),
            reporter_id=reporter.id,
            commander_id=commander.id if commander else None,
            on_call_user_id=on_call.id if on_call else None,
            ticket_id=ticket.id if ticket else None,
            detected_at=detected_at,
            acknowledged_at=_offset_time("acknowledged_at_offset_minutes"),
            mitigated_at=_offset_time("mitigated_at_offset_minutes"),
            resolved_at=_offset_time("resolved_at_offset_minutes"),
        )
        db.session.add(incident)
        db.session.flush()

        for event_data in inc_data.get("events", []):
            author = _user_by_username(event_data.get("author")) or admin
            event_time = now
            if "offset_minutes" in event_data:
                event_time = now + timedelta(minutes=event_data["offset_minutes"])
            event = IncidentEvent(
                incident_id=incident.id,
                user_id=author.id,
                event_type=event_data.get("event_type", "note"),
                description=event_data["description"],
                created_at=event_time,
            )
            db.session.add(event)

        pm_data = inc_data.get("postmortem")
        if pm_data:
            postmortem = Postmortem(
                incident_id=incident.id,
                title=pm_data.get("title", f"Postmortem: {incident.title}"),
                status=pm_data.get("status", "draft"),
                summary=pm_data.get("summary"),
                impact=pm_data.get("impact"),
                root_cause=pm_data.get("root_cause"),
                contributing_factors=pm_data.get("contributing_factors"),
                detection_analysis=pm_data.get("detection_analysis"),
                resolution_summary=pm_data.get("resolution_summary"),
                what_went_well=pm_data.get("what_went_well"),
                what_went_wrong=pm_data.get("what_went_wrong"),
                lessons_learned=pm_data.get("lessons_learned"),
                timeline_summary=pm_data.get("timeline_summary"),
                created_by=admin.id,
                published_at=(
                    now - timedelta(days=1)
                    if pm_data.get("status") == "published"
                    else None
                ),
            )
            db.session.add(postmortem)
            db.session.flush()

            for item_data in pm_data.get("action_items", []):
                owner = _user_by_username(item_data.get("assignee"))
                linked_ticket = None
                if item_data.get("status") == "ticket_created" and item_data.get(
                    "ticket_title"
                ):
                    linked_ticket = Ticket(
                        team_id=dev_team.id,
                        ticket_number=(
                            db.session.query(func.max(Ticket.ticket_number))
                            .filter_by(team_id=dev_team.id)
                            .scalar()
                            or 0
                        )
                        + 1,
                        title=item_data["ticket_title"],
                        description=f"Action item from postmortem: {postmortem.title}",
                        status="todo",
                        priority="high",
                        issue_type="task",
                        reporter_id=admin.id,
                        assignee_id=owner.id if owner else None,
                    )
                    db.session.add(linked_ticket)
                    db.session.flush()

                db.session.add(
                    PostmortemActionItem(
                        postmortem_id=postmortem.id,
                        title=item_data["title"],
                        owner_id=owner.id if owner else None,
                        status=item_data.get("status", "open"),
                        ticket_id=linked_ticket.id if linked_ticket else None,
                    )
                )

    for schedule_data in data.get("on_call_schedules", []):
        team = team_by_key.get(schedule_data["team_key"]) if team_by_key else None
        if team is None:
            team = Team.query.filter_by(project_key=schedule_data["team_key"]).first()
        if team is None:
            continue

        user = _user_by_username(schedule_data.get("username"))
        if user is None:
            continue

        start_at = now + timedelta(days=schedule_data.get("start_offset_days", 0))
        end_at = now + timedelta(days=schedule_data.get("end_offset_days", 7))

        existing = OnCallSchedule.query.filter_by(
            team_id=team.id,
            user_id=user.id,
            role=schedule_data.get("role", "primary"),
            start_at=start_at,
        ).first()
        if existing is None:
            db.session.add(
                OnCallSchedule(
                    team_id=team.id,
                    user_id=user.id,
                    role=schedule_data.get("role", "primary"),
                    start_at=start_at,
                    end_at=end_at,
                )
            )

    db.session.commit()


def seed_devops_wheels(team_by_key=None):
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    if admin is None:
        return

    for wheel_data in load_devops_wheels().get("wheels", []):
        existing = SpeakWheel.query.filter_by(title=wheel_data["title"]).first()
        if existing is not None:
            continue

        team = None
        if wheel_data.get("team_key") and team_by_key:
            team = team_by_key.get(wheel_data["team_key"])
        if team is None and wheel_data.get("team_key"):
            team = Team.query.filter_by(project_key=wheel_data["team_key"]).first()

        wheel = SpeakWheel(
            title=wheel_data["title"],
            description=wheel_data.get("description"),
            mode=wheel_data.get("mode", "elimination"),
            share_token=wheel_data.get("share_token") or uuid.uuid4().hex,
            team_id=team.id if team else None,
            created_by=admin.id,
            status="open",
        )
        db.session.add(wheel)
        db.session.flush()

        names = list(wheel_data.get("names", []))
        if team and not names:
            for membership in TeamMember.query.filter_by(team_id=team.id).all():
                user = User.query.get(membership.user_id)
                if user and not user.is_guest:
                    names.append(user.label)

        for i, name in enumerate(names):
            db.session.add(
                SpeakWheelName(
                    wheel_id=wheel.id,
                    name=name,
                    color_index=i % 12,
                )
            )

    db.session.commit()


def backfill_ticket_teams():
    default_team = Team.query.filter_by(project_key="DEV").first()
    if default_team is None:
        return

    updated = Ticket.query.filter(Ticket.team_id.is_(None)).update(
        {Ticket.team_id: default_team.id}, synchronize_session=False
    )
    if updated:
        db.session.commit()


def is_devops_data_seeded():
    """Fast check so startup skips heavy JSON seeding when demo data exists."""
    return Team.query.filter_by(project_key="DEV").first() is not None


def run_devops_seed():
    team_by_key = seed_devops_teams()
    seed_devops_retros()
    seed_devops_tickets(team_by_key)
    seed_devops_incidents(team_by_key)
    seed_devops_wheels(team_by_key)
    backfill_ticket_teams()


def ensure_schema():
    """Add columns introduced after first deploy (create_all won't alter tables)."""
    inspector = inspect(db.engine)
    user_cols = {c["name"] for c in inspector.get_columns("user")}
    retro_cols = {c["name"] for c in inspector.get_columns("retro")}
    ticket_cols = (
        {c["name"] for c in inspector.get_columns("ticket")}
        if "ticket" in inspector.get_table_names()
        else set()
    )

    if "is_guest" not in user_cols:
        db.session.execute(
            text(
                'ALTER TABLE "user" ADD COLUMN is_guest BOOLEAN DEFAULT FALSE NOT NULL'
            )
        )
    if "display_name" not in user_cols:
        db.session.execute(
            text('ALTER TABLE "user" ADD COLUMN display_name VARCHAR(80)')
        )
    if "share_token" not in retro_cols:
        db.session.execute(text("ALTER TABLE retro ADD COLUMN share_token VARCHAR(32)"))
        db.session.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_retro_share_token ON retro (share_token)"
            )
        )
    if ticket_cols and "team_id" not in ticket_cols:
        db.session.execute(
            text("ALTER TABLE ticket ADD COLUMN team_id INTEGER REFERENCES team(id)")
        )
    if ticket_cols or "ticket" in inspector.get_table_names():
        db.session.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS uq_team_ticket_number ON ticket (team_id, ticket_number)"
            )
        )

    db.session.commit()

    if Retro.query.filter(
        (Retro.share_token.is_(None)) | (Retro.share_token == "")
    ).limit(1).first():
        for retro in Retro.query.filter(
            (Retro.share_token.is_(None)) | (Retro.share_token == "")
        ).all():
            retro.share_token = uuid.uuid4().hex
        db.session.commit()
