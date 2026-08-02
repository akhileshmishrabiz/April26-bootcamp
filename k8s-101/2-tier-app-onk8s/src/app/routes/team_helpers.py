import csv
import io
import re

from flask import abort, g
from flask_login import current_user
from sqlalchemy import func

from app import db
from app.models.models import Team, TeamMember, Ticket, User
from app.routes.helpers import (
    unique_username_from_email,
    validate_email,
    validate_password,
)


def normalize_project_key(value):
    key = re.sub(r"[^A-Za-z0-9]", "", (value or "").upper())[:10]
    return key


def user_team_ids(user_id=None):
    user_id = user_id or current_user.id
    cache_key = f"user_team_ids_{user_id}"
    if hasattr(g, cache_key):
        return getattr(g, cache_key)

    team_ids = [
        membership.team_id
        for membership in TeamMember.query.filter_by(user_id=user_id).all()
    ]
    setattr(g, cache_key, team_ids)
    return team_ids


def user_teams(user_id=None):
    user_id = user_id or current_user.id
    cache_key = f"user_teams_{user_id}"
    if hasattr(g, cache_key):
        return getattr(g, cache_key)

    team_ids = user_team_ids(user_id)
    if not team_ids:
        teams = []
    else:
        teams = Team.query.filter(Team.id.in_(team_ids)).order_by(Team.name.asc()).all()
    setattr(g, cache_key, teams)
    return teams


def get_team_for_user(team_id, user_id=None):
    user_id = user_id or current_user.id
    membership = TeamMember.query.filter_by(team_id=team_id, user_id=user_id).first()
    if membership is None:
        abort(403)
    return membership.team


def is_team_owner(team_id, user_id=None):
    user_id = user_id or current_user.id
    membership = TeamMember.query.filter_by(
        team_id=team_id, user_id=user_id, role="owner"
    ).first()
    return membership is not None


def team_member_users(team_id):
    return (
        User.query.join(TeamMember, TeamMember.user_id == User.id)
        .filter(
            TeamMember.team_id == team_id,
            User.is_guest.is_(False),
        )
        .order_by(User.username.asc())
        .all()
    )


def team_member_users_for_teams(team_ids):
    if not team_ids:
        return []
    return (
        User.query.join(TeamMember, TeamMember.user_id == User.id)
        .filter(
            TeamMember.team_id.in_(team_ids),
            User.is_guest.is_(False),
        )
        .order_by(User.username.asc())
        .distinct(User.id)
        .all()
    )


def team_stats_for_teams(team_ids, user_id=None):
    """Batch member/ticket counts and current-user role for team list pages."""
    user_id = user_id or current_user.id
    if not team_ids:
        return {}, {}, {}

    member_counts = dict(
        db.session.query(TeamMember.team_id, func.count(TeamMember.id))
        .filter(TeamMember.team_id.in_(team_ids))
        .group_by(TeamMember.team_id)
        .all()
    )
    ticket_counts = dict(
        db.session.query(Ticket.team_id, func.count(Ticket.id))
        .filter(Ticket.team_id.in_(team_ids))
        .group_by(Ticket.team_id)
        .all()
    )
    memberships = {
        row.team_id: row
        for row in TeamMember.query.filter(
            TeamMember.team_id.in_(team_ids),
            TeamMember.user_id == user_id,
        ).all()
    }
    return member_counts, ticket_counts, memberships


def user_is_team_member(team_id, user_id):
    return (
        TeamMember.query.filter_by(team_id=team_id, user_id=user_id).first() is not None
    )


def validate_assignee_for_team(team_id, assignee_id):
    if not assignee_id:
        return None
    if not user_is_team_member(team_id, assignee_id):
        return False
    return True


def next_ticket_number(team_id):
    current_max = (
        db.session.query(func.max(Ticket.ticket_number))
        .filter_by(team_id=team_id)
        .scalar()
    )
    return (current_max or 0) + 1


def accessible_tickets_query(user_id=None):
    user_id = user_id or current_user.id
    team_ids = user_team_ids(user_id)
    if not team_ids:
        return Ticket.query.filter(Ticket.id == -1)
    return Ticket.query.filter(Ticket.team_id.in_(team_ids))


def get_ticket_for_user(ticket_id, user_id=None):
    ticket = Ticket.query.get_or_404(ticket_id)
    user_id = user_id or current_user.id
    if not user_is_team_member(ticket.team_id, user_id):
        abort(403)
    return ticket


def parse_bulk_member_rows(raw_text):
    rows = []
    errors = []

    if not raw_text or not raw_text.strip():
        return rows, ["No member data provided."]

    reader = csv.reader(io.StringIO(raw_text.strip()))
    for line_no, row in enumerate(reader, start=1):
        if not row or all(not cell.strip() for cell in row):
            continue

        cleaned = [cell.strip() for cell in row]
        if cleaned[0].lower() == "email":
            continue

        if len(cleaned) < 2:
            errors.append(f"Line {line_no}: need at least email and password.")
            continue

        email = cleaned[0]
        password = cleaned[1]
        username = cleaned[2] if len(cleaned) > 2 and cleaned[2] else None

        if not validate_email(email):
            errors.append(f"Line {line_no}: invalid email '{email}'.")
            continue
        if not validate_password(password):
            errors.append(
                f"Line {line_no}: password for '{email}' must be 8+ chars with upper, lower, and number."
            )
            continue

        rows.append({"email": email, "password": password, "username": username})

    if not rows and not errors:
        errors.append("No valid member rows found.")

    return rows, errors


def upsert_team_member(team, email, password, username=None, role="member"):
    user = User.query.filter_by(email=email).first()
    created = False

    if user is None:
        chosen_username = username or unique_username_from_email(email)
        if User.query.filter_by(username=chosen_username).first():
            return None, created, f"Username '{chosen_username}' is already taken."

        user = User(username=chosen_username, email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.flush()
        created = True
    elif username and user.username != username:
        return None, created, f"User {email} already exists with a different username."

    existing = TeamMember.query.filter_by(team_id=team.id, user_id=user.id).first()
    if existing is None:
        db.session.add(TeamMember(team_id=team.id, user_id=user.id, role=role))

    return user, created, None
