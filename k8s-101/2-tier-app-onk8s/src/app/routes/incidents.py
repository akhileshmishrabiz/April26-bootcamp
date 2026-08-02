from datetime import datetime

from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required
from sqlalchemy import func, or_

from app import db
from app.models.models import (
    INCIDENT_EVENT_TYPES,
    INCIDENT_SEVERITIES,
    INCIDENT_STATUSES,
    INCIDENT_STATUS_TRANSITIONS,
    Incident,
    Ticket,
)
from app.routes.helpers import full_account_required
from app.routes.incident_helpers import (
    accessible_incidents_query,
    current_on_call,
    get_incident_for_user,
    log_incident_event,
    next_incident_number,
)
from app.routes.team_helpers import (
    get_team_for_user,
    next_ticket_number,
    team_member_users,
    user_teams,
    validate_assignee_for_team,
)
from app.query_options import incident_list_options

incidents_bp = Blueprint("incidents", __name__, url_prefix="/incidents")


@incidents_bp.before_request
@full_account_required
def require_full_account():
    pass


def _apply_incident_filters(query):
    status = request.args.get("status", "").strip()
    severity = request.args.get("severity", "").strip()
    team_id = request.args.get("team_id", "").strip()
    search = request.args.get("q", "").strip()

    if team_id.isdigit():
        query = query.filter(Incident.team_id == int(team_id))
    if status in INCIDENT_STATUSES:
        query = query.filter(Incident.status == status)
    if severity in INCIDENT_SEVERITIES:
        query = query.filter(Incident.severity == severity)
    if search:
        like = f"%{search}%"
        query = query.filter(
            or_(
                Incident.title.ilike(like),
                Incident.summary.ilike(like),
                Incident.service_name.ilike(like),
            )
        )
    return query


def _status_counts(base_query, status_keys):
    rows = (
        base_query.with_entities(Incident.status, func.count(Incident.id))
        .group_by(Incident.status)
        .all()
    )
    counts = {key: 0 for key in status_keys}
    for status, count in rows:
        if status in counts:
            counts[status] = count
    return counts


def _selected_team(team_id_raw):
    teams = user_teams()
    if not teams:
        return None, teams
    if team_id_raw.isdigit():
        team_id = int(team_id_raw)
        for team in teams:
            if team.id == team_id:
                return team, teams
    return teams[0], teams


def _update_incident_timestamps(incident, new_status):
    now = datetime.utcnow()
    if new_status == "investigating" and not incident.acknowledged_at:
        incident.acknowledged_at = now
    if new_status in ("identified", "monitoring") and not incident.mitigated_at:
        incident.mitigated_at = now
    if new_status in ("resolved", "postmortem_pending", "closed"):
        if not incident.resolved_at:
            incident.resolved_at = now


@incidents_bp.route("")
@login_required
def list_incidents():
    teams = user_teams()
    if not teams:
        return render_template(
            "incidents/list.html",
            incidents=[],
            teams=[],
            severities=INCIDENT_SEVERITIES,
            statuses=INCIDENT_STATUSES,
            status_counts={key: 0 for key in INCIDENT_STATUSES},
            active_count=0,
            filters={"status": "", "severity": "", "team_id": "", "q": ""},
            no_teams=True,
            total_count=0,
        )

    base_query = accessible_incidents_query()
    query = _apply_incident_filters(base_query)
    incidents = (
        query.options(*incident_list_options())
        .order_by(Incident.updated_at.desc())
        .all()
    )

    status_counts = _status_counts(base_query, INCIDENT_STATUSES)
    active_count = sum(
        count
        for status, count in status_counts.items()
        if status not in ("resolved", "postmortem_pending", "closed")
    )

    return render_template(
        "incidents/list.html",
        incidents=incidents,
        teams=teams,
        severities=INCIDENT_SEVERITIES,
        statuses=INCIDENT_STATUSES,
        status_counts=status_counts,
        active_count=active_count,
        total_count=sum(status_counts.values()),
        filters={
            "status": request.args.get("status", ""),
            "severity": request.args.get("severity", ""),
            "team_id": request.args.get("team_id", ""),
            "q": request.args.get("q", ""),
        },
        no_teams=False,
    )


