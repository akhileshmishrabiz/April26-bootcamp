from flask import Blueprint, render_template, request, flash, redirect, url_for
from app.models.models import User, db
from app.routes.helpers import safe_next_url, validate_email, validate_password
from flask_login import login_user, logout_user, current_user

auth_bp = Blueprint("auth", __name__)


@auth_bp.route("/register", methods=["GET", "POST"])
def register():
    next_url = safe_next_url(request.args.get("next"))

    if request.method == "POST":
        username = request.form.get("username")
        email = request.form.get("email")
        password = request.form.get("password")
        next_url = safe_next_url(request.form.get("next")) or next_url

        if not username or not email or not password:
            flash("All fields are required", "error")
            return redirect(url_for("auth.register", next=next_url))

        if not validate_email(email):
            flash("Invalid email format", "error")
            return redirect(url_for("auth.register", next=next_url))

        if not validate_password(password):
            flash(
                "Password must be at least 8 characters long and contain uppercase, lowercase, and numbers",
                "error",
            )
            return redirect(url_for("auth.register", next=next_url))

        if User.query.filter_by(username=username).first():
            flash("Username already exists", "error")
            return redirect(url_for("auth.register", next=next_url))

        if User.query.filter_by(email=email).first():
            flash("Email already registered", "error")
            return redirect(url_for("auth.register", next=next_url))

        user = User(username=username, email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()

        login_user(user)
        flash("Registration successful", "success")
        return redirect(next_url or url_for("main.dashboard"))

    return render_template("auth/register.html", next_url=next_url)


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    next_url = safe_next_url(request.args.get("next"))

    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")
        next_url = safe_next_url(request.form.get("next")) or next_url
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            login_user(user)
            if user.is_guest:
                return redirect(url_for("retro.list_retros"))
            return redirect(next_url or url_for("main.dashboard"))
        flash("Invalid username or password", "error")
    return render_template("auth/login.html", next_url=next_url)


@auth_bp.route("/logout")
def logout():
    logout_user()
    flash("Logged out successfully", "success")
    return redirect(url_for("auth.login"))
