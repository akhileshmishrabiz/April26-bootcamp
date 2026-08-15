from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required
from sqlalchemy import func, or_

from app import db
from app.models.models import (
    SUBTASK_STATUSES,
    TICKET_PRIORITIES,
    TICKET_STATUSES,
    TICKET_TYPES,
    Subtask,
    Ticket,
    TicketActivity,
    TicketComment,
)
from app.routes.helpers import full_account_required
from app.routes.team_helpers import (
    accessible_tickets_query,
    get_team_for_user,
    get_ticket_for_user,
    next_ticket_number,
    team_member_users,
    team_member_users_for_teams,
    user_team_ids,
    user_teams,
    validate_assignee_for_team,
)
from app.query_options import ticket_list_options

tickets_bp = Blueprint("tickets", __name__, url_prefix="/tickets")


@tickets_bp.before_request
@full_account_required
def require_full_account():
    pass


def _apply_ticket_filters(query):
    status = request.args.get("status", "").strip()
    priority = request.args.get("priority", "").strip()
    assignee = request.args.get("assignee", "").strip()
    issue_type = request.args.get("type", "").strip()
    team_id = request.args.get("team_id", "").strip()
    search = request.args.get("q", "").strip()

    if team_id.isdigit():
        query = query.filter(Ticket.team_id == int(team_id))

    if status in TICKET_STATUSES:
        query = query.filter(Ticket.status == status)
    if priority in TICKET_PRIORITIES:
        query = query.filter(Ticket.priority == priority)
    if issue_type in TICKET_TYPES:
        query = query.filter(Ticket.issue_type == issue_type)
    if assignee == "me":
        query = query.filter(Ticket.assignee_id == current_user.id)
    elif assignee == "unassigned":
        query = query.filter(Ticket.assignee_id.is_(None))
    elif assignee.isdigit():
        query = query.filter(Ticket.assignee_id == int(assignee))
    if search:
        like = f"%{search}%"
        query = query.filter(
            or_(
                Ticket.title.ilike(like),
                Ticket.description.ilike(like),
            )
        )
    return query


def _status_counts(base_query, status_keys):
    rows = (
        base_query.with_entities(Ticket.status, func.count(Ticket.id))
        .group_by(Ticket.status)
        .all()
    )
    counts = {key: 0 for key in status_keys}
    for status, count in rows:
        if status in counts:
            counts[status] = count
    return counts, sum(counts.values())


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


@tickets_bp.route("")
@login_required
def list_tickets():
    teams = user_teams()
    if not teams:
        return render_template(
            "tickets/list.html",
            tickets=[],
            teams=[],
            users=[],
            statuses=TICKET_STATUSES,
            priorities=TICKET_PRIORITIES,
            types=TICKET_TYPES,
            status_counts={key: 0 for key in TICKET_STATUSES},
            total_ticket_count=0,
            filters={
                "status": request.args.get("status", ""),
                "priority": request.args.get("priority", ""),
                "assignee": request.args.get("assignee", ""),
                "type": request.args.get("type", ""),
                "team_id": request.args.get("team_id", ""),
                "q": request.args.get("q", ""),
            },
            no_teams=True,
        )

    base_query = accessible_tickets_query()
    query = _apply_ticket_filters(base_query)
    tickets = (
        query.options(*ticket_list_options())
        .order_by(Ticket.updated_at.desc())
        .all()
    )

    status_counts, total_ticket_count = _status_counts(base_query, TICKET_STATUSES)

    team_id = request.args.get("team_id", "").strip()
    my_team_ids = set(user_team_ids())
    assignee_users = []
    if team_id.isdigit() and int(team_id) in my_team_ids:
        assignee_users = team_member_users(int(team_id))
    if not assignee_users:
        assignee_users = team_member_users_for_teams([team.id for team in teams])

    return render_template(
        "tickets/list.html",
        tickets=tickets,
        teams=teams,
        users=assignee_users,
        statuses=TICKET_STATUSES,
        priorities=TICKET_PRIORITIES,
        types=TICKET_TYPES,
        status_counts=status_counts,
        total_ticket_count=total_ticket_count,
        filters={
            "status": request.args.get("status", ""),
            "priority": request.args.get("priority", ""),
            "assignee": request.args.get("assignee", ""),
            "type": request.args.get("type", ""),
            "team_id": team_id,
            "q": request.args.get("q", ""),
        },
        no_teams=False,
    )


