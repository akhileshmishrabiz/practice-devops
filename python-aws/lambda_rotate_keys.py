import boto3

from datetime import datetime, timezone
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
    temp_list = []
    for keys in access_key_data:
        access_key_id = keys.get('AccessKeyId')
        create_date = keys.get('CreateDate').replace(tzinfo=timezone.utc)
        current_date = datetime.now(timezone.utc)
        age = (current_date - create_date).days
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
    for keys in access_keys_info:
        for key in keys:
            user_name, access_key_id, age = key
            if age > expiry_days:
                temp.append((user_name, access_key_id))
    return temp

            

def run():
    what_to_delete = keys_to_delete()
    for items in what_to_delete:
        print(f"Deleting access key: {items[1]} for user: {items[0]}")
        delete_access_key(items[0], items[1])


def lambda_handler(event, context):
    run()