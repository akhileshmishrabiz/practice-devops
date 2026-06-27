import boto3


# go to iam, see all users, check the access keys, 
# see the age of the access keys, if it is more than 2 days, delete the access key and create a new access key, download the new access key and update the credentials file with the new access key and secret access key

# demo json parsing
# json_data = {
#     "user": "test-user",
#     "access_key": "AKIAIOSFODNN7EXAMPLE",
#     "secret_access_key": "wJalrXUtnFEMI/K7EXAMPLEKEY",
#     "nested": { "user_age" : 30 }
# }
# user = json_data["use"]
# access_key = json_data["access_key"]
# secret_access_key = json_data["secret_access_key"]

# user = json_data.get("use", "default-user")
# access_key = json_data.get("access_key")
# secret_access_key = json_data.get("secret_access_key")
# user_age = json_data.get("nested", {}).get("user_age", 0)

# print(f"User: {user}")
# print(f"Access Key: {access_key}")
# print(f"Secret Access Key: {secret_access_key}")
# print(f"User Age: {user_age}")


### main code to rotate the access keys

# iam_client = boto3.client('iam')

# response = iam_client.list_users()
# print(response.get('Users', []))
# print(type(response.get('Users')))
# user_data = response.get('Users', [])
# print(user_data[0])
# user_name = user_data[0].get('UserName')
# user_id = user_data[0].get('UserId')
# print(f"User Name: {user_name}")
# print(f"User ID: {user_id}")

# print users
# for user in user_data:
#     user_name = user.get('UserName')
#     user_id = user.get('UserId')
#     print(f"User Name: {user_name}")
#     print(f"User ID: {user_id}")

    # list access keys for the user
    
from datetime import datetime, timezone, timedelta
iam_client = boto3.client('iam')

def get_users():
    response = iam_client.list_users()
    user_data = response.get('Users', [])
    temp_list = []
    for user in user_data:
        user_name = user.get('UserName')
        temp_list.append(user_name)
    return temp_list

def get_access_keys(user_name):
    response = iam_client.list_access_keys(UserName=user_name)
    access_key_data = response.get('AccessKeyMetadata', [])
    # print(access_key_data[0])
    temp_list = []
    for keys in access_key_data:
        access_key_id = keys.get('AccessKeyId')
        # create_date = keys.get('CreateDate')
        create_date = keys.get('CreateDate').replace(tzinfo=timezone.utc)
        current_date = datetime.now(timezone.utc)
        age = (current_date - create_date).days
        # print(f"Access Key ID: {access_key_id}")
        # print(f"Create Date: {create_date}")
        # temp_list.append((user_name,access_key_id, create_date))
        temp_list.append( (user_name, access_key_id, age) )
    return temp_list

   
def list_access_keys_for_all_users():
    users = get_users()
    temp_list_for_user_access_keys = []
    for user in users:
        access_keys = get_access_keys(user)
        temp_list_for_user_access_keys.append(access_keys)

    return temp_list_for_user_access_keys

def delete_access_key(user_name, access_key_id):
    response = iam_client.delete_access_key(
        UserName=user_name,
        AccessKeyId=access_key_id
    )
    print(f"Deleted access key: {access_key_id} for user: {user_name}")
    return response


def keys_to_delete():
    access_keys_info = list_access_keys_for_all_users()
    expiry_days = 2
    temp = []
    # print(access_keys_info)
    for keys in access_keys_info:
        for key in keys:
            user_name, access_key_id, age = key
            if age > expiry_days:
                # print((user_name, access_key_id))
                temp.append((user_name, access_key_id))
    return temp

            

def run():
    what_to_delete = keys_to_delete()
    for items in what_to_delete:
        print(f"Deleting access key: {items[1]} for user: {items[0]}")
        delete_access_key(items[0], items[1])




# print(get_users())
# print(get_access_keys('cli-user'))
# print(list_access_keys_for_all_users())

print(run())

