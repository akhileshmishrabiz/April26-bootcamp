import csv
import io
import random

from flask import Blueprint, flash, jsonify, redirect, render_template, request, url_for
from flask_login import current_user, login_required

from app import db
from app.models.models import (
    WHEEL_MODES,
    WHEEL_NAME_STATUSES,
    SpeakWheel,
    SpeakWheelName,
    SpeakWheelPick,
)
from app.routes.helpers import new_share_token
from app.routes.team_helpers import get_team_for_user, team_member_users, user_teams
from app.query_options import wheel_detail_options

wheel_bp = Blueprint("wheel", __name__, url_prefix="/wheel")

PUBLIC_ENDPOINTS = {"wheel.watch_wheel", "wheel.wheel_state"}


@wheel_bp.before_request
def wheel_access():
    if request.endpoint in PUBLIC_ENDPOINTS:
        return None
    if not current_user.is_authenticated:
        return redirect(url_for("auth.login", next=request.url))
    if current_user.is_guest:
        flash("Create a full account to use the speak wheel.", "error")
        return redirect(url_for("retro.list_retros"))
    return None


def _wants_json():
    return (
        request.headers.get("X-Requested-With") == "XMLHttpRequest"
        or request.accept_mimetypes.best_match(["application/json", "text/html"])
        == "application/json"
    )


def _json_error(message, status=400):
    return jsonify({"ok": False, "error": message}), status


def _wheel_by_token(token):
    return (
        SpeakWheel.query.filter_by(share_token=token)
        .options(*wheel_detail_options())
        .first_or_404()
    )


def _get_wheel(wheel_id):
    return SpeakWheel.query.options(*wheel_detail_options()).get_or_404(wheel_id)


def _share_url(wheel):
    return url_for("wheel.watch_wheel", token=wheel.share_token, _external=True)


def _can_facilitate(wheel):
    return current_user.is_authenticated and (
        wheel.created_by == current_user.id or current_user.is_admin
    )


def _parse_names(raw_text):
    names = []
    seen = set()
    if not raw_text or not raw_text.strip():
        return names

    reader = csv.reader(io.StringIO(raw_text.strip()))
    for row in reader:
        if not row:
            continue
        name = row[0].strip()
        if not name or name.lower() in ("name", "username", "email"):
            continue
        key = name.lower()
        if key not in seen:
            seen.add(key)
            names.append(name)
    return names


def _wheel_state(wheel):
    active = wheel.active_names
    spoken = [
        n
        for n in wheel.names
        if n.status == "spoken" or (wheel.mode == "repeat" and n.pick_count > 0)
    ]
    waiting_elim = [n for n in wheel.names if n.status == "waiting"]
    spoken_count, total = wheel.progress

    picks = (
        SpeakWheelPick.query.filter_by(wheel_id=wheel.id)
        .order_by(SpeakWheelPick.picked_at.desc())
        .limit(20)
        .all()
    )

    return {
        "wheel_id": wheel.id,
        "title": wheel.title,
        "mode": wheel.mode,
        "status": wheel.status,
        "spoken_count": spoken_count,
        "total": total,
        "active": [
            {"id": n.id, "name": n.name, "color_index": n.color_index} for n in active
        ],
        "waiting": [
            {"id": n.id, "name": n.name, "status": n.status, "pick_count": n.pick_count}
            for n in waiting_elim
            if wheel.mode == "elimination"
        ]
        or [
            {"id": n.id, "name": n.name, "status": n.status, "pick_count": n.pick_count}
            for n in wheel.names
        ],
        "spoken": [
            {"id": n.id, "name": n.name, "pick_count": n.pick_count}
            for n in sorted(
                {n.id: n for n in spoken}.values(),
                key=lambda x: x.picks[-1].picked_at if x.picks else x.created_at,
                reverse=True,
            )
        ],
        "recent_picks": [
            {
                "name": p.name_entry.name,
                "picked_at": p.picked_at.strftime("%H:%M:%S"),
            }
            for p in picks
        ],
        "can_spin": len(active) > 0 and wheel.status == "open",
    }


def _add_names(wheel, names):
    added = 0
    existing = {n.name.lower() for n in wheel.names}
    for name in names:
        if name.lower() in existing:
            continue
        color_index = len(wheel.names) % 12
        db.session.add(
            SpeakWheelName(
                wheel_id=wheel.id,
                name=name,
                color_index=color_index,
            )
        )
        existing.add(name.lower())
        added += 1
    return added


@wheel_bp.route("")
@login_required
def list_wheels():
    wheels = SpeakWheel.query.order_by(SpeakWheel.created_at.desc()).all()
    return render_template("wheel/list.html", wheels=wheels, modes=WHEEL_MODES)


@wheel_bp.route("/create", methods=["GET", "POST"])
@login_required
def create_wheel():
    teams = user_teams()

    if request.method == "POST":
        title = request.form.get("title", "").strip()
        description = request.form.get("description", "").strip()
        mode = request.form.get("mode", "elimination")
        team_id_raw = request.form.get("team_id", "").strip()
        names_raw = request.form.get("names", "").strip()

        if not title:
            flash("Session title is required.", "error")
            return redirect(url_for("wheel.create_wheel"))

        if mode not in WHEEL_MODES:
            mode = "elimination"

        wheel = SpeakWheel(
            title=title,
            description=description or None,
            mode=mode,
            share_token=new_share_token(),
            created_by=current_user.id,
        )

        if team_id_raw.isdigit():
            team = get_team_for_user(int(team_id_raw))
            wheel.team_id = team.id

        db.session.add(wheel)
        db.session.flush()

        names = _parse_names(names_raw)
        if team_id_raw.isdigit() and not names:
            team = get_team_for_user(int(team_id_raw))
            names = [u.label for u in team_member_users(team.id)]

        added = _add_names(wheel, names)
        db.session.commit()

        flash(
            f"Speak wheel created with {added} name{'s' if added != 1 else ''}! Share the link with your group.",
            "success",
        )
        return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))

    return render_template(
        "wheel/create.html",
        teams=teams,
        modes=WHEEL_MODES,
    )