@tickets_bp.route("/create", methods=["GET", "POST"])
@login_required
def create_ticket():
    teams = user_teams()
    if not teams:
        flash("Create or join a team before creating tickets.", "error")
        return redirect(url_for("teams.create_team"))

    if request.method == "POST":
        title = request.form.get("title", "").strip()
        description = request.form.get("description", "").strip()
        status = request.form.get("status", "todo")
        priority = request.form.get("priority", "medium")
        issue_type = request.form.get("issue_type", "task")
        assignee_id_raw = request.form.get("assignee_id", "").strip()
        team_id_raw = request.form.get("team_id", "").strip()

        if not title:
            flash("Ticket title is required.", "error")
            return redirect(url_for("tickets.create_ticket", team_id=team_id_raw))

        if not team_id_raw.isdigit():
            flash("Select a team for this ticket.", "error")
            return redirect(url_for("tickets.create_ticket"))

        team = get_team_for_user(int(team_id_raw))

        if status not in TICKET_STATUSES:
            status = "todo"
        if priority not in TICKET_PRIORITIES:
            priority = "medium"
        if issue_type not in TICKET_TYPES:
            issue_type = "task"

        assignee_id = int(assignee_id_raw) if assignee_id_raw.isdigit() else None
        if assignee_id and validate_assignee_for_team(team.id, assignee_id) is False:
            flash("Assignee must be a member of the selected team.", "error")
            return redirect(url_for("tickets.create_ticket", team_id=team.id))

        ticket = Ticket(
            team_id=team.id,
            ticket_number=next_ticket_number(team.id),
            title=title,
            description=description or None,
            status=status,
            priority=priority,
            issue_type=issue_type,
            reporter_id=current_user.id,
            assignee_id=assignee_id,
        )
        db.session.add(ticket)
        db.session.commit()

        flash(f"Ticket {ticket.key} created.", "success")
        return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))

    selected_team, _ = _selected_team(request.args.get("team_id", ""))
    members = team_member_users(selected_team.id)

    return render_template(
        "tickets/create.html",
        teams=teams,
        selected_team=selected_team,
        users=members,
        statuses=TICKET_STATUSES,
        priorities=TICKET_PRIORITIES,
        types=TICKET_TYPES,
    )


def _log_ticket_activity(
    ticket, activity_type, field_name=None, old_value=None, new_value=None, content=None
):
    db.session.add(
        TicketActivity(
            ticket_id=ticket.id,
            user_id=current_user.id,
            activity_type=activity_type,
            field_name=field_name,
            old_value=old_value,
            new_value=new_value,
            content=content,
        )
    )


@tickets_bp.route("/<int:ticket_id>")
@login_required
def view_ticket(ticket_id):
    ticket = get_ticket_for_user(ticket_id)
    ticket_comments = (
        TicketComment.query.filter_by(ticket_id=ticket.id, subtask_id=None)
        .order_by(TicketComment.created_at.asc())
        .all()
    )
    activities = (
        TicketActivity.query.filter_by(ticket_id=ticket.id)
        .order_by(TicketActivity.created_at.asc())
        .all()
    )
    timeline = []
    for comment in ticket_comments:
        timeline.append(
            {"type": "comment", "item": comment, "created_at": comment.created_at}
        )
    for activity in activities:
        timeline.append(
            {"type": "activity", "item": activity, "created_at": activity.created_at}
        )
    timeline.sort(key=lambda x: x["created_at"])

    linked_incident = None
    from app.models.models import Incident

    linked_incident = Incident.query.filter_by(ticket_id=ticket.id).first()

    return render_template(
        "tickets/detail.html",
        ticket=ticket,
        ticket_comments=ticket_comments,
        timeline=timeline,
        linked_incident=linked_incident,
        users=team_member_users(ticket.team_id),
        statuses=TICKET_STATUSES,
        priorities=TICKET_PRIORITIES,
        types=TICKET_TYPES,
        subtask_statuses=SUBTASK_STATUSES,
    )


