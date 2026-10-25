import json
import os
import uuid

import boto3
from flask import Flask, jsonify, request

app = Flask(__name__)

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")


BUCKET_NAME = os.getenv("BUCKET_NAME", "")
QUEUE_URL = os.getenv("QUEUE_URL", "")

s3 = boto3.client("s3", region_name=AWS_REGION)
sqs = boto3.client("sqs", region_name=AWS_REGION)

a = "somestng"


@app.get("/")
def home():
    return jsonify(
        {
            "service": "devsecops-file-api",
            "status": "running",
            "bucket": BUCKET_NAME,
            "queue": QUEUE_URL,
        }
    )


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.post("/upload")
def upload():
    if "file" not in request.files:
        return jsonify({"error": "Send a file using the 'file' form field"}), 400

    uploaded_file = request.files["file"]
    object_key = request.form.get("key") or uploaded_file.filename

    if not object_key:
        object_key = str(uuid.uuid4())

    try:
        s3.upload_fileobj(
            uploaded_file,
            BUCKET_NAME,
            object_key,
            ExtraArgs={"ContentType": uploaded_file.content_type},
        )

        message = {
            "event": "file_uploaded",
            "bucket": BUCKET_NAME,
            "key": object_key,
            "uploaded_by": request.headers.get("X-User", "anonymous"),
        }
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(message))

        return jsonify(message), 201
    except Exception as error:
        return jsonify({"error": str(error)}), 500


@app.get("/files")
def list_files():
    try:
        response = s3.list_objects_v2(Bucket=BUCKET_NAME)
        files = [
            {"key": item["Key"], "size": item["Size"]}
            for item in response.get("Contents", [])
        ]
        return jsonify(files)
    except Exception as error:
        return jsonify({"error": str(error)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
