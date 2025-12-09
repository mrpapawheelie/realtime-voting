import os
import json
import base64
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.client("dynamodb")
VOTES_TABLE_NAME = os.getenv("VOTES_TABLE_NAME", "")


def lambda_handler(event, context):
  """
  Consumes Kinesis records.
  For each vote:
    - payload: { "userId": "...", "pollId": "...", "option": "..." }
    - writes one row per user to VOTES_TABLE_NAME
    - enforces single vote per user via conditional write
  """
  print("Received event:", json.dumps(event))

  for record in event.get("Records", []):
    try:
      # Decode Kinesis base64 payload
      kinesis_data = record["kinesis"]["data"]
      decoded = base64.b64decode(kinesis_data).decode("utf-8")
      payload = json.loads(decoded)

      user_id = str(payload["userId"])
      poll_id = str(payload["pollId"])
      option  = str(payload["option"])

      # Conditional put: only if userId does NOT already exist
      try:
        dynamodb.put_item(
          TableName=VOTES_TABLE_NAME,
          Item={
            "userId": {"S": user_id},
            "pollId": {"S": poll_id},
            "option": {"S": option},
          },
          ConditionExpression="attribute_not_exists(userId)",
        )
        print(f"Stored vote for user {user_id}")
      except ClientError as e:
        # If the condition fails, user already voted; ignore
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
          print(f"User {user_id} already voted, skipping")
        else:
          raise

    except Exception as e:
      # Don’t crash entire batch; just log it
      print(f"Error processing record: {e}")

  return {"statusCode": 200}