@wheel_bp.route("/<int:wheel_id>")
@login_required
def view_wheel(wheel_id):
    wheel = _get_wheel(wheel_id)
    return render_template(
        "wheel/board.html",
        wheel=wheel,
        modes=WHEEL_MODES,
        statuses=WHEEL_NAME_STATUSES,
        share_url=_share_url(wheel),
        state=_wheel_state(wheel),
        can_facilitate=_can_facilitate(wheel),
    )


@wheel_bp.route("/watch/<token>")
def watch_wheel(token):
    wheel = _wheel_by_token(token)
    return render_template(
        "wheel/watch.html",
        wheel=wheel,
        share_url=_share_url(wheel),
        state=_wheel_state(wheel),
        token=token,
    )


@wheel_bp.route("/<int:wheel_id>/state")
def wheel_state(wheel_id):
    wheel = _get_wheel(wheel_id)
    return jsonify({"ok": True, **_wheel_state(wheel)})


@wheel_bp.route("/<int:wheel_id>/names", methods=["POST"])
@login_required
def add_names(wheel_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can manage names.", 403)

    upload = request.files.get("names_file")
    raw = request.form.get("names", "")
    if upload and upload.filename:
        raw = upload.read().decode("utf-8-sig")

    names = _parse_names(raw)
    if not names:
        if _wants_json():
            return _json_error("No valid names found.")
        flash("No valid names found.", "error")
        return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))

    added = _add_names(wheel, names)
    db.session.commit()

    if _wants_json():
        return jsonify({"ok": True, "added": added, "state": _wheel_state(wheel)})

    flash(f"Added {added} name(s) to the wheel.", "success")
    return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))


@wheel_bp.route("/<int:wheel_id>/spin", methods=["POST"])
@login_required
def spin_wheel(wheel_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can spin.", 403)

    if wheel.status != "open":
        return _json_error("This session is closed.")

    active = wheel.active_names
    if not active:
        return _json_error("No names left on the wheel — add more or reset.")

    winner = random.choice(active)
    segment_index = active.index(winner)

    pick = SpeakWheelPick(
        wheel_id=wheel.id,
        name_id=winner.id,
        picked_by=current_user.id,
    )
    db.session.add(pick)

    if wheel.mode == "elimination":
        winner.status = "spoken"

    db.session.commit()

    return jsonify(
        {
            "ok": True,
            "winner": {
                "id": winner.id,
                "name": winner.name,
                "color_index": winner.color_index,
            },
            "segment_index": segment_index,
            "segment_count": len(active),
            "state": _wheel_state(wheel),
        }
    )


@wheel_bp.route("/<int:wheel_id>/names/<int:name_id>/absent", methods=["POST"])
@login_required
def mark_absent(wheel_id, name_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can update names.", 403)

    entry = SpeakWheelName.query.filter_by(id=name_id, wheel_id=wheel.id).first_or_404()
    entry.status = "waiting"
    db.session.commit()

    if _wants_json():
        return jsonify({"ok": True, "state": _wheel_state(wheel)})
    return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))


@wheel_bp.route("/<int:wheel_id>/names/<int:name_id>/remove", methods=["POST"])
@login_required
def remove_name(wheel_id, name_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can update names.", 403)

    entry = SpeakWheelName.query.filter_by(id=name_id, wheel_id=wheel.id).first_or_404()
    db.session.delete(entry)
    db.session.commit()

    if _wants_json():
        return jsonify({"ok": True, "state": _wheel_state(wheel)})
    return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))


@wheel_bp.route("/<int:wheel_id>/reset", methods=["POST"])
@login_required
def reset_wheel(wheel_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can reset.", 403)

    for entry in wheel.names:
        entry.status = "waiting"
    SpeakWheelPick.query.filter_by(wheel_id=wheel.id).delete()
    wheel.status = "open"
    db.session.commit()

    if _wants_json():
        return jsonify({"ok": True, "state": _wheel_state(wheel)})
    flash("Wheel reset — everyone is back in the pool.", "success")
    return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))


@wheel_bp.route("/<int:wheel_id>/shuffle", methods=["POST"])
@login_required
def shuffle_wheel(wheel_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can shuffle.", 403)

    entries = list(wheel.names)
    random.shuffle(entries)
    for i, entry in enumerate(entries):
        entry.color_index = i % 12
    db.session.commit()

    if _wants_json():
        return jsonify({"ok": True, "state": _wheel_state(wheel)})
    return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))


@wheel_bp.route("/<int:wheel_id>/close", methods=["POST"])
@login_required
def close_wheel(wheel_id):
    wheel = _get_wheel(wheel_id)
    if not _can_facilitate(wheel):
        return _json_error("Only the facilitator can close.", 403)

    wheel.status = "closed"
    db.session.commit()

    if _wants_json():
        return jsonify({"ok": True, "state": _wheel_state(wheel)})
    flash("Session closed.", "success")
    return redirect(url_for("wheel.view_wheel", wheel_id=wheel.id))
