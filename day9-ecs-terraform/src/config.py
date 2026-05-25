import os


class Config:
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DB_LINK", "sqlite:////tmp/student_portal.db"
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