@tickets_bp.route("/<int:ticket_id>/update", methods=["POST"])
@login_required
def update_ticket(ticket_id):
    ticket = get_ticket_for_user(ticket_id)

    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    status = request.form.get("status", ticket.status)
    priority = request.form.get("priority", ticket.priority)
    issue_type = request.form.get("issue_type", ticket.issue_type)
    assignee_id_raw = request.form.get("assignee_id", "").strip()

    if title:
        ticket.title = title
    ticket.description = description or None

    if status in TICKET_STATUSES and status != ticket.status:
        _log_ticket_activity(
            ticket,
            "status_change",
            "status",
            TICKET_STATUSES[ticket.status]["label"],
            TICKET_STATUSES[status]["label"],
        )
        ticket.status = status
    if priority in TICKET_PRIORITIES and priority != ticket.priority:
        _log_ticket_activity(
            ticket,
            "field_change",
            "priority",
            TICKET_PRIORITIES[ticket.priority]["label"],
            TICKET_PRIORITIES[priority]["label"],
        )
        ticket.priority = priority
    if issue_type in TICKET_TYPES and issue_type != ticket.issue_type:
        _log_ticket_activity(
            ticket,
            "field_change",
            "type",
            TICKET_TYPES[ticket.issue_type]["label"],
            TICKET_TYPES[issue_type]["label"],
        )
        ticket.issue_type = issue_type

    old_assignee = ticket.assignee.label if ticket.assignee else "Unassigned"
    assignee_id = int(assignee_id_raw) if assignee_id_raw.isdigit() else None
    if assignee_id and validate_assignee_for_team(ticket.team_id, assignee_id) is False:
        flash("Assignee must be a member of this ticket's team.", "error")
        return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))

    new_assignee = "Unassigned"
    if assignee_id:
        from app.models.models import User

        user = User.query.get(assignee_id)
        new_assignee = user.label if user else "Unassigned"
    if (ticket.assignee_id or None) != assignee_id:
        _log_ticket_activity(
            ticket, "field_change", "assignee", old_assignee, new_assignee
        )
    ticket.assignee_id = assignee_id

    db.session.commit()
    flash(f"{ticket.key} updated.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))


@tickets_bp.route("/<int:ticket_id>/comments", methods=["POST"])
@login_required
def add_ticket_comment(ticket_id):
    ticket = get_ticket_for_user(ticket_id)
    content = request.form.get("content", "").strip()

    if not content:
        flash("Comment cannot be empty.", "error")
        return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))

    db.session.add(
        TicketComment(ticket_id=ticket.id, user_id=current_user.id, content=content)
    )
    db.session.commit()
    flash("Comment added.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))


@tickets_bp.route("/<int:ticket_id>/subtasks", methods=["POST"])
@login_required
def add_subtask(ticket_id):
    ticket = get_ticket_for_user(ticket_id)
    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    assignee_id_raw = request.form.get("assignee_id", "").strip()

    if not title:
        flash("Subtask title is required.", "error")
        return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))

    assignee_id = int(assignee_id_raw) if assignee_id_raw.isdigit() else None
    if assignee_id and validate_assignee_for_team(ticket.team_id, assignee_id) is False:
        flash("Assignee must be a member of this ticket's team.", "error")
        return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))

    subtask = Subtask(
        ticket_id=ticket.id,
        title=title,
        description=description or None,
        assignee_id=assignee_id,
    )
    db.session.add(subtask)
    db.session.commit()
    flash("Subtask added.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=ticket.id))


@tickets_bp.route("/subtasks/<int:subtask_id>/update", methods=["POST"])
@login_required
def update_subtask(subtask_id):
    subtask = Subtask.query.get_or_404(subtask_id)
    get_ticket_for_user(subtask.ticket_id)

    title = request.form.get("title", "").strip()
    status = request.form.get("status", subtask.status)
    assignee_id_raw = request.form.get("assignee_id", "").strip()

    if title:
        subtask.title = title
    if status in SUBTASK_STATUSES:
        subtask.status = status

    assignee_id = int(assignee_id_raw) if assignee_id_raw.isdigit() else None
    if (
        assignee_id
        and validate_assignee_for_team(subtask.ticket.team_id, assignee_id) is False
    ):
        flash("Assignee must be a member of this ticket's team.", "error")
        return redirect(url_for("tickets.view_ticket", ticket_id=subtask.ticket_id))

    subtask.assignee_id = assignee_id

    db.session.commit()
    flash("Subtask updated.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=subtask.ticket_id))


@tickets_bp.route("/subtasks/<int:subtask_id>/comments", methods=["POST"])
@login_required
def add_subtask_comment(subtask_id):
    subtask = Subtask.query.get_or_404(subtask_id)
    get_ticket_for_user(subtask.ticket_id)
    content = request.form.get("content", "").strip()

    if not content:
        flash("Comment cannot be empty.", "error")
        return redirect(url_for("tickets.view_ticket", ticket_id=subtask.ticket_id))

    db.session.add(
        TicketComment(
            ticket_id=subtask.ticket_id,
            subtask_id=subtask.id,
            user_id=current_user.id,
            content=content,
        )
    )
    db.session.commit()
    flash("Subtask comment added.", "success")
    return redirect(url_for("tickets.view_ticket", ticket_id=subtask.ticket_id))


@tickets_bp.route("/subtasks/<int:subtask_id>/toggle", methods=["POST"])
@login_required
def toggle_subtask(subtask_id):
    subtask = Subtask.query.get_or_404(subtask_id)
    get_ticket_for_user(subtask.ticket_id)
    subtask.status = "done" if subtask.status != "done" else "todo"
    db.session.commit()
    return redirect(url_for("tickets.view_ticket", ticket_id=subtask.ticket_id))
