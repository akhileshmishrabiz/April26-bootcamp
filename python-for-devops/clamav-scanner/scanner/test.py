# # import boto3
# # # import json
# # # queue_url = 'https://sqs.ap-south-1.amazonaws.com/879381241087/clamav-automation-queue'
# # # sqs_client = boto3.client('sqs')
# # # response = sqs_client.receive_message(
# # #     QueueUrl=queue_url,
# # # )

# # # # print(response.get('Messages')[0].get("MessageId"),
# # # # type(response.get('Messages')[0].get('Body')),
# # # # # response.get('Messages')[0].get('Body').get("Records")[0].get("s3").get("object").get("key")
# # # # )


# # # message = response.get('Messages')[0]
# # # message_id = message.get('MessageId')
# # # message_body = json.loads(message.get('Body'))
# # # print(message_body.get("Records")[0].get("s3").get("bucket").get("name"),
# # # message_body.get("Records")[0].get("s3").get("object").get("key"))



# # # scan file for malware
# # # import subprocess
# # # sns_client = boto3.client('sns')
# # # file_path = 'eicar.txt'
# # # result = subprocess.run(['clamscan', file_path], capture_output=True, text=True)

# # # # print(result.stdout, type(result.stdout))
# # # if result.stdout.splitlines()[6].split()[2] == "0":
# # #     print("CLEAN")
# # # else:
# # #     print("DIRTY")
# # #     response = sns_client.publish(
# # #     TopicArn='arn:aws:sns:ap-south-1:879381241087:alarm-notification',
# # #     Message='Malware found in file_path',
# # #     Subject='ClamAV Scanner'
# # # )
# # #     print(response)


# # # send sns notification to topic alarm-notification

# # import subprocess

# # def clamav_db_download_local():
# #     try:
# #         result = subprocess.run(['freshclam'], capture_output=True, text=True)
# #         print(result.stdout)
# #         print("ClamAV database downloaded successfully ")
# #         return True
# #     except Exception as e:
# #         print(e)
# #         return False

# # def upload_clamav_db_to_s3():
# #     try:
# #         s3_client = boto3.client('s3')
# #         s3_client.upload_file('/var/lib/clamav/clamav.db', 'clamav-db', 'clamav.db')
# #         print("ClamAV database uploaded to S3 successfully")
# #         return True
# #     except Exception as e:
# #         print(e)
# #         return False
# # def download_clamav_db_from_s3():
# #     try:
# #         s3_client.download_file('clamav-db', 'clamav.db', '/var/lib/clamav/clamav.db')
# #         print("ClamAV database downloaded from S3 successfully")
# #         return True
# #     except Exception as e:
# #         print(e)
# #         return False

# # clamav_db_download_local()

# import subprocess
# import os
# import boto3
# s3_client = boto3.client('s3')
# DatabaseDirectory = '/opt/homebrew/var/lib/clamav'

# bucket_name = "clamav-db-879381241087"
# key = "clamav/"

# def clamav_db_download_local(DatabaseDirectory):
#     try:
#         result = subprocess.run(['freshclam'], capture_output=True, text=True)
#         print(result.stdout)
#         print(f"ClamAV database downloaded successfully  to {DatabaseDirectory}")
#         return True
#     except Exception as e:
#         print(e)
#         return False

# # upload all db realted files from local database directory (DatabaseDirectory) to s3
# def upload_clamav_db_to_s3(DatabaseDirectory, bucket_name, key):
#     try:
#         for file in os.listdir(DatabaseDirectory):
#             s3_client.upload_file(os.path.join(DatabaseDirectory, file), bucket_name, os.path.join(key, file))
#         print("ClamAV database uploaded to S3 successfully")
#         return True
#     except Exception as e:
#         print(e)
#         return False

# # download add .cdv files from s3 to local database directory
# def download_clamav_db_from_s3(bucket_name, key, DatabaseDirectory):
#     list_of_files = s3_client.list_objects(Bucket=bucket_name, Prefix=key)['Contents']
#     try:
#         for file in list_of_files:
#             s3_client.download_file(bucket_name, file['Key'], os.path.join(DatabaseDirectory, file['Key'].split('/')[-1]))
#         print(f"ClamAV database downloaded from S3 successfully to {DatabaseDirectory}")
#         return True
#     except Exception as e:
#         print(e)
#         return False
 


# # clamav_db_download_local(DatabaseDirectory)
# # upload_clamav_db_to_s3(DatabaseDirectory, bucket_name, key)
# download_clamav_db_from_s3(bucket_name, key, DatabaseDirectory)


# import boto3
# sqs_client = boto3.client('sqs')
# queue_url = 'https://sqs.ap-south-1.amazonaws.com/879381241087/clamav-automation-queue'
# message_id = 'c3a828f6-b1f7-4781-83e4-4dfa082b20e0'
# def delete_message_from_queue(queue_url, message_id):
#     try:
#         sqs_client.delete_message(QueueUrl=queue_url, ReceiptHandle=message_id)
#         return True
#     except Exception as e:
#         print(e)
#         return False

# delete_message_from_queue(queue_url, message_id)

import boto3
import subprocess
s3_client = boto3.client('s3')
bucket_name = "landing-bucket-879381241087"
result = "CLEAN"

def create_tags_for_s3_object(bucket_name, key, result):
    try:
        s3_client.put_object_tagging(Bucket=bucket_name, Key=key, Tagging={'TagSet': [{'Key': 'scanned', 'Value': 'true'}, {'Key': 'result', 'Value': result}]})
        return True
    except Exception as e:
        print(e)
        # return False


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
key = "dirty.txt"
result = scan_file_for_malware(key)
print(f"Scan result: {result}")
print(f"Scan result: {result}")
create_tags_output = create_tags_for_s3_object(bucket_name, key, result)
print(f"Create tags output: {create_tags_output}")