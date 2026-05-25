from app import db, login_manager
from datetime import datetime, timezone
from bcrypt import hashpw, checkpw, gensalt
from flask_login import UserMixin


RETRO_CATEGORIES = {
    "went_well": {"label": "What Went Well", "emoji": "🎉", "color": "#fef08a"},
    "needs_improvement": {"label": "What Needs Improvement", "emoji": "🔧", "color": "#fbcfe8"},
    "action_items": {"label": "Action Items", "emoji": "📋", "color": "#bbf7d0"},
}


@login_manager.user_loader
def load_user(id):
    return db.session.get(User, int(id))


class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    is_admin = db.Column(db.Boolean, default=False, nullable=False)
    is_guest = db.Column(db.Boolean, default=False, nullable=False)
    display_name = db.Column(db.String(80))

    def set_password(self, password):
        self.password_hash = hashpw(password.encode("utf-8"), gensalt()).decode("utf-8")

    def check_password(self, password):
        return checkpw(password.encode("utf-8"), self.password_hash.encode("utf-8"))

    @property
    def label(self):
        return self.display_name or self.username


class Student(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    attendance = db.relationship("Attendance", backref="student", lazy=True)


class Attendance(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(
        db.Date, nullable=False, default=lambda: datetime.now(timezone.utc)
    )
    status = db.Column(db.String(10), nullable=False)
    student_id = db.Column(db.Integer, db.ForeignKey("student.id"), nullable=False)


class Class(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(db.Date, nullable=False)
    time = db.Column(db.String(50), nullable=False)
    session_link = db.Column(db.String(500))
    code_link = db.Column(db.String(500))
    recording_link = db.Column(db.String(500))
    resource_link = db.Column(db.String(500))
    remarks = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)


class Assignment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    due_date = db.Column(db.Date, nullable=False)
    link = db.Column(db.String(500))
    is_completed = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)


class Announcement(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    content = db.Column(db.Text, nullable=False)
    is_pinned = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)


class Retro(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    status = db.Column(db.String(20), default="open", nullable=False)
    share_token = db.Column(db.String(32), unique=True, index=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)

    creator = db.relationship("User", backref="retros")
    participants = db.relationship(
        "RetroParticipant", backref="retro", cascade="all, delete-orphan"
    )
    cards = db.relationship(
        "RetroCard", backref="retro", cascade="all, delete-orphan"
    )


class RetroParticipant(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    retro_id = db.Column(db.Integer, db.ForeignKey("retro.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    joined_at = db.Column(db.DateTime, default=datetime.utcnow)

    user = db.relationship("User", backref="retro_participations")

    __table_args__ = (
        db.UniqueConstraint("retro_id", "user_id", name="uq_retro_participant"),
    )


class RetroCard(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    retro_id = db.Column(db.Integer, db.ForeignKey("retro.id"), nullable=False)
    category = db.Column(db.String(30), nullable=False)
    content = db.Column(db.Text, nullable=False)
    author_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    author = db.relationship("User", backref="retro_cards")
    likes = db.relationship(
        "RetroLike", backref="card", cascade="all, delete-orphan"
    )
    comments = db.relationship(
        "RetroComment",
        backref="card",
        cascade="all, delete-orphan",
        order_by="RetroComment.created_at",
    )


class RetroLike(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    card_id = db.Column(db.Integer, db.ForeignKey("retro_card.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint("card_id", "user_id", name="uq_retro_like"),
    )


class RetroComment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    card_id = db.Column(db.Integer, db.ForeignKey("retro_card.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    content = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    author = db.relationship("User", backref="retro_comments")
