#!/bin/bash

sudo yum install git -y
git clone https://github.com/akhileshmishrabiz/April26-bootcamp


cd April26-bootcamp/day2/app
sudo chmod u+x run.sh

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DB_LINK=postgresql://postgres:Admin1234@aprilasgapp.cvik8accw2tk.ap-south-1.rds.amazonaws.com:5432/mydb
gunicorn run:app --bind 0.0.0.0:8000 &