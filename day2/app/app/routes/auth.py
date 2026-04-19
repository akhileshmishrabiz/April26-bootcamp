from flask import Blueprint, render_template, request, flash, redirect, url_for, session
from app.models.models import User, db
import re
from flask_login import login_user, logout_user, current_user
from app.metrics import auth_attempts

auth_bp = Blueprint("auth", __name__)


def validate_password(password):
    if len(password) < 8:
        return False
    if not re.search("[a-z]", password):
        return False
    if not re.search("[A-Z]", password):
        return False
    if not re.search("[0-9]", password):
        return False
    return True


def validate_email(email):
    pattern = r"^[\w\.-]+@[\w\.-]+\.\w+$"
    return re.match(pattern, email) is not None


@auth_bp.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form.get("username")
        email = request.form.get("email")
        password = request.form.get("password")

        if not username or not email or not password:
            flash("All fields are required", "error")
            auth_attempts.labels(status="failed_validation").inc()
            return redirect(url_for("auth.register"))

        if not validate_email(email):
            flash("Invalid email format", "error")
            auth_attempts.labels(status="failed_validation").inc()
            return redirect(url_for("auth.register"))

        if not validate_password(password):
            flash(
                "Password must be at least 8 characters long and contain uppercase, lowercase, and numbers",
                "error",
            )
            auth_attempts.labels(status="failed_validation").inc()
            return redirect(url_for("auth.register"))

        if User.query.filter_by(username=username).first():
            flash("Username already exists", "error")
            auth_attempts.labels(status="failed_duplicate").inc()
            return redirect(url_for("auth.register"))

        if User.query.filter_by(email=email).first():
            flash("Email already registered", "error")
            auth_attempts.labels(status="failed_duplicate").inc()
            return redirect(url_for("auth.register"))

        user = User(username=username, email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()

        auth_attempts.labels(status="registered").inc()
        flash("Registration successful", "success")
        return redirect(url_for("auth.login"))

    return render_template("auth/register.html")


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            login_user(user)
            auth_attempts.labels(status="success").inc()
            return redirect(url_for("main.dashboard"))
        auth_attempts.labels(status="failed").inc()
        flash("Invalid username or password", "error")
    return render_template("auth/login.html")


@auth_bp.route("/logout")
def logout():
    logout_user()
    flash("Logged out successfully", "success")
    return redirect(url_for("auth.login"))
