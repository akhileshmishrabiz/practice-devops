import boto3

# # create a s3 bucket and upload some file 

# # 1. Create an S3 client

# bucket_name = 'my-first-bucket-1234567890'
# s3_client = boto3.client('s3')
# response = s3_client.create_bucket(
#     Bucket=bucket_name,
#     CreateBucketConfiguration={
#         'LocationConstraint': 'ap-south-1'
#         }
#         )
    
    
# # 2. Upload a file to the bucket

# s3_client.upload_file('readme.md', bucket_name, '/python-aws/readme.md')



s3_client = boto3.client('s3')
def create_bucket(bucket_name):

    # f' cretimg a new buckjet , bukcet name: {bucket_name}'
    print(f"Creating bucket: {bucket_name}")
    response = s3_client.create_bucket(
        Bucket=bucket_name,
        CreateBucketConfiguration={
            'LocationConstraint': 'ap-south-1'
        })
    
    print(response)


def upload_file(bucket_name, local_file_name, s3_file_name):
    print(f"Uploading file: {local_file_name} to bucket: {bucket_name} as {s3_file_name}")
    s3_client.upload_file(local_file_name, bucket_name, s3_file_name)


def run():
    bucket_name = 'some-other-bucket-1234567890'
    local_file_name = 'readme.md'
    s3_file_name = 'readme.md'
    create_bucket(bucket_name)
    upload_file(bucket_name, local_file_name, s3_file_name) 


run()