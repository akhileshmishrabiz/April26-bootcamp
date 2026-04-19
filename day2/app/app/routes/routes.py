from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_required, current_user
from app.models.models import Student, Attendance, db, Class, Assignment, Announcement
from datetime import datetime, date
from app.metrics import (
    student_operations, student_total, class_operations, class_total,
    assignment_operations, assignment_total, announcement_operations,
    announcement_total, db_query_duration_seconds, student_attendance_marked
)
import time

bp = Blueprint("main", __name__)


@bp.route("/")
@login_required
def dashboard():
    today = date.today()

    # Get total students
    total_students = Student.query.count()

    # Get today's attendance
    today_attendance = Attendance.query.filter_by(date=today, status="Present").count()

    # Calculate total attendance rate
    total_marked_days = Attendance.query.distinct(Attendance.date).count()
    total_present = Attendance.query.filter_by(status="Present").count()
    total_records = Attendance.query.count()

    attendance_rate = round(
        (total_present / total_records * 100) if total_records > 0 else 0, 1
    )

    # Get pinned announcements + 3 most recent
    announcements = Announcement.query.filter_by(is_pinned=True).order_by(
        Announcement.created_at.desc()
    ).all()
    recent = Announcement.query.filter_by(is_pinned=False).order_by(
        Announcement.created_at.desc()
    ).limit(3).all()
    announcements = announcements + recent

    # Get upcoming assignments (due today or later, not completed)
    upcoming_assignments = Assignment.query.filter(
        Assignment.due_date >= today,
        Assignment.is_completed == False
    ).order_by(Assignment.due_date.asc()).limit(5).all()

    return render_template(
        "dashboard.html",
        total_students=total_students,
        today_attendance=f"{today_attendance}/{total_students}",
        attendance_rate=attendance_rate,
        announcements=announcements,
        upcoming_assignments=upcoming_assignments,
        today=today,
    )


@bp.route("/students")
@login_required
def students():
    students = Student.query.all()
    for student in students:
        total_days = Attendance.query.filter_by(student_id=student.id).count()
        if total_days > 0:
            present_days = Attendance.query.filter_by(
                student_id=student.id, status="Present"
            ).count()
            student.attendance_rate = round(present_days / total_days * 100, 1)
        else:
            student.attendance_rate = 0
    return render_template("students.html", students=students)


@bp.route("/attendance")
@login_required
def attendance():
    selected_date = request.args.get("date", date.today().isoformat())
    students = Student.query.all()

    for student in students:
        student.today_attendance = Attendance.query.filter_by(
            student_id=student.id, date=selected_date
        ).first()

    return render_template(
        "attendance.html", students=students, selected_date=selected_date
    )


@bp.route("/add_student", methods=["POST"])
@login_required
def add_student():
    name = request.form.get("name")
    if name:
        start_time = time.time()
        student = Student(name=name)
        db.session.add(student)
        db.session.commit()
        db_query_duration_seconds.labels(operation="add_student").observe(time.time() - start_time)
        student_operations.labels(operation="add").inc()
        student_total.set(Student.query.count())
        flash("Student added successfully", "success")
    return redirect(url_for("main.students"))


@bp.route("/mark_attendance", methods=["POST"])
@login_required
def mark_attendance():
    try:
        start_time = time.time()
        attendance_date = request.form.get("date", date.today().isoformat())
        students = Student.query.all()

        marked_count = 0
        for student in students:
            status = request.form.get(f"status_{student.id}")
            if status:
                # Update existing or create new attendance record
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
                marked_count += 1

        db.session.commit()
        db_query_duration_seconds.labels(operation="mark_attendance").observe(time.time() - start_time)
        student_attendance_marked.inc(marked_count)
        flash("Attendance marked successfully", "success")
        return redirect(url_for("main.attendance", date=attendance_date))
    except Exception as e:
        flash("Error marking attendance", "error")
        return redirect(url_for("main.attendance"))


@bp.route("/edit_student/<int:id>", methods=["POST"])
@login_required
def edit_student(id):
    start_time = time.time()
    student = Student.query.get_or_404(id)
    data = request.get_json()
    student.name = data["name"]
    db.session.commit()
    db_query_duration_seconds.labels(operation="edit_student").observe(time.time() - start_time)
    student_operations.labels(operation="edit").inc()
    return "", 204


@bp.route("/delete_student/<int:id>", methods=["POST"])
@login_required
def delete_student(id):
    start_time = time.time()
    student = Student.query.get_or_404(id)
    db.session.delete(student)
    db.session.commit()
    db_query_duration_seconds.labels(operation="delete_student").observe(time.time() - start_time)
    student_operations.labels(operation="delete").inc()
    student_total.set(Student.query.count())
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
            start_time = time.time()
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
            db_query_duration_seconds.labels(operation="add_class").observe(time.time() - start_time)
            class_operations.labels(operation="add").inc()
            class_total.set(Class.query.count())
            flash("Class added successfully!", "success")
            return redirect(url_for("main.classes"))
        except Exception as e:
            flash("Error adding class.", "error")
            return redirect(url_for("main.add_class"))
    return render_template("add_class.html")


