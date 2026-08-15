from flask import Blueprint, jsonify, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.models.models import (
    Student,
    Attendance,
    db,
    Class,
    Assignment,
    Announcement,
    Ticket,
    Incident,
)
from datetime import datetime, date
import os
import time

from sqlalchemy import case, func, text
from app.routes.incident_helpers import accessible_incidents_query, current_on_call
from app.routes.team_helpers import accessible_tickets_query, user_teams
from app.query_options import incident_summary_options, ticket_summary_options

_HEALTH_CACHE_SECONDS = float(os.getenv("HEALTH_CACHE_SECONDS", "5"))
_health_cache = {"checked_at": 0.0, "healthy": False}

bp = Blueprint("main", __name__)


@bp.before_request
def block_guests_from_portal():
    if not current_user.is_authenticated or not current_user.is_guest:
        return None
    if request.endpoint == "static":
        return None
    return redirect(url_for("retro.list_retros"))


def _parse_date(value):
    if isinstance(value, date):
        return value
    return datetime.strptime(value, "%Y-%m-%d").date()


@bp.route("/health")
def health():
    now = time.time()
    if now - _health_cache["checked_at"] < _HEALTH_CACHE_SECONDS:
        if _health_cache["healthy"]:
            return jsonify({"status": "healthy", "database": "connected"}), 200
        return jsonify({"status": "unhealthy", "database": "disconnected"}), 503

    try:
        db.session.execute(text("SELECT 1"))
        _health_cache["checked_at"] = now
        _health_cache["healthy"] = True
        return jsonify({"status": "healthy", "database": "connected"}), 200
    except Exception:
        _health_cache["checked_at"] = now
        _health_cache["healthy"] = False
        return jsonify({"status": "unhealthy", "database": "disconnected"}), 503


@bp.route("/")
@login_required
def dashboard():
    today = date.today()

    total_students = Student.query.count()

    attendance_stats = db.session.query(
        func.count(Attendance.id).label("total_records"),
        func.sum(case((Attendance.status == "Present", 1), else_=0)).label(
            "total_present"
        ),
        func.sum(
            case(
                (
                    (Attendance.date == today) & (Attendance.status == "Present"),
                    1,
                ),
                else_=0,
            )
        ).label("today_present"),
    ).one()

    total_records = attendance_stats.total_records or 0
    total_present = attendance_stats.total_present or 0
    today_attendance = attendance_stats.today_present or 0
    attendance_rate = round(
        (total_present / total_records * 100) if total_records > 0 else 0, 1
    )

    announcements = (
        Announcement.query.filter_by(is_pinned=True)
        .order_by(Announcement.created_at.desc())
        .all()
    )
    recent = (
        Announcement.query.filter_by(is_pinned=False)
        .order_by(Announcement.created_at.desc())
        .limit(3)
        .all()
    )
    announcements = announcements + recent

    upcoming_assignments = (
        Assignment.query.filter(
            Assignment.due_date >= today, Assignment.is_completed == False
        )
        .order_by(Assignment.due_date.asc())
        .limit(5)
        .all()
    )

    open_incidents = (
        accessible_incidents_query()
        .options(*incident_summary_options())
        .filter(Incident.status.notin_(["resolved", "postmortem_pending", "closed"]))
        .order_by(Incident.updated_at.desc())
        .limit(5)
        .all()
    )
    my_tickets = (
        accessible_tickets_query()
        .options(*ticket_summary_options())
        .filter(Ticket.assignee_id == current_user.id, Ticket.status != "done")
        .order_by(Ticket.updated_at.desc())
        .limit(5)
        .all()
    )
    teams = user_teams()
    on_call_shifts = []
    for team in teams:
        primary = current_on_call(team.id)
        if primary:
            on_call_shifts.append({"team": team, "shift": primary, "role": "primary"})

    return render_template(
        "dashboard.html",
        total_students=total_students,
        today_attendance=f"{today_attendance}/{total_students}",
        attendance_rate=attendance_rate,
        announcements=announcements,
        upcoming_assignments=upcoming_assignments,
        today=today,
        open_incidents=open_incidents,
        my_tickets=my_tickets,
        on_call_shifts=on_call_shifts,
    )


