# Intentionally weak Dockerfile for DevSecOps scanner practice.
FROM python:3.12

WORKDIR /app

COPY . .

RUN pip install -r requirements.txt
RUN chmod -R 777 /app

EXPOSE 5000

# Training issues include running as root and using a shell-form command.
CMD gunicorn --bind 0.0.0.0:5000 app:app