@bp.route("/delete_class/<int:id>", methods=["POST"])
@login_required
def delete_class(id):
    start_time = time.time()
    class_obj = Class.query.get_or_404(id)
    db.session.delete(class_obj)
    db.session.commit()
    db_query_duration_seconds.labels(operation="delete_class").observe(time.time() - start_time)
    class_operations.labels(operation="delete").inc()
    class_total.set(Class.query.count())
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
    pending = Assignment.query.filter(
        Assignment.is_completed == False
    ).order_by(Assignment.due_date.asc()).all()
    completed = Assignment.query.filter(
        Assignment.is_completed == True
    ).order_by(Assignment.due_date.desc()).limit(10).all()
    return render_template("assignments.html", pending=pending, completed=completed, today=today)


@bp.route("/add_assignment", methods=["POST"])
@login_required
def add_assignment():
    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    due_date_str = request.form.get("due_date", "")
    link = request.form.get("link", "").strip()
    if title and due_date_str:
        try:
            start_time = time.time()
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
            db_query_duration_seconds.labels(operation="add_assignment").observe(time.time() - start_time)
            assignment_operations.labels(operation="add").inc()
            assignment_total.labels(status="pending").set(Assignment.query.filter_by(is_completed=False).count())
            flash("Assignment added successfully!", "success")
        except Exception:
            flash("Error adding assignment.", "error")
    else:
        flash("Title and due date are required.", "error")
    return redirect(url_for("main.assignments"))


@bp.route("/toggle_assignment/<int:id>", methods=["POST"])
@login_required
def toggle_assignment(id):
    start_time = time.time()
    assignment = Assignment.query.get_or_404(id)
    assignment.is_completed = not assignment.is_completed
    db.session.commit()
    db_query_duration_seconds.labels(operation="toggle_assignment").observe(time.time() - start_time)
    assignment_operations.labels(operation="toggle").inc()
    assignment_total.labels(status="pending").set(Assignment.query.filter_by(is_completed=False).count())
    assignment_total.labels(status="completed").set(Assignment.query.filter_by(is_completed=True).count())
    return redirect(url_for("main.assignments"))


@bp.route("/delete_assignment/<int:id>", methods=["POST"])
@login_required
def delete_assignment(id):
    start_time = time.time()
    assignment = Assignment.query.get_or_404(id)
    db.session.delete(assignment)
    db.session.commit()
    db_query_duration_seconds.labels(operation="delete_assignment").observe(time.time() - start_time)
    assignment_operations.labels(operation="delete").inc()
    assignment_total.labels(status="pending").set(Assignment.query.filter_by(is_completed=False).count())
    assignment_total.labels(status="completed").set(Assignment.query.filter_by(is_completed=True).count())
    flash("Assignment deleted.", "success")
    return redirect(url_for("main.assignments"))


# ── Announcements ─────────────────────────────────────────────────────────────

@bp.route("/announcements")
@login_required
def announcements():
    pinned = Announcement.query.filter_by(is_pinned=True).order_by(
        Announcement.created_at.desc()
    ).all()
    others = Announcement.query.filter_by(is_pinned=False).order_by(
        Announcement.created_at.desc()
    ).all()
    return render_template("announcements.html", pinned=pinned, others=others)


@bp.route("/add_announcement", methods=["POST"])
@login_required
def add_announcement():
    title = request.form.get("title", "").strip()
    content = request.form.get("content", "").strip()
    is_pinned = request.form.get("is_pinned") == "on"
    if title and content:
        start_time = time.time()
        announcement = Announcement(
            title=title,
            content=content,
            is_pinned=is_pinned,
            created_by=current_user.id,
        )
        db.session.add(announcement)
        db.session.commit()
        db_query_duration_seconds.labels(operation="add_announcement").observe(time.time() - start_time)
        announcement_operations.labels(operation="add").inc()
        announcement_total.labels(pinned="true").set(Announcement.query.filter_by(is_pinned=True).count())
        announcement_total.labels(pinned="false").set(Announcement.query.filter_by(is_pinned=False).count())
        flash("Announcement posted!", "success")
    else:
        flash("Title and content are required.", "error")
    return redirect(url_for("main.announcements"))


@bp.route("/delete_announcement/<int:id>", methods=["POST"])
@login_required
def delete_announcement(id):
    start_time = time.time()
    announcement = Announcement.query.get_or_404(id)
    db.session.delete(announcement)
    db.session.commit()
    db_query_duration_seconds.labels(operation="delete_announcement").observe(time.time() - start_time)
    announcement_operations.labels(operation="delete").inc()
    announcement_total.labels(pinned="true").set(Announcement.query.filter_by(is_pinned=True).count())
    announcement_total.labels(pinned="false").set(Announcement.query.filter_by(is_pinned=False).count())
    flash("Announcement deleted.", "success")
    return redirect(url_for("main.announcements"))
