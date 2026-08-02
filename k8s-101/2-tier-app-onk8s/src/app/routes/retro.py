import re
import uuid

from flask import Blueprint, flash, jsonify, redirect, render_template, request, url_for
from flask_login import current_user, login_required, login_user
from sqlalchemy.orm import joinedload

from app.models.models import (
    RETRO_CATEGORIES,
    Retro,
    RetroCard,
    RetroComment,
    RetroLike,
    RetroParticipant,
    User,
    db,
)
from app.routes.helpers import (
    admin_required,
    new_share_token,
    safe_next_url,
    unique_guest_username,
)

retro_bp = Blueprint("retro", __name__, url_prefix="/retro")


def _share_url(retro):
    return url_for("retro.join_landing", token=retro.share_token, _external=True)


def _retro_by_token(token):
    return Retro.query.filter_by(share_token=token).first_or_404()


def _is_participant(retro):
    if not current_user.is_authenticated:
        return False
    return (
        RetroParticipant.query.filter_by(
            retro_id=retro.id, user_id=current_user.id
        ).first()
        is not None
    )


def _ensure_participant(retro):
    if not current_user.is_authenticated or retro.status != "open":
        return

    existing = RetroParticipant.query.filter_by(
        retro_id=retro.id, user_id=current_user.id
    ).first()
    if existing is None:
        db.session.add(RetroParticipant(retro_id=retro.id, user_id=current_user.id))
        db.session.commit()


def _liked_card_ids_for_retro(retro_id):
    if not current_user.is_authenticated:
        return set()
    return {
        like.card_id
        for like in RetroLike.query.join(RetroCard, RetroLike.card_id == RetroCard.id)
        .filter(
            RetroCard.retro_id == retro_id,
            RetroLike.user_id == current_user.id,
        )
        .all()
    }


def _card_item(card, liked_ids=None):
    liked_ids = liked_ids if liked_ids is not None else _liked_card_ids_for_retro(card.retro_id)
    return {
        "card": card,
        "like_count": len(card.likes),
        "liked_by_me": card.id in liked_ids,
    }


def _wants_json():
    return (
        request.headers.get("X-Requested-With") == "XMLHttpRequest"
        or request.accept_mimetypes.best_match(["application/json", "text/html"])
        == "application/json"
    )


def _render_card_html(retro, item, is_participant):
    meta = RETRO_CATEGORIES[item["card"].category]
    return render_template(
        "retro/_card.html",
        retro=retro,
        item=item,
        meta=meta,
        is_participant=is_participant,
    )


def _json_error(message, status=400):
    return jsonify({"ok": False, "error": message}), status


def _board_context(retro):
    cards = (
        RetroCard.query.filter_by(retro_id=retro.id)
        .options(joinedload(RetroCard.likes))
        .order_by(RetroCard.created_at.desc())
        .all()
    )
    cards_by_category = {key: [] for key in RETRO_CATEGORIES}
    liked_ids = _liked_card_ids_for_retro(retro.id)
    for card in cards:
        if card.category in cards_by_category:
            cards_by_category[card.category].append(_card_item(card, liked_ids))

    participants = (
        RetroParticipant.query.filter_by(retro_id=retro.id)
        .order_by(RetroParticipant.joined_at.asc())
        .all()
    )

    return {
        "retro": retro,
        "categories": RETRO_CATEGORIES,
        "cards_by_category": cards_by_category,
        "participants": participants,
        "share_url": _share_url(retro),
        "is_participant": _is_participant(retro),
    }


@retro_bp.route("")
@login_required
def list_retros():
    if current_user.is_guest:
        retro_ids = [
            p.retro_id
            for p in RetroParticipant.query.filter_by(user_id=current_user.id).all()
        ]
        retros = (
            Retro.query.filter(Retro.id.in_(retro_ids))
            .order_by(Retro.created_at.desc())
            .all()
            if retro_ids
            else []
        )
    else:
        retros = Retro.query.order_by(Retro.created_at.desc()).all()

    return render_template("retro/list.html", retros=retros)


@retro_bp.route("/create", methods=["GET", "POST"])
@login_required
@admin_required
def create_retro():
    if request.method == "POST":
        title = request.form.get("title", "").strip()
        description = request.form.get("description", "").strip()

        if not title:
            flash("Retro title is required.", "error")
            return redirect(url_for("retro.create_retro"))

        retro = Retro(
            title=title,
            description=description or None,
            created_by=current_user.id,
            share_token=new_share_token(),
        )
        db.session.add(retro)
        db.session.commit()

        db.session.add(RetroParticipant(retro_id=retro.id, user_id=current_user.id))
        db.session.commit()

        flash("Retro board created! Share the link with your team.", "success")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    return render_template("retro/create.html")


@retro_bp.route("/join/<token>", methods=["GET"])
def join_landing(token):
    retro = _retro_by_token(token)
    share_url = _share_url(retro)
    next_url = url_for("retro.join_landing", token=token)

    if current_user.is_authenticated and retro.status == "open":
        _ensure_participant(retro)

    return render_template(
        "retro/join.html",
        retro=retro,
        share_url=share_url,
        token=token,
        login_url=url_for("auth.login", next=next_url),
        register_url=url_for("auth.register", next=next_url),
        board_url=url_for("retro.view_retro", retro_id=retro.id),
        is_logged_in=current_user.is_authenticated,
    )