@incidents_bp.route("/create", methods=["GET", "POST"])
@login_required
def create_incident():
    teams = user_teams()
    if not teams:
        flash("Create or join a team before declaring incidents.", "error")
        return redirect(url_for("teams.create_team"))

    if request.method == "POST":
        title = request.form.get("title", "").strip()
        summary = request.form.get("summary", "").strip()
        severity = request.form.get("severity", "sev3")
        service_name = request.form.get("service_name", "").strip()
        customer_impact = request.form.get("customer_impact", "").strip()
        runbook_url = request.form.get("runbook_url", "").strip()
        team_id_raw = request.form.get("team_id", "").strip()
        commander_id_raw = request.form.get("commander_id", "").strip()
        on_call_id_raw = request.form.get("on_call_user_id", "").strip()

        if not title:
            flash("Incident title is required.", "error")
            return redirect(url_for("incidents.create_incident", team_id=team_id_raw))

        if not team_id_raw.isdigit():
            flash("Select a team for this incident.", "error")
            return redirect(url_for("incidents.create_incident"))

        team = get_team_for_user(int(team_id_raw))
        if severity not in INCIDENT_SEVERITIES:
            severity = "sev3"

        on_call_shift = current_on_call(team.id)
        on_call_user_id = (
            int(on_call_id_raw)
            if on_call_id_raw.isdigit()
            else (on_call_shift.user_id if on_call_shift else None)
        )
        commander_id = (
            int(commander_id_raw)
            if commander_id_raw.isdigit()
            else (on_call_user_id or current_user.id)
        )

        if (
            on_call_user_id
            and validate_assignee_for_team(team.id, on_call_user_id) is False
        ):
            flash("On-call assignee must be a team member.", "error")
            return redirect(url_for("incidents.create_incident", team_id=team.id))
        if commander_id and validate_assignee_for_team(team.id, commander_id) is False:
            flash("Incident commander must be a team member.", "error")
            return redirect(url_for("incidents.create_incident", team_id=team.id))

        incident = Incident(
            team_id=team.id,
            incident_number=next_incident_number(team.id),
            title=title,
            summary=summary or None,
            severity=severity,
            status="triggered",
            service_name=service_name or None,
            customer_impact=customer_impact or None,
            runbook_url=runbook_url or None,
            reporter_id=current_user.id,
            commander_id=commander_id,
            on_call_user_id=on_call_user_id,
            detected_at=datetime.utcnow(),
        )
        db.session.add(incident)
        db.session.flush()

        log_incident_event(
            incident,
            current_user.id,
            "created",
            f"Incident {incident.key} declared — {INCIDENT_SEVERITIES[severity]['label']}",
        )
        if request.form.get("source") == "alert":
            log_incident_event(
                incident,
                current_user.id,
                "alert",
                request.form.get(
                    "alert_message", "Automated alert triggered incident creation."
                ),
            )

        db.session.commit()
        flash(
            f"Incident {incident.key} declared. Page the on-call and start the timeline.",
            "success",
        )
        return redirect(url_for("incidents.view_incident", incident_id=incident.id))

    selected_team, _ = _selected_team(request.args.get("team_id", ""))
    members = team_member_users(selected_team.id)
    on_call = current_on_call(selected_team.id)
    secondary = current_on_call(selected_team.id, role="secondary")

    alert_prefill = {
        "title": request.args.get("title", ""),
        "summary": request.args.get("summary", ""),
        "severity": request.args.get("severity", "sev2"),
        "service_name": request.args.get("service_name", ""),
        "customer_impact": request.args.get("customer_impact", ""),
        "source": request.args.get("source", ""),
    }

    return render_template(
        "incidents/create.html",
        teams=teams,
        selected_team=selected_team,
        users=members,
        severities=INCIDENT_SEVERITIES,
        on_call=on_call,
        secondary=secondary,
        alert_prefill=alert_prefill,
    )


@incidents_bp.route("/simulate-alert")
@login_required
def simulate_alert():
    teams = user_teams()
    if not teams:
        flash("Join a team first to simulate alerts.", "error")
        return redirect(url_for("teams.list_teams"))

    team = teams[0]
    return redirect(
        url_for(
            "incidents.create_incident",
            team_id=team.id,
            source="alert",
            title="High error rate on /health endpoint",
            summary="Prometheus alert: http_requests_total{status=500} > 50/min for 5m. "
            "ALB target health checks failing on 3/4 ECS tasks.",
            severity="sev2",
            service_name="student-portal-api",
            customer_impact="Users may see 502 errors. Dashboard and login affected.",
        )
    )


@incidents_bp.route("/<int:incident_id>")
@login_required
def view_incident(incident_id):
    incident = get_incident_for_user(incident_id)
    allowed = incident.allowed_statuses()
    if incident.status in INCIDENT_STATUSES:
        allowed = [incident.status] + allowed

    return render_template(
        "incidents/detail.html",
        incident=incident,
        users=team_member_users(incident.team_id),
        severities=INCIDENT_SEVERITIES,
        statuses=INCIDENT_STATUSES,
        event_types=INCIDENT_EVENT_TYPES,
        allowed_statuses=allowed,
        status_transitions=INCIDENT_STATUS_TRANSITIONS,
    )


