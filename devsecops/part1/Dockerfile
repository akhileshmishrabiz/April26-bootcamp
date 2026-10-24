FROM python:latest

WORKDIR /app

COPY . .

RUN pip install -r requirements.txt

ENV AWS_REGION=us-east-1

EXPOSE 5000

CMD ["python", "app.py"]
