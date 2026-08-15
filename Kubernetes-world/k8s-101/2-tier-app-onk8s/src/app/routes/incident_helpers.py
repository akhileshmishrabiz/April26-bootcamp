from datetime import datetime

from flask import abort
from flask_login import current_user
from sqlalchemy import func
from sqlalchemy.orm import joinedload

from app import db
from app.models.models import Incident, OnCallSchedule
from app.query_options import on_call_options


def next_incident_number(team_id):
    current_max = (
        db.session.query(func.max(Incident.incident_number))
        .filter_by(team_id=team_id)
        .scalar()
    )
    return (current_max or 0) + 1


def accessible_incidents_query(user_id=None):
    from app.routes.team_helpers import user_team_ids

    user_id = user_id or current_user.id
    team_ids = user_team_ids(user_id)
    if not team_ids:
        return Incident.query.filter(Incident.id == -1)
    return Incident.query.filter(Incident.team_id.in_(team_ids))


def get_incident_for_user(incident_id, user_id=None):
    from app.routes.team_helpers import user_is_team_member

    incident = Incident.query.get_or_404(incident_id)
    user_id = user_id or current_user.id
    if not user_is_team_member(incident.team_id, user_id):
        abort(403)
    return incident


def current_on_call(team_id, role="primary", at=None):
    at = at or datetime.utcnow()
    return (
        OnCallSchedule.query.filter(
            OnCallSchedule.team_id == team_id,
            OnCallSchedule.role == role,
            OnCallSchedule.start_at <= at,
            OnCallSchedule.end_at > at,
        )
        .options(*on_call_options())
        .order_by(OnCallSchedule.start_at.desc())
        .first()
    )


def log_incident_event(incident, user_id, event_type, description):
    from app.models.models import IncidentEvent

    event = IncidentEvent(
        incident_id=incident.id,
        user_id=user_id,
        event_type=event_type,
        description=description,
    )
    db.session.add(event)
    return event
