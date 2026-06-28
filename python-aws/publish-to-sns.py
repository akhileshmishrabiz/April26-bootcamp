import boto3

# 1. Initialize the SNS client
sns_client = boto3.client('sns', region_name='ap-south-1')

topic_arn = 'arn:aws:sns:ap-south-1:879381241087:alarm-notification'

# 2. Publish to the topic
response = sns_client.publish(
    TopicArn=topic_arn,
    Message='Hello from Boto3!',
    Subject='Notification Subject' # Optional
)

print("Message published with ID:", response['MessageId'])