@bp.route("/students")
@login_required
def students():
    students = Student.query.all()
    stats = {
        row.student_id: row
        for row in db.session.query(
            Attendance.student_id,
            func.count(Attendance.id).label("total_days"),
            func.sum(case((Attendance.status == "Present", 1), else_=0)).label(
                "present_days"
            ),
        )
        .group_by(Attendance.student_id)
        .all()
    }
    for student in students:
        row = stats.get(student.id)
        if row and row.total_days:
            student.attendance_rate = round(row.present_days / row.total_days * 100, 1)
        else:
            student.attendance_rate = 0
    return render_template("students.html", students=students)


@bp.route("/attendance")
@login_required
def attendance():
    selected_date = _parse_date(request.args.get("date", date.today().isoformat()))
    students = Student.query.all()
    attendance_by_student = {
        row.student_id: row
        for row in Attendance.query.filter_by(date=selected_date).all()
    }

    for student in students:
        student.today_attendance = attendance_by_student.get(student.id)

    return render_template(
        "attendance.html",
        students=students,
        selected_date=selected_date.isoformat(),
    )


@bp.route("/add_student", methods=["POST"])
@login_required
def add_student():
    name = request.form.get("name")
    if name:
        student = Student(name=name)
        db.session.add(student)
        db.session.commit()
        flash("Student added successfully", "success")
    return redirect(url_for("main.students"))


@bp.route("/mark_attendance", methods=["POST"])
@login_required
def mark_attendance():
    try:
        attendance_date = _parse_date(
            request.form.get("date", date.today().isoformat())
        )
        students = Student.query.all()

        for student in students:
            status = request.form.get(f"status_{student.id}")
            if status:
                attendance = Attendance.query.filter_by(
                    student_id=student.id, date=attendance_date
                ).first()

                if attendance:
                    attendance.status = status
                else:
                    attendance = Attendance(
                        student_id=student.id, date=attendance_date, status=status
                    )
                    db.session.add(attendance)

        db.session.commit()
        flash("Attendance marked successfully", "success")
        return redirect(url_for("main.attendance", date=attendance_date.isoformat()))
    except Exception:
        db.session.rollback()
        flash("Error marking attendance", "error")
        return redirect(url_for("main.attendance"))


@bp.route("/edit_student/<int:id>", methods=["POST"])
@login_required
def edit_student(id):
    student = Student.query.get_or_404(id)
    data = request.get_json()
    student.name = data["name"]
    db.session.commit()
    return "", 204


@bp.route("/delete_student/<int:id>", methods=["POST"])
@login_required
def delete_student(id):
    student = Student.query.get_or_404(id)
    db.session.delete(student)
    db.session.commit()
    return "", 204


@bp.route("/classes")
@login_required
def classes():
    classes = Class.query.order_by(Class.date.desc()).all()
    return render_template("classes.html", classes=classes)


@bp.route("/add_class", methods=["GET", "POST"])
@login_required
def add_class():
    if request.method == "POST":
        try:
            new_class = Class(
                date=datetime.strptime(request.form["date"], "%Y-%m-%d").date(),
                time=request.form["time"],
                session_link=request.form["session_link"],
                code_link=request.form["code_link"],
                recording_link=request.form["recording_link"],
                resource_link=request.form["resource_link"],
                remarks=request.form["remarks"],
                created_by=current_user.id,
            )
            db.session.add(new_class)
            db.session.commit()
            flash("Class added successfully!", "success")
            return redirect(url_for("main.classes"))
        except Exception as e:
            flash("Error adding class.", "error")
            return redirect(url_for("main.add_class"))
    return render_template("add_class.html")


@bp.route("/delete_class/<int:id>", methods=["POST"])
@login_required
def delete_class(id):
    class_obj = Class.query.get_or_404(id)
    db.session.delete(class_obj)
    db.session.commit()
    return "", 204


