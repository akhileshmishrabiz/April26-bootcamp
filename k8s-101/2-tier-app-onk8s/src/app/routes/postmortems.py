from datetime import datetime

from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import db
from app.models.models import (
    INCIDENT_STATUSES,
    POSTMORTEM_STATUSES,
    Incident,
    Postmortem,
    PostmortemActionItem,
    Ticket,
)
from app.routes.helpers import full_account_required
from app.routes.incident_helpers import get_incident_for_user, log_incident_event
from app.routes.team_helpers import (
    next_ticket_number,
    team_member_users,
    user_teams,
    validate_assignee_for_team,
)

postmortems_bp = Blueprint("postmortems", __name__, url_prefix="/postmortems")


@postmortems_bp.before_request
@full_account_required
def require_full_account():
    pass


def _accessible_postmortems():
    from app.routes.incident_helpers import accessible_incidents_query

    incident_ids = accessible_incidents_query().with_entities(Incident.id)
    return Postmortem.query.filter(Postmortem.incident_id.in_(incident_ids))


def get_postmortem_for_user(postmortem_id):
    postmortem = Postmortem.query.get_or_404(postmortem_id)
    get_incident_for_user(postmortem.incident_id)
    return postmortem


@postmortems_bp.route("")
@login_required
def list_postmortems():
    postmortems = _accessible_postmortems().order_by(Postmortem.updated_at.desc()).all()
    return render_template(
        "postmortems/list.html",
        postmortems=postmortems,
        statuses=POSTMORTEM_STATUSES,
    )


@postmortems_bp.route("/create", methods=["GET", "POST"])
@login_required
def create_postmortem():
    incident_id_raw = request.args.get("incident_id") or request.form.get(
        "incident_id", ""
    )
    if not incident_id_raw.isdigit():
        flash("Select an incident to write a postmortem.", "error")
        return redirect(url_for("incidents.list_incidents"))

    incident = get_incident_for_user(int(incident_id_raw))

    if incident.postmortem:
        flash("A postmortem already exists for this incident.", "error")
        return redirect(
            url_for("postmortems.view_postmortem", postmortem_id=incident.postmortem.id)
        )

    if incident.status not in ("resolved", "postmortem_pending", "closed"):
        flash("Resolve the incident before starting a postmortem.", "error")
        return redirect(url_for("incidents.view_incident", incident_id=incident.id))

    if request.method == "POST":
        title = request.form.get("title", "").strip()
        if not title:
            title = f"Postmortem: {incident.title}"

        postmortem = Postmortem(
            incident_id=incident.id,
            title=title,
            summary=request.form.get("summary", "").strip() or None,
            impact=request.form.get("impact", "").strip() or incident.customer_impact,
            root_cause=request.form.get("root_cause", "").strip() or None,
            contributing_factors=request.form.get("contributing_factors", "").strip()
            or None,
            detection_analysis=request.form.get("detection_analysis", "").strip()
            or None,
            resolution_summary=request.form.get("resolution_summary", "").strip()
            or None,
            what_went_well=request.form.get("what_went_well", "").strip() or None,
            what_went_wrong=request.form.get("what_went_wrong", "").strip() or None,
            lessons_learned=request.form.get("lessons_learned", "").strip() or None,
            timeline_summary=request.form.get("timeline_summary", "").strip() or None,
            created_by=current_user.id,
            status="draft",
        )
        db.session.add(postmortem)

        if incident.status == "resolved":
            incident.status = "postmortem_pending"
            log_incident_event(
                incident,
                current_user.id,
                "note",
                "Postmortem draft started — blameless review in progress.",
            )

        db.session.commit()
        flash(
            "Postmortem draft created. Fill in all sections before publishing.",
            "success",
        )
        return redirect(
            url_for("postmortems.view_postmortem", postmortem_id=postmortem.id)
        )

    timeline_lines = []
    for event in incident.events:
        ts = event.created_at.strftime("%H:%M UTC")
        meta = event.event_type.replace("_", " ").title()
        timeline_lines.append(f"{ts} — [{meta}] {event.description}")
    timeline_prefill = "\n".join(timeline_lines)

    return render_template(
        "postmortems/create.html",
        incident=incident,
        timeline_prefill=timeline_prefill,
    )


@postmortems_bp.route("/<int:postmortem_id>")
@login_required
def view_postmortem(postmortem_id):
    postmortem = get_postmortem_for_user(postmortem_id)
    incident = postmortem.incident
    return render_template(
        "postmortems/detail.html",
        postmortem=postmortem,
        incident=incident,
        users=team_member_users(incident.team_id),
        statuses=POSTMORTEM_STATUSES,
        incident_statuses=INCIDENT_STATUSES,
    )


