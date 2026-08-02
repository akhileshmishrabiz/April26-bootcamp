from flask import Blueprint, flash, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import db
from app.models.models import Team, TeamMember, User
from app.routes.helpers import full_account_required, validate_email, validate_password
from app.routes.team_helpers import (
    is_team_owner,
    normalize_project_key,
    parse_bulk_member_rows,
    team_stats_for_teams,
    upsert_team_member,
    user_teams,
)

teams_bp = Blueprint("teams", __name__, url_prefix="/teams")


@teams_bp.before_request
@full_account_required
def require_full_account():
    pass


@teams_bp.route("")
@login_required
def list_teams():
    teams = user_teams()
    team_ids = [team.id for team in teams]
    member_counts, ticket_counts, memberships = team_stats_for_teams(team_ids)
    team_cards = []
    for team in teams:
        membership = memberships.get(team.id)
        team_cards.append(
            {
                "team": team,
                "role": membership.role if membership else "member",
                "member_count": member_counts.get(team.id, 0),
                "ticket_count": ticket_counts.get(team.id, 0),
            }
        )

    return render_template("teams/list.html", team_cards=team_cards)


@teams_bp.route("/create", methods=["GET", "POST"])
@login_required
def create_team():
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        description = request.form.get("description", "").strip()
        project_key = normalize_project_key(request.form.get("project_key", ""))

        if not name:
            flash("Team name is required.", "error")
            return redirect(url_for("teams.create_team"))
        if len(project_key) < 2:
            flash(
                "Project key must be at least 2 characters (letters/numbers).", "error"
            )
            return redirect(url_for("teams.create_team"))
        if Team.query.filter_by(project_key=project_key).first():
            flash(f"Project key '{project_key}' is already in use.", "error")
            return redirect(url_for("teams.create_team"))

        team = Team(
            name=name,
            description=description or None,
            project_key=project_key,
            created_by=current_user.id,
        )
        db.session.add(team)
        db.session.flush()
        db.session.add(
            TeamMember(team_id=team.id, user_id=current_user.id, role="owner")
        )
        db.session.commit()

        flash(
            f"Team '{team.name}' created. Ticket keys will use {team.project_key}-1, {team.project_key}-2, …",
            "success",
        )
        return redirect(url_for("teams.view_team", team_id=team.id))

    return render_template("teams/create.html")


@teams_bp.route("/<int:team_id>")
@login_required
def view_team(team_id):
    from app.routes.team_helpers import get_team_for_user, team_member_users
    from app.routes.incident_helpers import current_on_call

    team = get_team_for_user(team_id)
    members = (
        TeamMember.query.filter_by(team_id=team.id)
        .join(User)
        .order_by(TeamMember.role.desc(), User.username.asc())
        .all()
    )
    is_owner = is_team_owner(team.id)

    return render_template(
        "teams/detail.html",
        team=team,
        members=members,
        is_owner=is_owner,
        team_members=team_member_users(team.id),
        on_call_primary=current_on_call(team.id),
        on_call_secondary=current_on_call(team.id, role="secondary"),
    )


@teams_bp.route("/<int:team_id>/members", methods=["POST"])
@login_required
def add_member(team_id):
    from app.routes.team_helpers import get_team_for_user

    team = get_team_for_user(team_id)
    if not is_team_owner(team.id):
        flash("Only team owners can add members.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    email = request.form.get("email", "").strip()
    password = request.form.get("password", "").strip()
    username = request.form.get("username", "").strip() or None

    if not email:
        flash("Email is required.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    if not validate_email(email):
        flash("Invalid email format.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    existing_user = User.query.filter_by(email=email).first()
    if existing_user is None:
        if not password:
            flash("Password is required when creating a new user.", "error")
            return redirect(url_for("teams.view_team", team_id=team.id))
        if not validate_password(password):
            flash(
                "Password must be at least 8 characters with uppercase, lowercase, and numbers.",
                "error",
            )
            return redirect(url_for("teams.view_team", team_id=team.id))

    user, created, error = upsert_team_member(team, email, password, username=username)
    if error:
        flash(error, "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    db.session.commit()
    if created:
        flash(f"Created account for {email} and added to the team.", "success")
    else:
        flash(f"{user.label} added to the team.", "success")
    return redirect(url_for("teams.view_team", team_id=team.id))


@teams_bp.route("/<int:team_id>/members/bulk", methods=["POST"])
@login_required
def bulk_add_members(team_id):
    from app.routes.team_helpers import get_team_for_user

    team = get_team_for_user(team_id)
    if not is_team_owner(team.id):
        flash("Only team owners can bulk-import members.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    raw_text = request.form.get("bulk_data", "")
    upload = request.files.get("bulk_file")
    if upload and upload.filename:
        raw_text = upload.read().decode("utf-8-sig")

    rows, errors = parse_bulk_member_rows(raw_text)
    if errors and not rows:
        for message in errors[:5]:
            flash(message, "error")
        if len(errors) > 5:
            flash(f"…and {len(errors) - 5} more errors.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    created_count = 0
    added_count = 0
    for row in rows:
        user, created, error = upsert_team_member(
            team,
            row["email"],
            row["password"],
            username=row.get("username"),
        )
        if error:
            errors.append(error)
            continue
        if created:
            created_count += 1
        added_count += 1

    db.session.commit()

    if added_count:
        flash(
            f"Imported {added_count} member(s) ({created_count} new account(s) created).",
            "success",
        )
    if errors:
        for message in errors[:5]:
            flash(message, "error")
        if len(errors) > 5:
            flash(f"…and {len(errors) - 5} more errors.", "error")

    return redirect(url_for("teams.view_team", team_id=team.id))


@teams_bp.route("/<int:team_id>/members/<int:user_id>/remove", methods=["POST"])
@login_required
def remove_member(team_id, user_id):
    from app.routes.team_helpers import get_team_for_user

    team = get_team_for_user(team_id)
    if not is_team_owner(team.id):
        flash("Only team owners can remove members.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    if user_id == current_user.id:
        flash("You cannot remove yourself from the team.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    membership = TeamMember.query.filter_by(team_id=team.id, user_id=user_id).first()
    if membership is None:
        flash("Member not found on this team.", "error")
        return redirect(url_for("teams.view_team", team_id=team.id))

    db.session.delete(membership)
    db.session.commit()
    flash("Member removed from the team.", "success")
    return redirect(url_for("teams.view_team", team_id=team.id))
