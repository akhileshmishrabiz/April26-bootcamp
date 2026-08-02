import os

_db_uri = os.getenv("DB_LINK", "sqlite:////tmp/student_portal.db")


class Config:
    SQLALCHEMY_DATABASE_URI = _db_uri
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    if _db_uri.startswith("postgresql"):
        # pool_size should roughly match gunicorn thread count (default 8).
        SQLALCHEMY_ENGINE_OPTIONS = {
            "pool_size": int(os.getenv("DB_POOL_SIZE", "5")),
            "max_overflow": int(os.getenv("DB_MAX_OVERFLOW", "3")),
            "pool_timeout": int(os.getenv("DB_POOL_TIMEOUT", "30")),
            "pool_pre_ping": True,
            "pool_recycle": int(os.getenv("DB_POOL_RECYCLE", "300")),
        }
