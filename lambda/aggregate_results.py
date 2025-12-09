import os
import json
import base64
import boto3

dynamodb = boto3.client("dynamodb")
INTERMEDIATE_TABLE_NAME = os.getenv("INTERMEDIATE_TABLE_NAME", "")


def lambda_handler(event, context):
  """
  Consumes Kinesis records.
  For each vote:
    - payload: { "userId": "...", "pollId": "...", "option": "..." }
    - increments a counter per (pollId, option) in INTERMEDIATE_TABLE_NAME
  """
  print("Received event:", json.dumps(event))

  for record in event.get("Records", []):
    try:
      # Decode Kinesis base64 payload
      kinesis_data = record["kinesis"]["data"]
      decoded = base64.b64decode(kinesis_data).decode("utf-8")
      payload = json.loads(decoded)

      poll_id = str(payload["pollId"])
      option  = str(payload["option"])

      # Upsert + increment counter
      dynamodb.update_item(
        TableName=INTERMEDIATE_TABLE_NAME,
        Key={
          "pollId": {"S": poll_id},
          "option": {"S": option},
        },
        UpdateExpression="ADD voteCount :inc",
        ExpressionAttributeValues={
          ":inc": {"N": "1"},
        },
      )

      print(f"Incremented voteCount for poll {poll_id}, option {option}")

    except Exception as e:
      print(f"Error processing record: {e}")

  return {"statusCode": 200}