from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

from .models import Question, QuizAttempt, QuizSession, Topic, WikiPage  # noqa: E402

__all__ = ["db", "Topic", "Question", "WikiPage", "QuizSession", "QuizAttempt"]
