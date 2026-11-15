import os

from dotenv import load_dotenv

load_dotenv()


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-key")
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DATABASE_URL", "postgresql://postgres:postgres@db:5432/devops_learning"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 300,
        "pool_size": 10,
        "max_overflow": 20,
    }
    DEBUG = bool(int(os.getenv("FLASK_DEBUG", "0")))

    MAX_QUIZ_QUESTIONS = int(os.getenv("MAX_QUIZ_QUESTIONS", "15"))
    PASS_THRESHOLD = int(os.getenv("PASS_THRESHOLD", "70"))
    QUIZ_SESSION_TTL_MINUTES = int(os.getenv("QUIZ_SESSION_TTL_MINUTES", "60"))
    LEADERBOARD_DEFAULT_LIMIT = int(os.getenv("LEADERBOARD_DEFAULT_LIMIT", "50"))
