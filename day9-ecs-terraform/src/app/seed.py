import os
import uuid

from app import db
from app.models.models import Retro, User
from sqlalchemy import inspect, text

ADMIN_EMAIL = "livingdevops@gmail.com"
ADMIN_USERNAME = "livingdevops"


def seed_admin_user():
    admin = User.query.filter_by(email=ADMIN_EMAIL).first()
    password = os.getenv("ADMIN_PASSWORD", "LivingDevops1!")

    if admin is None:
        admin = User(
            username=ADMIN_USERNAME,
            email=ADMIN_EMAIL,
            is_admin=True,
        )
        admin.set_password(password)
        db.session.add(admin)
    else:
        admin.is_admin = True
        if admin.username != ADMIN_USERNAME:
            admin.username = ADMIN_USERNAME

    db.session.commit()


def ensure_schema():
    """Add columns introduced after first deploy (create_all won't alter tables)."""
    inspector = inspect(db.engine)
    user_cols = {c["name"] for c in inspector.get_columns("user")}
    retro_cols = {c["name"] for c in inspector.get_columns("retro")}

    if "is_guest" not in user_cols:
        db.session.execute(
            text('ALTER TABLE "user" ADD COLUMN is_guest BOOLEAN DEFAULT FALSE NOT NULL')
        )
    if "display_name" not in user_cols:
        db.session.execute(
            text('ALTER TABLE "user" ADD COLUMN display_name VARCHAR(80)')
        )
    if "share_token" not in retro_cols:
        db.session.execute(
            text("ALTER TABLE retro ADD COLUMN share_token VARCHAR(32)")
        )
        db.session.execute(
            text("CREATE UNIQUE INDEX IF NOT EXISTS ix_retro_share_token ON retro (share_token)")
        )

    db.session.commit()

    for retro in Retro.query.filter(
        (Retro.share_token.is_(None)) | (Retro.share_token == "")
    ).all():
        retro.share_token = uuid.uuid4().hex
    db.session.commit()