@bp.route("/edit_class/<int:id>", methods=["GET", "POST"])
@login_required
def edit_class(id):
    class_obj = Class.query.get_or_404(id)

    if request.method == "POST":
        try:
            class_obj.date = datetime.strptime(request.form["date"], "%Y-%m-%d").date()
            class_obj.time = request.form["time"]
            class_obj.session_link = request.form["session_link"]
            class_obj.code_link = request.form["code_link"]
            class_obj.recording_link = request.form["recording_link"]
            class_obj.resource_link = request.form["resource_link"]
            class_obj.remarks = request.form["remarks"]

            db.session.commit()
            flash("Class updated successfully!", "success")
            return redirect(url_for("main.classes"))
        except Exception as e:
            flash("Error updating class.", "error")

    return render_template("edit_class.html", class_obj=class_obj)


# ── Assignments ──────────────────────────────────────────────────────────────


@bp.route("/assignments")
@login_required
def assignments():
    today = date.today()
    pending = (
        Assignment.query.filter(Assignment.is_completed == False)
        .order_by(Assignment.due_date.asc())
        .all()
    )
    completed = (
        Assignment.query.filter(Assignment.is_completed == True)
        .order_by(Assignment.due_date.desc())
        .limit(10)
        .all()
    )
    return render_template(
        "assignments.html", pending=pending, completed=completed, today=today
    )


@bp.route("/add_assignment", methods=["POST"])
@login_required
def add_assignment():
    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    due_date_str = request.form.get("due_date", "")
    link = request.form.get("link", "").strip()
    if title and due_date_str:
        try:
            due_date = datetime.strptime(due_date_str, "%Y-%m-%d").date()
            assignment = Assignment(
                title=title,
                description=description or None,
                due_date=due_date,
                link=link or None,
                created_by=current_user.id,
            )
            db.session.add(assignment)
            db.session.commit()
            flash("Assignment added successfully!", "success")
        except Exception:
            flash("Error adding assignment.", "error")
    else:
        flash("Title and due date are required.", "error")
    return redirect(url_for("main.assignments"))


@bp.route("/toggle_assignment/<int:id>", methods=["POST"])
@login_required
def toggle_assignment(id):
    assignment = Assignment.query.get_or_404(id)
    assignment.is_completed = not assignment.is_completed
    db.session.commit()
    return redirect(url_for("main.assignments"))


@bp.route("/delete_assignment/<int:id>", methods=["POST"])
@login_required
def delete_assignment(id):
    assignment = Assignment.query.get_or_404(id)
    db.session.delete(assignment)
    db.session.commit()
    flash("Assignment deleted.", "success")
    return redirect(url_for("main.assignments"))


# ── Announcements ─────────────────────────────────────────────────────────────


@bp.route("/announcements")
@login_required
def announcements():
    pinned = (
        Announcement.query.filter_by(is_pinned=True)
        .order_by(Announcement.created_at.desc())
        .all()
    )
    others = (
        Announcement.query.filter_by(is_pinned=False)
        .order_by(Announcement.created_at.desc())
        .all()
    )
    return render_template("announcements.html", pinned=pinned, others=others)


@bp.route("/add_announcement", methods=["POST"])
@login_required
def add_announcement():
    title = request.form.get("title", "").strip()
    content = request.form.get("content", "").strip()
    is_pinned = request.form.get("is_pinned") == "on"
    if title and content:
        announcement = Announcement(
            title=title,
            content=content,
            is_pinned=is_pinned,
            created_by=current_user.id,
        )
        db.session.add(announcement)
        db.session.commit()
        flash("Announcement posted!", "success")
    else:
        flash("Title and content are required.", "error")
    return redirect(url_for("main.announcements"))


@bp.route("/delete_announcement/<int:id>", methods=["POST"])
@login_required
def delete_announcement(id):
    announcement = Announcement.query.get_or_404(id)
    db.session.delete(announcement)
    db.session.commit()
    flash("Announcement deleted.", "success")
    return redirect(url_for("main.announcements"))
