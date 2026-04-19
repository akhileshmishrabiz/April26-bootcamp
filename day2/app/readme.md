# app needs

<!-- # DB_LINK = "postgresql://{user}:{password}@{host}:5432/{database_name}"

# host = "localhost"
# port = 5432
# database_name = "mydb"
# user = "postgres"
# password = "postgres"

# Run Postgre on ec2 -->


# install postgres




# Export database connection string
export DB_LINK="postgresql://postgres:password@localhost:5432/mydb"

# cd to src

cd src

# Virtual env

python3 -m venv venv

source venv/bin/activate

pip install -r requirements.txt

