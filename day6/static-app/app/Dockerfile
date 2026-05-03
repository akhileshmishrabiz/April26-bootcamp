FROM python:3.13-slim

WORKDIR /app
COPY requirements.txt requirements.txt

RUN pip install -r requirements.txt

copy . .

EXPOSE 8000
CMD ["gunicorn", "app:app", "--bind", "0.0.0.0:8000"]