@incidents_bp.route("/<int:incident_id>/update", methods=["POST"])
@login_required
def update_incident(incident_id):
    incident = get_incident_for_user(incident_id)

    title = request.form.get("title", "").strip()
    summary = request.form.get("summary", "").strip()
    severity = request.form.get("severity", incident.severity)
    status = request.form.get("status", incident.status)
    service_name = request.form.get("service_name", "").strip()
    customer_impact = request.form.get("customer_impact", "").strip()
    runbook_url = request.form.get("runbook_url", "").strip()
    commander_id_raw = request.form.get("commander_id", "").strip()
    on_call_id_raw = request.form.get("on_call_user_id", "").strip()

    if title:
        incident.title = title
    incident.summary = summary or None
    incident.service_name = service_name or None
    incident.customer_impact = customer_impact or None
    incident.runbook_url = runbook_url or None

    if severity in INCIDENT_SEVERITIES and severity != incident.severity:
        old = INCIDENT_SEVERITIES[incident.severity]["label"]
        incident.severity = severity
        log_incident_event(
            incident,
            current_user.id,
            "severity_change",
            f"Severity changed from {old} to {INCIDENT_SEVERITIES[severity]['label']}",
        )

    if status in INCIDENT_STATUSES and status != incident.status:
        allowed = INCIDENT_STATUS_TRANSITIONS.get(incident.status, [])
        if status not in allowed:
            flash(
                f"Cannot move from {INCIDENT_STATUSES[incident.status]['label']} "
                f"to {INCIDENT_STATUSES[status]['label']}. "
                f"Allowed: {', '.join(INCIDENT_STATUSES[s]['label'] for s in allowed) or 'none'}.",
                "error",
            )
            return redirect(url_for("incidents.view_incident", incident_id=incident.id))

        old_status = INCIDENT_STATUSES[incident.status]["label"]
        incident.status = status
        _update_incident_timestamps(incident, status)
        log_incident_event(
            incident,
            current_user.id,
            "status_change",
            f"Status changed from {old_status} to {INCIDENT_STATUSES[status]['label']}",
        )
        if status == "resolved":
            log_incident_event(
                incident,
                current_user.id,
                "resolved",
                "Incident marked resolved. Schedule a blameless postmortem within 48 hours.",
            )

    commander_id = int(commander_id_raw) if commander_id_raw.isdigit() else None
    on_call_id = int(on_call_id_raw) if on_call_id_raw.isdigit() else None
    if (
        commander_id
        and validate_assignee_for_team(incident.team_id, commander_id) is False
    ):
        flash("Incident commander must be a team member.", "error")
        return redirect(url_for("incidents.view_incident", incident_id=incident.id))
    if on_call_id and validate_assignee_for_team(incident.team_id, on_call_id) is False:
        flash("On-call assignee must be a team member.", "error")
        return redirect(url_for("incidents.view_incident", incident_id=incident.id))

    incident.commander_id = commander_id
    incident.on_call_user_id = on_call_id

    db.session.commit()
    flash(f"{incident.key} updated.", "success")
    return redirect(url_for("incidents.view_incident", incident_id=incident.id))


@incidents_bp.route("/<int:incident_id>/events", methods=["POST"])
@login_required
def add_incident_event(incident_id):
    incident = get_incident_for_user(incident_id)
    event_type = request.form.get("event_type", "note")
    description = request.form.get("description", "").strip()

    if not description:
        flash("Timeline entry cannot be empty.", "error")
        return redirect(url_for("incidents.view_incident", incident_id=incident.id))

    if event_type not in INCIDENT_EVENT_TYPES:
        event_type = "note"

    log_incident_event(incident, current_user.id, event_type, description)
    db.session.commit()
    flash("Timeline updated.", "success")
    return redirect(url_for("incidents.view_incident", incident_id=incident.id))


@incidents_bp.route("/<int:incident_id>/create-ticket", methods=["POST"])
@login_required
def create_linked_ticket(incident_id):
    incident = get_incident_for_user(incident_id)

    if incident.ticket_id:
        flash("This incident already has a linked ticket.", "error")
        return redirect(url_for("incidents.view_incident", incident_id=incident.id))

    ticket = Ticket(
        team_id=incident.team_id,
        ticket_number=next_ticket_number(incident.team_id),
        title=f"[INC] {incident.title}",
        description=(
            f"Tracking ticket for incident {incident.key}.\n\n"
            f"{incident.summary or ''}\n\n"
            f"Customer impact: {incident.customer_impact or 'TBD'}"
        ),
        status="in_progress",
        priority="highest" if incident.severity in ("sev1", "sev2") else "high",
        issue_type="incident",
        reporter_id=current_user.id,
        assignee_id=incident.commander_id or incident.on_call_user_id,
    )
    db.session.add(ticket)
    db.session.flush()

    incident.ticket_id = ticket.id
    log_incident_event(
        incident,
        current_user.id,
        "note",
        f"Created tracking ticket {ticket.key}",
    )
    db.session.commit()

    flash(f"Created tracking ticket {ticket.key}.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))
