import helper
import os
import argparse


# clean_bucket_name = "clean-bucket-879381241087"
clean_bucket_name = os.getenv("CLEAN_BUCKET_NAME","clean-bucket-879381241087")
# clamav_dbkey = os.getenv("CLAMAV_DB_KEY","clamav/")
clamav_dbkey = os.getenv("CLAMAV_DB_KEY","clamav/")

# clamav_db_bucket_name = "clamav-db-879381241087"
clamav_db_bucket_name = os.getenv("CLAMAV_DB_BUCKET_NAME","clamav-db-879381241087")
# DatabaseDirectory = "/var/lib/clamav"
DatabaseDirectory = os.getenv("DATABASE_DIRECTORY","/opt/homebrew/var/lib/clamav")
# sns_topic_arn = "arn:aws:sns:ap-south-1:879381241087:alarm-notification"
sns_topic_arn = os.getenv("SNS_TOPIC_ARN","arn:aws:sns:ap-south-1:879381241087:alarm-notification")
# queue_url = "https://sqs.ap-south-1.amazonaws.com/879381241087/clamav-automation-queue"
queue_url = os.getenv("QUEUE_URL","https://sqs.ap-south-1.amazonaws.com/879381241087/clamav-automation-queue")


def scan():
    
    fetch_queue = helper.get_message_from_queue(queue_url)
    if fetch_queue is not None:
        local_path = "."
        ReceiptHandle, download_bucket_name, download_key = fetch_queue
        # print(ReceiptHandle, download_bucket_name, download_key)
        # downlaod the file to scan for malware
        print(f"Downloading file from S3: bucket_name: {download_bucket_name} key: {download_key}")
        output =helper.download_file_from_s3(download_bucket_name, download_key, os.path.join(local_path, download_key))
        print(f"Download file from S3 output: {output}")
        print(f"File to scan for malware downloaded will be at {local_path}/{download_key}")

        ## update the clamav db
        ## if we have seperate db bucket, then download the db from s3 to local database directory
        ## given you alredy have a clamav db bucket, then download the db from s3 to local database directory
        
        # helper.download_clamav_db_from_s3(clamav_db_bucket_name, clamav_dbkey, DatabaseDirectory)
        
        # else  do a new freshclam download to local database directory
        helper.local_freshclam_db_download()

        # scan the file for malware
        file_to_scan = os.path.join(local_path, download_key)
        result = helper.scan_file_for_malware(file_to_scan)
        print(f"Scan result: {result}")
        print(f"Creating tags for s3 object: bucket_name: {download_bucket_name} key: {download_key} result: {result}")
        create_tags_output = helper.create_tags_for_s3_object(download_bucket_name, download_key, result)
        print(f"Create tags for s3 object output: {create_tags_output}")

        if result == "DIRTY":
            print(f"Malware found in file {file_to_scan}")
            helper.create_tags_for_s3_object(download_bucket_name, download_key, "DIRTY")
            helper.send_sns_notification(file_to_scan, sns_topic_arn)

            delete_message_output = helper.delete_message_from_queue(queue_url, ReceiptHandle)
            print(f"Delete message from queue output: {delete_message_output}")
        else:
            print(f"No malware found in file {file_to_scan}")
            helper.create_tags_for_s3_object(download_bucket_name, download_key, "CLEAN")
            helper.upload_file_to_s3(clean_bucket_name, download_key, file_to_scan)
            delete_message_output = helper.delete_message_from_queue(queue_url, ReceiptHandle)

            print(f"Delete message from queue output: {delete_message_output}")

def update_clamav_db():
    helper.local_freshclam_db_download()
    helper.upload_clamav_db_to_s3(DatabaseDirectory, clamav_db_bucket_name, clamav_dbkey)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--action", type=str, required=True, help="Action to perform", choices=["scan", "update"])
    args = parser.parse_args()
    if args.action == "scan":
        scan()
    elif args.action == "update":
        update_clamav_db()
    else:
        print("Invalid action")