from datetime import datetime, timezone

from devops_quest import db


class Player(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(40), unique=True, nullable=False)
    avatar = db.Column(db.String(12), nullable=False, default="🧑‍💻")
    xp = db.Column(db.Integer, nullable=False, default=0)
    streak = db.Column(db.Integer, nullable=False, default=0)
    energy = db.Column(db.Integer, nullable=False, default=5)
    last_played_at = db.Column(db.DateTime(timezone=True))
    created_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    completions = db.relationship(
        "Completion", back_populates="player", cascade="all, delete-orphan"
    )

    @property
    def level(self):
        return self.xp // 100 + 1

    @property
    def rank(self):
        if self.xp >= 500:
            return "Platform Guardian"
        if self.xp >= 250:
            return "Pipeline Ranger"
        if self.xp >= 100:
            return "Container Cadet"
        return "YAML Rookie"

    def to_dict(self):
        return {
            "id": self.id,
            "username": self.username,
            "avatar": self.avatar,
            "xp": self.xp,
            "level": self.level,
            "rank": self.rank,
            "streak": self.streak,
            "energy": self.energy,
            "badges": self.badges(),
            "completed": len(self.completions),
        }

    def badges(self):
        badges = []
        completed = len(self.completions)
        if completed >= 1:
            badges.append("First Deploy")
        if completed >= 3:
            badges.append("Pipeline Builder")
        if self.streak >= 3:
            badges.append("On-call Hero")
        if self.xp >= 500:
            badges.append("DevOps Legend")
        return badges


class Completion(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    player_id = db.Column(db.Integer, db.ForeignKey("player.id"), nullable=False)
    challenge_slug = db.Column(db.String(80), nullable=False)
    score = db.Column(db.Integer, nullable=False)
    attempts = db.Column(db.Integer, nullable=False, default=1)
    completed_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    player = db.relationship("Player", back_populates="completions")

    __table_args__ = (
        db.UniqueConstraint("player_id", "challenge_slug", name="uq_player_challenge"),
    )