@postmortems_bp.route("/<int:postmortem_id>/update", methods=["POST"])
@login_required
def update_postmortem(postmortem_id):
    postmortem = get_postmortem_for_user(postmortem_id)
    incident = postmortem.incident

    postmortem.title = (
        request.form.get("title", postmortem.title).strip() or postmortem.title
    )
    postmortem.summary = request.form.get("summary", "").strip() or None
    postmortem.impact = request.form.get("impact", "").strip() or None
    postmortem.root_cause = request.form.get("root_cause", "").strip() or None
    postmortem.contributing_factors = (
        request.form.get("contributing_factors", "").strip() or None
    )
    postmortem.detection_analysis = (
        request.form.get("detection_analysis", "").strip() or None
    )
    postmortem.resolution_summary = (
        request.form.get("resolution_summary", "").strip() or None
    )
    postmortem.what_went_well = request.form.get("what_went_well", "").strip() or None
    postmortem.what_went_wrong = request.form.get("what_went_wrong", "").strip() or None
    postmortem.lessons_learned = request.form.get("lessons_learned", "").strip() or None
    postmortem.timeline_summary = (
        request.form.get("timeline_summary", "").strip() or None
    )

    new_status = request.form.get("status", postmortem.status)
    if new_status in POSTMORTEM_STATUSES and new_status != postmortem.status:
        postmortem.status = new_status
        if new_status == "published" and not postmortem.published_at:
            postmortem.published_at = datetime.utcnow()
            log_incident_event(
                incident,
                current_user.id,
                "note",
                f"Postmortem published: {postmortem.title}",
            )
            if incident.status == "postmortem_pending":
                incident.status = "closed"
                log_incident_event(
                    incident,
                    current_user.id,
                    "status_change",
                    "Incident closed after postmortem publication.",
                )

    db.session.commit()
    flash("Postmortem saved.", "success")
    return redirect(url_for("postmortems.view_postmortem", postmortem_id=postmortem.id))


@postmortems_bp.route("/<int:postmortem_id>/action-items", methods=["POST"])
@login_required
def add_action_item(postmortem_id):
    postmortem = get_postmortem_for_user(postmortem_id)
    title = request.form.get("title", "").strip()
    owner_id_raw = request.form.get("owner_id", "").strip()
    due_date_raw = request.form.get("due_date", "").strip()

    if not title:
        flash("Action item title is required.", "error")
        return redirect(
            url_for("postmortems.view_postmortem", postmortem_id=postmortem.id)
        )

    owner_id = int(owner_id_raw) if owner_id_raw.isdigit() else None
    if (
        owner_id
        and validate_assignee_for_team(postmortem.incident.team_id, owner_id) is False
    ):
        flash("Owner must be a team member.", "error")
        return redirect(
            url_for("postmortems.view_postmortem", postmortem_id=postmortem.id)
        )

    due_date = None
    if due_date_raw:
        try:
            due_date = datetime.strptime(due_date_raw, "%Y-%m-%d").date()
        except ValueError:
            pass

    db.session.add(
        PostmortemActionItem(
            postmortem_id=postmortem.id,
            title=title,
            owner_id=owner_id,
            due_date=due_date,
        )
    )
    db.session.commit()
    flash("Action item added.", "success")
    return redirect(url_for("postmortems.view_postmortem", postmortem_id=postmortem.id))


@postmortems_bp.route("/action-items/<int:item_id>/promote", methods=["POST"])
@login_required
def promote_action_item(item_id):
    item = PostmortemActionItem.query.get_or_404(item_id)
    postmortem = get_postmortem_for_user(item.postmortem_id)
    incident = postmortem.incident

    if item.ticket_id:
        flash("This action item already has a linked ticket.", "error")
        return redirect(
            url_for("postmortems.view_postmortem", postmortem_id=postmortem.id)
        )

    ticket = Ticket(
        team_id=incident.team_id,
        ticket_number=next_ticket_number(incident.team_id),
        title=f"[PM] {item.title}",
        description=(
            f"Follow-up from postmortem: {postmortem.title}\n"
            f"Related incident: {incident.key}"
        ),
        status="todo",
        priority="high",
        issue_type="task",
        reporter_id=current_user.id,
        assignee_id=item.owner_id,
    )
    db.session.add(ticket)
    db.session.flush()

    item.ticket_id = ticket.id
    item.status = "ticket_created"
    db.session.commit()

    flash(f"Created ticket {ticket.key} from action item.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))
