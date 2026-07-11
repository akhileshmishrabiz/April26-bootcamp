1. need a landing bucket -> the bucket in which vendor upload the data

2. need a clean bucket -> where our autimaton upload the clean files

3. create a sqs queue 

4. create landing bucket notification -> sqs queue 

5. this sqs queue message will scale the ecs service that run automation, automation should 
delete that sqs message (important)

6. we nedd dockerised autimation so we can provide clamav in runtime

7. Automation flow

 - read the message from the queue, from event data
 - parse the message to find the bucket and key (file)
 - download the file
 - given you have done the backup for clamav db, us ethat to scan, or run freshclam in runtime
 - captuure the scan resulets 
 - if clean -> create a tag in object and upload to the clean bucket
 - if dirty -> tag the object and send notification -> sns to send 
 - validate the scaning and delete the message
 - same cli can also -> download the db and upload that to bucket



s3_client.download_file(bucket_name, file['Key'], os.path.join(DatabaseDirectory, file['Key'].split('/')[-1]))


download_file_from_s3(bucket_name, file['Key'], os.path.join(DatabaseDirectory, file['Key'].split('/')[-1]))


```bash
# docker build  with amd platform
# ecr repo -> 879381241087.dkr.ecr.ap-south-1.amazonaws.com/clamav
docker build --platform linux/amd64 -t 879381241087.dkr.ecr.ap-south-1.amazonaws.com/clamav:latest .

aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 879381241087.dkr.ecr.ap-south-1.amazonaws.com

docker push 879381241087.dkr.ecr.ap-south-1.amazonaws.com/clamav:latest 
```
