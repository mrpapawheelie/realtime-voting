import os
import json
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
INTERMEDIATE_TABLE_NAME = os.getenv("INTERMEDIATE_TABLE_NAME", "")

def lambda_handler(event, context):
    """
    API Gateway proxy integration.

    Expects: GET /results?pollId=poll-1

    Returns:
    {
      "pollId": "poll-1",
      "items": [
        { "option": "A", "count": 10 },
        { "option": "B", "count": 4 }
      ]
    }
    """
    try:
        qs = event.get("queryStringParameters") or {}
        poll_id = qs.get("pollId")

        if not poll_id:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Missing required query parameter: pollId"}),
            }

        table = dynamodb.Table(INTERMEDIATE_TABLE_NAME)

        # Query by pollId (partition key)
        resp = table.query(
            KeyConditionExpression=Key("pollId").eq(poll_id)
        )

        items = resp.get("Items", [])

        result_items = []
        for item in items:
            option = item.get("option")
            count = int(item.get("voteCount", 0))
            result_items.append({
                "option": option,
                "count": count,
            })

        body = {
            "pollId": poll_id,
            "items": result_items,
        }

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                # optional CORS
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps(body),
        }

    except Exception as e:
        print("Error in results lambda:", e)
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Internal server error"}),
        }