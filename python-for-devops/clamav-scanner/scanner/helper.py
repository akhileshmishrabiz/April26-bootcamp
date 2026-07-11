import boto3
import json
import subprocess
import os
from urllib.parse import unquote_plus
sqs_client = boto3.client('sqs')
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')


# clean_bucket_name = "clamav-db-879381241087"
# clamav_dbkey = "clamav/"
# clamav_db_bucket_name = "clamav-db-879381241087"
# DatabaseDirectory = "/opt/homebrew/var/lib/clamav"
# sns_topic_arn = "arn:aws:sns:ap-south-1:879381241087:alarm-notification"
# queue_url = "https://sqs.ap-south-1.amazonaws.com/879381241087/clamav-scanner-queue"

def get_message_from_queue(queue_url):
    try:
        response = sqs_client.receive_message(
            QueueUrl=queue_url,
        )
        message = response.get('Messages')[0]
        ReceiptHandle = message.get('ReceiptHandle')
        message_body = json.loads(message.get('Body'))
        bucket_name = message_body.get("Records")[0].get("s3").get("bucket").get("name")
        key= message_body.get("Records")[0].get("s3").get("object").get("key")

        return ReceiptHandle, bucket_name, key
    except Exception as e:
        print(e)
        return None

def download_file_from_s3(bucket_name, key, local_path):
    try:
        s3_client.download_file(bucket_name, key, local_path)
        return True
    except Exception as e:
        print(e)
        return False


def upload_file_to_s3(destination_bucket_name, key, local_path):
    try:
        s3_client.upload_file(local_path, destination_bucket_name, key)
        return True
    except Exception as e:
        print(e)
        return False


def scan_file_for_malware(file_path):
    result = subprocess.run(['clamscan', file_path], capture_output=True, text=True)
    # if result.stdout.splitlines()[6].split()[2] == "0":
    #     return "CLEAN"
    # else:
    #     return "DIRTY"
    command_return_code = result.returncode
    if command_return_code == 0:
        return "CLEAN"
    else:
        return "DIRTY"


# creat tags for s3 object -> scanned = true, result = "CLEAN" or "DIRTY"
def create_tags_for_s3_object(bucket_name, key, result):
    try:
        decoded_key = unquote_plus(key)
        s3_client.put_object_tagging(Bucket=bucket_name, Key=decoded_key, Tagging={'TagSet': [{'Key': 'SCANNED', 'Value': 'true'}, {'Key': 'RESULT', 'Value': result}]})
        return True
    except Exception as e:
        print(e)
        return False

def send_sns_notification(key, sns_topic_arn):
    response = sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=f'Malware found in {key}',
        Subject='ClamAV Scanner'
    )
    return response

def clamav_db_download():
    try:
        subprocess.run(['freshclam'], capture_output=True, text=True)
    except Exception as e:
        print(e)
        return False


def clamav_db_download_local(DatabaseDirectory):
    try:
        result = subprocess.run(['freshclam'], capture_output=True, text=True)
        print(result.stdout)
        print(f"ClamAV database downloaded successfully  to {DatabaseDirectory}")
        return True
    except Exception as e:
        print(e)
        return False

# upload all .cdv files from local database directory (DatabaseDirectory) to s3
def upload_clamav_db_to_s3(DatabaseDirectory, bucket_name):
    try:
        for file in os.listdir(DatabaseDirectory):
            if file.endswith('.cdv'):
                s3_client.upload_file(os.path.join(DatabaseDirectory, file), bucket_name, file)
        print("ClamAV database uploaded to S3 successfully")
        return True
    except Exception as e:
        print(e)
        return False

# download add .cdv files from s3 to local database directory
def download_clamav_db_from_s3(bucket_name, key, DatabaseDirectory):
    try:
        for file in s3_client.list_objects(Bucket=bucket_name, Prefix=key)['Contents']:
            s3_client.download_file(bucket_name, file['Key'], os.path.join(DatabaseDirectory, file['Key']))
    except Exception as e:
        print(e)
        return False


def clamav_db_download_local(DatabaseDirectory):
    try:
        result = subprocess.run(['freshclam'], capture_output=True, text=True)
        print(result.stdout)
        print(f"ClamAV database downloaded successfully  to {DatabaseDirectory}")
        return True
    except Exception as e:
        print(e)
        return False

# upload all db realted files from local database directory (DatabaseDirectory) to s3
def upload_clamav_db_to_s3(DatabaseDirectory, bucket_name, key):
    try:
        for file in os.listdir(DatabaseDirectory):
            s3_client.upload_file(os.path.join(DatabaseDirectory, file), bucket_name, os.path.join(key, file))
        print("ClamAV database uploaded to S3 successfully")
        return True
    except Exception as e:
        print(e)
        return False

# download add .cdv files from s3 to local database directory
def download_clamav_db_from_s3(bucket_name, key, DatabaseDirectory):
    list_of_files = s3_client.list_objects(Bucket=bucket_name, Prefix=key)['Contents']
    try:
        for file in list_of_files:
            download_file_from_s3(bucket_name, file['Key'], os.path.join(DatabaseDirectory, file['Key'].split('/')[-1]))
        print(f"ClamAV database downloaded from S3 successfully to {DatabaseDirectory}")
        return True
    except Exception as e:
        print(e)
        return False

def local_freshclam_db_download():
    try:
        result = subprocess.run(['freshclam'], capture_output=True, text=True)
        print(result.stdout)
        print("ClamAV database downloaded successfully ")
        return True
    except Exception as e:
        print(e)
        return False

def delete_message_from_queue(queue_url, ReceiptHandle):
    try:
        sqs_client.delete_message(QueueUrl=queue_url, ReceiptHandle=ReceiptHandle)
        return True
    except Exception as e:
        print(e)
        return False

