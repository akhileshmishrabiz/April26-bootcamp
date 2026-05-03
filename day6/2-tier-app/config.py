import os

variable_which_i_wont_use = "this is a variable which i wont use"


class Config:
    SQLALCHEMY_DATABASE_URI = os.getenv("DB_LINK", "postgresql://postgres:postgres@localhost:5432/mydb")
    SQLALCHEMY_TRACK_MODIFICATIONS = False

# DB_LINK = "postgresql://{user}:{password}@{host}:5432/{database_name}"

# host = "localhost"
# port = 5432
# database_name = "mydb"
# user = "postgres"
# password = "postgres"