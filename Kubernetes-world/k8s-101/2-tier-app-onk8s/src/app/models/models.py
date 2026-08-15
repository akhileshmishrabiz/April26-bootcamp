from app import db, login_manager
from datetime import datetime, timezone
from bcrypt import hashpw, checkpw, gensalt
from flask_login import UserMixin

RETRO_CATEGORIES = {
    "went_well": {"label": "What Went Well", "emoji": "🎉", "color": "#fef08a"},
    "needs_improvement": {
        "label": "What Needs Improvement",
        "emoji": "🔧",
        "color": "#fbcfe8",
    },
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
    cards = db.relationship("RetroCard", backref="retro", cascade="all, delete-orphan")


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
    likes = db.relationship("RetroLike", backref="card", cascade="all, delete-orphan")
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

    __table_args__ = (db.UniqueConstraint("card_id", "user_id", name="uq_retro_like"),)


class RetroComment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    card_id = db.Column(db.Integer, db.ForeignKey("retro_card.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    content = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    author = db.relationship("User", backref="retro_comments")


TICKET_STATUSES = {
    "backlog": {"label": "Backlog", "badge": "badge-muted"},
    "todo": {"label": "To Do", "badge": "badge-info"},
    "in_progress": {"label": "In Progress", "badge": "badge-warning"},
    "in_review": {"label": "In Review", "badge": "badge-info"},
    "done": {"label": "Done", "badge": "badge-success"},
}

TICKET_PRIORITIES = {
    "lowest": {"label": "Lowest", "badge": "badge-muted"},
    "low": {"label": "Low", "badge": "badge-muted"},
    "medium": {"label": "Medium", "badge": "badge-info"},
    "high": {"label": "High", "badge": "badge-warning"},
    "highest": {"label": "Highest", "badge": "badge-danger"},
}

TICKET_TYPES = {
    "bug": {"label": "Bug", "emoji": "🐛"},
    "task": {"label": "Task", "emoji": "✅"},
    "story": {"label": "Story", "emoji": "📖"},
    "epic": {"label": "Epic", "emoji": "⚡"},
    "incident": {"label": "Incident", "emoji": "🚨"},
}

SUBTASK_STATUSES = {
    "todo": {"label": "To Do", "badge": "badge-muted"},
    "in_progress": {"label": "In Progress", "badge": "badge-warning"},
    "done": {"label": "Done", "badge": "badge-success"},
}

PROJECT_KEY = "DEV"

TEAM_ROLES = {
    "owner": {"label": "Owner"},
    "member": {"label": "Member"},
}


class Team(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    description = db.Column(db.Text)
    project_key = db.Column(db.String(10), unique=True, nullable=False, index=True)
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    creator = db.relationship(
        "User", foreign_keys=[created_by], backref="created_teams"
    )
    members = db.relationship(
        "TeamMember", backref="team", cascade="all, delete-orphan"
    )
    tickets = db.relationship("Ticket", backref="team")


class TeamMember(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    team_id = db.Column(db.Integer, db.ForeignKey("team.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    role = db.Column(db.String(20), default="member", nullable=False)
    joined_at = db.Column(db.DateTime, default=datetime.utcnow)

    user = db.relationship("User", backref="team_memberships")

    __table_args__ = (db.UniqueConstraint("team_id", "user_id", name="uq_team_member"),)


class Ticket(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    team_id = db.Column(db.Integer, db.ForeignKey("team.id"), nullable=False)
    ticket_number = db.Column(db.Integer, nullable=False)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    status = db.Column(db.String(20), default="todo", nullable=False)
    priority = db.Column(db.String(20), default="medium", nullable=False)
    issue_type = db.Column(db.String(20), default="task", nullable=False)
    assignee_id = db.Column(db.Integer, db.ForeignKey("user.id"))
    reporter_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    assignee = db.relationship(
        "User", foreign_keys=[assignee_id], backref="assigned_tickets"
    )
    reporter = db.relationship(
        "User", foreign_keys=[reporter_id], backref="reported_tickets"
    )
    subtasks = db.relationship(
        "Subtask",
        backref="ticket",
        cascade="all, delete-orphan",
        order_by="Subtask.created_at",
    )
    comments = db.relationship(
        "TicketComment",
        backref="ticket",
        cascade="all, delete-orphan",
        order_by="TicketComment.created_at",
        foreign_keys="TicketComment.ticket_id",
    )

    __table_args__ = (
        db.UniqueConstraint("team_id", "ticket_number", name="uq_team_ticket_number"),
    )

    @property
    def key(self):
        key = self.team.project_key if self.team else PROJECT_KEY
        return f"{key}-{self.ticket_number}"

    @property
    def subtask_progress(self):
        if not self.subtasks:
            return None
        done = sum(1 for s in self.subtasks if s.status == "done")
        return done, len(self.subtasks)


class Subtask(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    ticket_id = db.Column(db.Integer, db.ForeignKey("ticket.id"), nullable=False)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    status = db.Column(db.String(20), default="todo", nullable=False)
    assignee_id = db.Column(db.Integer, db.ForeignKey("user.id"))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    assignee = db.relationship("User", backref="assigned_subtasks")
    comments = db.relationship(
        "TicketComment",
        backref="subtask",
        cascade="all, delete-orphan",
        order_by="TicketComment.created_at",
        foreign_keys="TicketComment.subtask_id",
    )


class TicketComment(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    ticket_id = db.Column(db.Integer, db.ForeignKey("ticket.id"))
    subtask_id = db.Column(db.Integer, db.ForeignKey("subtask.id"))
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    content = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    author = db.relationship("User", backref="ticket_comments")


class TicketActivity(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    ticket_id = db.Column(db.Integer, db.ForeignKey("ticket.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    activity_type = db.Column(db.String(30), nullable=False)
    field_name = db.Column(db.String(40))
    old_value = db.Column(db.String(200))
    new_value = db.Column(db.String(200))
    content = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    author = db.relationship("User", backref="ticket_activities")
    ticket = db.relationship(
        "Ticket",
        backref=db.backref("activities", order_by="TicketActivity.created_at"),
    )


INCIDENT_SEVERITIES = {
    "sev1": {
        "label": "SEV-1 Critical",
        "badge": "badge-danger",
        "description": "Complete outage — all users affected, revenue impact",
    },
    "sev2": {
        "label": "SEV-2 Major",
        "badge": "badge-danger",
        "description": "Major degradation — significant user impact",
    },
    "sev3": {
        "label": "SEV-3 Minor",
        "badge": "badge-warning",
        "description": "Partial impact — workaround available",
    },
    "sev4": {
        "label": "SEV-4 Low",
        "badge": "badge-info",
        "description": "Minimal impact — cosmetic or internal only",
    },
}

INCIDENT_STATUSES = {
    "triggered": {"label": "Triggered", "badge": "badge-danger"},
    "investigating": {"label": "Investigating", "badge": "badge-warning"},
    "identified": {"label": "Identified", "badge": "badge-warning"},
    "monitoring": {"label": "Monitoring", "badge": "badge-info"},
    "resolved": {"label": "Resolved", "badge": "badge-success"},
    "postmortem_pending": {"label": "Postmortem Pending", "badge": "badge-info"},
    "closed": {"label": "Closed", "badge": "badge-muted"},
}

INCIDENT_STATUS_TRANSITIONS = {
    "triggered": ["investigating", "resolved"],
    "investigating": ["identified", "monitoring", "resolved"],
    "identified": ["monitoring", "resolved"],
    "monitoring": ["resolved"],
    "resolved": ["postmortem_pending", "closed"],
    "postmortem_pending": ["closed"],
    "closed": [],
}

INCIDENT_EVENT_TYPES = {
    "created": {"label": "Created", "icon": "🆕"},
    "status_change": {"label": "Status Change", "icon": "🔄"},
    "severity_change": {"label": "Severity Change", "icon": "⚠️"},
    "alert": {"label": "Alert Fired", "icon": "🔔"},
    "escalation": {"label": "Escalation", "icon": "📣"},
    "mitigation": {"label": "Mitigation", "icon": "🛡️"},
    "deployment": {"label": "Deployment", "icon": "🚀"},
    "communication": {"label": "Communication", "icon": "💬"},
    "note": {"label": "Note", "icon": "📝"},
    "resolved": {"label": "Resolved", "icon": "✅"},
}

POSTMORTEM_STATUSES = {
    "draft": {"label": "Draft", "badge": "badge-muted"},
    "in_review": {"label": "In Review", "badge": "badge-warning"},
    "published": {"label": "Published", "badge": "badge-success"},
    "closed": {"label": "Closed", "badge": "badge-muted"},
}

ON_CALL_ROLES = {
    "primary": {"label": "Primary On-Call"},
    "secondary": {"label": "Secondary On-Call"},
}


class Incident(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    team_id = db.Column(db.Integer, db.ForeignKey("team.id"), nullable=False)
    incident_number = db.Column(db.Integer, nullable=False)
    title = db.Column(db.String(200), nullable=False)
    summary = db.Column(db.Text)
    severity = db.Column(db.String(10), default="sev3", nullable=False)
    status = db.Column(db.String(30), default="triggered", nullable=False)
    service_name = db.Column(db.String(120))
    customer_impact = db.Column(db.Text)
    runbook_url = db.Column(db.String(500))
    commander_id = db.Column(db.Integer, db.ForeignKey("user.id"))
    on_call_user_id = db.Column(db.Integer, db.ForeignKey("user.id"))
    reporter_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    ticket_id = db.Column(db.Integer, db.ForeignKey("ticket.id"))
    detected_at = db.Column(db.DateTime, default=datetime.utcnow)
    acknowledged_at = db.Column(db.DateTime)
    mitigated_at = db.Column(db.DateTime)
    resolved_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )

    team = db.relationship("Team", backref="incidents")
    commander = db.relationship(
        "User", foreign_keys=[commander_id], backref="commanded_incidents"
    )
    on_call_user = db.relationship(
        "User", foreign_keys=[on_call_user_id], backref="on_call_incidents"
    )
    reporter = db.relationship(
        "User", foreign_keys=[reporter_id], backref="reported_incidents"
    )
    ticket = db.relationship(
        "Ticket", backref="linked_incident", foreign_keys=[ticket_id]
    )
    events = db.relationship(
        "IncidentEvent",
        backref="incident",
        cascade="all, delete-orphan",
        order_by="IncidentEvent.created_at",
    )
    postmortem = db.relationship(
        "Postmortem",
        backref="incident",
        uselist=False,
        cascade="all, delete-orphan",
    )

    __table_args__ = (
        db.UniqueConstraint(
            "team_id", "incident_number", name="uq_team_incident_number"
        ),
    )

    @property
    def key(self):
        key = self.team.project_key if self.team else PROJECT_KEY
        return f"{key}-INC-{self.incident_number}"

    @property
    def duration_minutes(self):
        end = self.resolved_at or datetime.utcnow()
        start = self.detected_at or self.created_at
        if not start:
            return None
        delta = end - start
        return max(int(delta.total_seconds() // 60), 0)

    def allowed_statuses(self):
        return INCIDENT_STATUS_TRANSITIONS.get(self.status, [])


class IncidentEvent(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    incident_id = db.Column(db.Integer, db.ForeignKey("incident.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    event_type = db.Column(db.String(30), nullable=False)
    description = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    author = db.relationship("User", backref="incident_events")


class Postmortem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    incident_id = db.Column(
        db.Integer, db.ForeignKey("incident.id"), nullable=False, unique=True
    )
    title = db.Column(db.String(200), nullable=False)
    status = db.Column(db.String(20), default="draft", nullable=False)
    summary = db.Column(db.Text)
    impact = db.Column(db.Text)
    root_cause = db.Column(db.Text)
    contributing_factors = db.Column(db.Text)
    detection_analysis = db.Column(db.Text)
    resolution_summary = db.Column(db.Text)
    what_went_well = db.Column(db.Text)
    what_went_wrong = db.Column(db.Text)
    lessons_learned = db.Column(db.Text)
    timeline_summary = db.Column(db.Text)
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(
        db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )
    published_at = db.Column(db.DateTime)

    author = db.relationship("User", backref="postmortems")
    action_items = db.relationship(
        "PostmortemActionItem",
        backref="postmortem",
        cascade="all, delete-orphan",
        order_by="PostmortemActionItem.created_at",
    )


class PostmortemActionItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    postmortem_id = db.Column(
        db.Integer, db.ForeignKey("postmortem.id"), nullable=False
    )
    title = db.Column(db.String(200), nullable=False)
    owner_id = db.Column(db.Integer, db.ForeignKey("user.id"))
    due_date = db.Column(db.Date)
    status = db.Column(db.String(20), default="open", nullable=False)
    ticket_id = db.Column(db.Integer, db.ForeignKey("ticket.id"))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    owner = db.relationship("User", backref="postmortem_action_items")
    ticket = db.relationship("Ticket", backref="postmortem_action_items")


class OnCallSchedule(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    team_id = db.Column(db.Integer, db.ForeignKey("team.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    role = db.Column(db.String(20), default="primary", nullable=False)
    start_at = db.Column(db.DateTime, nullable=False)
    end_at = db.Column(db.DateTime, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    team = db.relationship("Team", backref="on_call_schedules")
    user = db.relationship("User", backref="on_call_shifts")


WHEEL_MODES = {
    "elimination": {
        "label": "Elimination",
        "description": "Each speaker is removed from the wheel after being picked",
    },
    "repeat": {
        "label": "Round Robin",
        "description": "Everyone stays on the wheel — track who has spoken",
    },
}

WHEEL_NAME_STATUSES = {
    "waiting": {"label": "Waiting", "badge": "badge-info"},
    "spoken": {"label": "Spoken", "badge": "badge-success"},
    "skipped": {"label": "Absent", "badge": "badge-warning"},
}

WHEEL_COLORS = [
    "#5b21b6",
    "#ec4899",
    "#f97316",
    "#34d399",
    "#38bdf8",
    "#fde047",
    "#ef4444",
    "#8b5cf6",
    "#14b8a6",
    "#f59e0b",
    "#6366f1",
    "#84cc16",
]


class SpeakWheel(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    mode = db.Column(db.String(20), default="elimination", nullable=False)
    status = db.Column(db.String(20), default="open", nullable=False)
    share_token = db.Column(db.String(32), unique=True, index=True)
    team_id = db.Column(db.Integer, db.ForeignKey("team.id"))
    created_by = db.Column(db.Integer, db.ForeignKey("user.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    creator = db.relationship("User", backref="speak_wheels")
    team = db.relationship("Team", backref="speak_wheels")
    names = db.relationship(
        "SpeakWheelName",
        backref="wheel",
        cascade="all, delete-orphan",
        order_by="SpeakWheelName.created_at",
    )
    picks = db.relationship(
        "SpeakWheelPick",
        backref="wheel",
        cascade="all, delete-orphan",
        order_by="SpeakWheelPick.picked_at.desc()",
    )

    @property
    def active_names(self):
        if self.mode == "repeat":
            return self.names
        return [n for n in self.names if n.status == "waiting"]

    @property
    def progress(self):
        total = len(self.names)
        if not total:
            return 0, 0
        spoken = sum(1 for n in self.names if n.status == "spoken" or n.pick_count > 0)
        if self.mode == "elimination":
            spoken = sum(1 for n in self.names if n.status == "spoken")
        return spoken, total


class SpeakWheelName(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    wheel_id = db.Column(db.Integer, db.ForeignKey("speak_wheel.id"), nullable=False)
    name = db.Column(db.String(120), nullable=False)
    status = db.Column(db.String(20), default="waiting", nullable=False)
    color_index = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    picks = db.relationship(
        "SpeakWheelPick",
        backref="name_entry",
        cascade="all, delete-orphan",
    )

    @property
    def pick_count(self):
        return len(self.picks)


class SpeakWheelPick(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    wheel_id = db.Column(db.Integer, db.ForeignKey("speak_wheel.id"), nullable=False)
    name_id = db.Column(
        db.Integer, db.ForeignKey("speak_wheel_name.id"), nullable=False
    )
    picked_by = db.Column(db.Integer, db.ForeignKey("user.id"))
    picked_at = db.Column(db.DateTime, default=datetime.utcnow)

    picker = db.relationship("User", backref="wheel_picks")


class GameScore(db.Model):
    __tablename__ = "game_scores"

    id = db.Column(db.Integer, primary_key=True)
    player_name = db.Column(db.String(80), nullable=False, index=True)
    game_type = db.Column(db.String(50), nullable=False, index=True)
    score = db.Column(db.Integer, nullable=False, default=0)
    details = db.Column(db.Text, nullable=True)
    played_at = db.Column(db.DateTime, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            "id": self.id,
            "player_name": self.player_name,
            "game_type": self.game_type,
            "score": self.score,
            "details": self.details,
            "played_at": self.played_at.isoformat() if self.played_at else None,
        }


class PlayerAchievement(db.Model):
    __tablename__ = "player_achievements"

    id = db.Column(db.Integer, primary_key=True)
    player_name = db.Column(db.String(80), nullable=False, index=True)
    badge_id = db.Column(db.String(50), nullable=False)
    earned_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.UniqueConstraint("player_name", "badge_id", name="uq_player_badge"),
    )

    def to_dict(self):
        return {
            "badge_id": self.badge_id,
            "earned_at": self.earned_at.isoformat() if self.earned_at else None,
        }


class PlayerProfile(db.Model):
    __tablename__ = "player_profiles"

    id = db.Column(db.Integer, primary_key=True)
    player_name = db.Column(db.String(80), unique=True, nullable=False)
    games_played = db.Column(db.Integer, default=0)
    total_score = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
