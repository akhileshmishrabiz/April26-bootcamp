"""Add quiz sessions and attempts for leaderboard

Revision ID: b7c3d4e5f6a1
Revises: a05e32811b08
Create Date: 2026-06-14 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


revision = "b7c3d4e5f6a1"
down_revision = "a05e32811b08"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "quiz_sessions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("topic_id", sa.Integer(), nullable=False),
        sa.Column("player_name", sa.String(length=30), nullable=False),
        sa.Column("question_data", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("submitted", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["topic_id"], ["topics.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_quiz_sessions_topic_id", "quiz_sessions", ["topic_id"])

    op.create_table(
        "quiz_attempts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("player_name", sa.String(length=30), nullable=False),
        sa.Column("topic_id", sa.Integer(), nullable=False),
        sa.Column("score", sa.Float(), nullable=False),
        sa.Column("correct_count", sa.Integer(), nullable=False),
        sa.Column("total_questions", sa.Integer(), nullable=False),
        sa.Column("time_taken_seconds", sa.Integer(), nullable=False),
        sa.Column("passed", sa.Boolean(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["topic_id"], ["topics.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_quiz_attempts_player_name", "quiz_attempts", ["player_name"])
    op.create_index("ix_quiz_attempts_topic_id", "quiz_attempts", ["topic_id"])
    op.create_index("ix_quiz_attempts_completed_at", "quiz_attempts", ["completed_at"])
    op.create_index("ix_quiz_attempts_topic_score", "quiz_attempts", ["topic_id", "score"])
    op.create_index(
        "ix_quiz_attempts_player_topic", "quiz_attempts", ["player_name", "topic_id"]
    )


def downgrade():
    op.drop_index("ix_quiz_attempts_player_topic", table_name="quiz_attempts")
    op.drop_index("ix_quiz_attempts_topic_score", table_name="quiz_attempts")
    op.drop_index("ix_quiz_attempts_completed_at", table_name="quiz_attempts")
    op.drop_index("ix_quiz_attempts_topic_id", table_name="quiz_attempts")
    op.drop_index("ix_quiz_attempts_player_name", table_name="quiz_attempts")
    op.drop_table("quiz_attempts")
    op.drop_index("ix_quiz_sessions_topic_id", table_name="quiz_sessions")
    op.drop_table("quiz_sessions")
