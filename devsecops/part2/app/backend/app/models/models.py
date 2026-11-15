import random
import uuid
from datetime import datetime, timedelta

from . import db


class Topic(db.Model):
    __tablename__ = "topics"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    description = db.Column(db.Text, nullable=False)
    slug = db.Column(db.String(100), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    questions = db.relationship(
        "Question", backref="topic", lazy=True, cascade="all, delete-orphan"
    )
    quiz_attempts = db.relationship("QuizAttempt", backref="topic", lazy=True)

    def to_dict(self):
        return {
            "id": self.slug,
            "title": self.name,
            "description": self.description,
            "question_count": len(self.questions),
        }


class Question(db.Model):
    __tablename__ = "questions"

    id = db.Column(db.Integer, primary_key=True)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"), nullable=False)
    question_text = db.Column(db.Text, nullable=False)
    options = db.Column(db.JSON, nullable=False)
    correct_answer = db.Column(db.Integer, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def shuffle_options(self):
        correct_option = self.options[self.correct_answer]
        options_with_indices = list(enumerate(self.options))
        random.shuffle(options_with_indices)

        new_options = []
        new_correct_index = None
        for _, option in options_with_indices:
            new_options.append(option)
            if option == correct_option:
                new_correct_index = len(new_options) - 1

        return {"options": new_options, "correct_index": new_correct_index}

    def to_public_dict(self):
        """Return shuffled question for quiz takers — never exposes the answer."""
        shuffled = self.shuffle_options()
        return {
            "id": self.id,
            "question": self.question_text,
            "options": shuffled["options"],
        }

    def to_admin_dict(self):
        """Full question payload for the question manager."""
        return {
            "id": self.id,
            "question": self.question_text,
            "options": self.options,
            "correct_answer": self.correct_answer,
        }

    def to_dict(self, shuffle=True):
        if shuffle:
            return self.to_public_dict()
        return self.to_admin_dict()


class QuizSession(db.Model):
    __tablename__ = "quiz_sessions"

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"), nullable=False, index=True)
    player_name = db.Column(db.String(30), nullable=False)
    question_data = db.Column(db.JSON, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    submitted = db.Column(db.Boolean, default=False, nullable=False)

    topic = db.relationship("Topic", backref="quiz_sessions")

    @staticmethod
    def default_expiry(minutes=60):
        return datetime.utcnow() + timedelta(minutes=minutes)

    def is_expired(self):
        return datetime.utcnow() > self.expires_at

    def grade(self, answers):
        correct_count = 0
        review = []
        total = len(self.question_data)

        for item in self.question_data:
            qid = str(item["id"])
            submitted = answers.get(qid)
            if submitted is None:
                submitted = answers.get(int(qid)) if qid.isdigit() else None
            try:
                submitted_index = int(submitted)
            except (TypeError, ValueError):
                submitted_index = None

            is_correct = submitted_index == item["correct_index"]
            if is_correct:
                correct_count += 1

            question = Question.query.get(item["id"])
            review.append(
                {
                    "question_id": item["id"],
                    "question": question.question_text if question else "",
                    "options": item["options"],
                    "your_answer": submitted_index,
                    "correct_answer": item["correct_index"],
                    "is_correct": is_correct,
                }
            )

        score = round((correct_count / total) * 100, 1) if total else 0
        return correct_count, total, score, review


class QuizAttempt(db.Model):
    __tablename__ = "quiz_attempts"

    id = db.Column(db.Integer, primary_key=True)
    player_name = db.Column(db.String(30), nullable=False, index=True)
    topic_id = db.Column(db.Integer, db.ForeignKey("topics.id"), nullable=False, index=True)
    score = db.Column(db.Float, nullable=False)
    correct_count = db.Column(db.Integer, nullable=False)
    total_questions = db.Column(db.Integer, nullable=False)
    time_taken_seconds = db.Column(db.Integer, nullable=False, default=0)
    passed = db.Column(db.Boolean, nullable=False, default=False)
    completed_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)

    __table_args__ = (
        db.Index("ix_quiz_attempts_topic_score", "topic_id", "score"),
        db.Index("ix_quiz_attempts_player_topic", "player_name", "topic_id"),
    )

    def to_leaderboard_dict(self, rank=None):
        return {
            "rank": rank,
            "player_name": self.player_name,
            "score": self.score,
            "correct_count": self.correct_count,
            "total_questions": self.total_questions,
            "time_taken_seconds": self.time_taken_seconds,
            "passed": self.passed,
            "completed_at": self.completed_at.isoformat(),
            "topic_slug": self.topic.slug if self.topic else None,
            "topic_name": self.topic.name if self.topic else None,
        }

    def to_history_dict(self):
        return {
            "id": self.id,
            "player_name": self.player_name,
            "score": self.score,
            "correct_count": self.correct_count,
            "total_questions": self.total_questions,
            "time_taken_seconds": self.time_taken_seconds,
            "passed": self.passed,
            "completed_at": self.completed_at.isoformat(),
            "topic_slug": self.topic.slug if self.topic else None,
            "topic_name": self.topic.name if self.topic else None,
        }


class WikiPage(db.Model):
    __tablename__ = "wiki_pages"

    id = db.Column(db.Integer, primary_key=True)
    slug = db.Column(db.String(100), unique=True, nullable=False)
    title = db.Column(db.String(200), nullable=False)
    content = db.Column(db.Text, nullable=False)
    category = db.Column(db.String(100), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    author = db.Column(db.String(100), nullable=True)
    is_published = db.Column(db.Boolean, default=True)

    def to_dict(self):
        return {
            "id": self.id,
            "slug": self.slug,
            "title": self.title,
            "content": self.content,
            "category": self.category,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "author": self.author,
            "is_published": self.is_published,
        }