@retro_bp.route("/join/<token>/guest", methods=["POST"])
def join_as_guest(token):
    retro = _retro_by_token(token)

    if retro.status != "open":
        flash("This retro is closed.", "error")
        return redirect(url_for("retro.join_landing", token=token))

    display_name = request.form.get("display_name", "").strip()
    if len(display_name) < 2:
        flash("Please enter a display name (at least 2 characters).", "error")
        return redirect(url_for("retro.join_landing", token=token))

    username = unique_guest_username(display_name)
    guest = User(
        username=username,
        email=f"guest.{uuid.uuid4().hex}@retro.local",
        is_guest=True,
        display_name=display_name,
    )
    guest.set_password(uuid.uuid4().hex)
    db.session.add(guest)
    db.session.commit()

    db.session.add(RetroParticipant(retro_id=retro.id, user_id=guest.id))
    db.session.commit()

    login_user(guest)
    flash(f"Welcome, {display_name}! You're in the retro.", "success")
    return redirect(url_for("retro.view_retro", retro_id=retro.id))


@retro_bp.route("/<int:retro_id>")
@login_required
def view_retro(retro_id):
    retro = Retro.query.get_or_404(retro_id)

    if not _is_participant(retro):
        if retro.status == "open":
            _ensure_participant(retro)
        else:
            flash("Join this retro via the shared link first.", "error")
            return redirect(url_for("retro.list_retros"))

    return render_template("retro/board.html", **_board_context(retro))


@retro_bp.route("/<int:retro_id>/join", methods=["POST"])
@login_required
def join_retro(retro_id):
    retro = Retro.query.get_or_404(retro_id)
    if retro.status != "open":
        flash("This retro is closed.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    _ensure_participant(retro)
    flash("You joined the retro session.", "success")
    return redirect(url_for("retro.view_retro", retro_id=retro.id))


@retro_bp.route("/<int:retro_id>/cards", methods=["POST"])
@login_required
def add_card(retro_id):
    retro = Retro.query.get_or_404(retro_id)
    if retro.status != "open":
        if _wants_json():
            return _json_error("This retro is closed — no new cards allowed.")
        flash("This retro is closed — no new cards allowed.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    if not _is_participant(retro):
        if _wants_json():
            return _json_error("Join the retro before adding notes.")
        flash("Join the retro before adding notes.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    category = request.form.get("category", "")
    content = request.form.get("content", "").strip()

    if category not in RETRO_CATEGORIES:
        if _wants_json():
            return _json_error("Invalid retro column.")
        flash("Invalid retro column.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    if not content:
        if _wants_json():
            return _json_error("Card content cannot be empty.")
        flash("Card content cannot be empty.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    card = RetroCard(
        retro_id=retro.id,
        category=category,
        content=content,
        author_id=current_user.id,
    )
    db.session.add(card)
    db.session.commit()

    if _wants_json():
        item = _card_item(card)
        return jsonify(
            {
                "ok": True,
                "category": category,
                "card_id": card.id,
                "html": _render_card_html(retro, item, True),
            }
        )

    flash("Sticky note added!", "success")
    return redirect(url_for("retro.view_retro", retro_id=retro.id))


@retro_bp.route("/cards/<int:card_id>/like", methods=["POST"])
@login_required
def toggle_like(card_id):
    card = RetroCard.query.get_or_404(card_id)
    retro = Retro.query.get_or_404(card.retro_id)

    if retro.status != "open":
        if _wants_json():
            return _json_error("This retro is closed.")
        flash("This retro is closed.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    if not _is_participant(retro):
        if _wants_json():
            return _json_error("Join the retro to like notes.")
        flash("Join the retro to like notes.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    existing = RetroLike.query.filter_by(
        card_id=card.id, user_id=current_user.id
    ).first()

    if existing:
        db.session.delete(existing)
        liked_by_me = False
    else:
        db.session.add(RetroLike(card_id=card.id, user_id=current_user.id))
        liked_by_me = True

    db.session.commit()

    if _wants_json():
        like_count = RetroLike.query.filter_by(card_id=card.id).count()
        return jsonify(
            {
                "ok": True,
                "card_id": card.id,
                "like_count": like_count,
                "liked_by_me": liked_by_me,
            }
        )

    return redirect(url_for("retro.view_retro", retro_id=retro.id))


@retro_bp.route("/cards/<int:card_id>/comment", methods=["POST"])
@login_required
def add_comment(card_id):
    card = RetroCard.query.get_or_404(card_id)
    retro = Retro.query.get_or_404(card.retro_id)

    if retro.status != "open":
        if _wants_json():
            return _json_error("This retro is closed.")
        flash("This retro is closed.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    if not _is_participant(retro):
        if _wants_json():
            return _json_error("Join the retro to comment.")
        flash("Join the retro to comment.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    content = request.form.get("content", "").strip()
    if not content:
        if _wants_json():
            return _json_error("Comment cannot be empty.")
        flash("Comment cannot be empty.", "error")
        return redirect(url_for("retro.view_retro", retro_id=retro.id))

    comment = RetroComment(
        card_id=card.id,
        user_id=current_user.id,
        content=content,
    )
    db.session.add(comment)
    db.session.commit()

    if _wants_json():
        comment_html = render_template(
            "retro/_comment.html",
            comment=comment,
        )
        return jsonify(
            {
                "ok": True,
                "card_id": card.id,
                "html": comment_html,
            }
        )

    flash("Comment added.", "success")
    return redirect(url_for("retro.view_retro", retro_id=retro.id))


@retro_bp.route("/<int:retro_id>/close", methods=["POST"])
@login_required
@admin_required
def close_retro(retro_id):
    retro = Retro.query.get_or_404(retro_id)
    retro.status = "closed"
    db.session.commit()
    flash("Retro closed. Great session!", "success")
    return redirect(url_for("retro.view_retro", retro_id=retro.id))
