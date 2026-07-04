# try except finally

# print(10/0)


try:
    import boto3
    s3 = boto3.client('s3', region_name='us-east-1')
    s3.list_buckets()
# except Exception as e:
except ModuleNotFoundError:
    print("Module not found")


print("anoher function")


print("anoher function new")
