import re
import uuid
from functools import wraps
from urllib.parse import urlparse

from flask import flash, redirect, request, url_for
from flask_login import current_user, login_required


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            flash("Admin access required.", "error")
            return redirect(url_for("retro.list_retros"))
        return view(*args, **kwargs)

    return wrapped


def full_account_required(view):
    @login_required
    @wraps(view)
    def wrapped(*args, **kwargs):
        if current_user.is_guest:
            flash("Create a full account to access this section.", "error")
            return redirect(url_for("retro.list_retros"))
        return view(*args, **kwargs)

    return wrapped


def safe_next_url(target):
    if not target:
        return None
    host = urlparse(request.host_url).netloc
    test = urlparse(target)
    if test.scheme or test.netloc:
        if test.netloc != host:
            return None
        return target
    if target.startswith("/"):
        return target
    return None


def unique_guest_username(display_name):
    from app import db
    from app.models.models import User

    base = re.sub(r"[^a-zA-Z0-9_]", "", display_name.replace(" ", "_").lower())[:20]
    if not base:
        base = "guest"
    candidate = base
    suffix = 1
    while User.query.filter_by(username=candidate).first():
        candidate = f"{base}_{suffix}"
        suffix += 1
    return candidate


def new_share_token():
    return uuid.uuid4().hex


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


def unique_username_from_email(email):
    from app import db
    from app.models.models import User

    local = email.split("@")[0]
    base = re.sub(r"[^a-zA-Z0-9_]", "", local.lower())[:20] or "user"
    candidate = base
    suffix = 1
    while User.query.filter_by(username=candidate).first():
        candidate = f"{base}_{suffix}"
        suffix += 1
    return candidate
