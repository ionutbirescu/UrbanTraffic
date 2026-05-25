import json
import os
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE_NAME = os.environ["RECORDINGS_TABLE"]
BUCKET_NAME = os.environ["RECORDINGS_BUCKET"]

table = dynamodb.Table(TABLE_NAME)


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    recording_id = (event.get("pathParameters") or {}).get("id")

    if not recording_id:
        return respond(400, {"error": "missing_recording_id"})

    if not isinstance(recording_id, str) or len(recording_id) < 8 or len(recording_id) > 64:
        return respond(400, {"error": "invalid_recording_id"})

    # 1. Fetch the item so we know it exists before deleting
    resp = table.get_item(Key={"recording_id": recording_id})
    item = resp.get("Item")

    if item is None:
        return respond(404, {"error": "not_found", "recording_id": recording_id})

    # 2. Delete from S3 (best-effort — don't fail the whole request if this fails)
    s3_key = f"recordings/{recording_id}.wav"
    try:
        s3.delete_object(Bucket=BUCKET_NAME, Key=s3_key)
    except ClientError as e:
        # Log but continue — DynamoDB delete is the authoritative operation
        print(f"S3 delete failed for {s3_key}: {e}")

    # 3. Delete from DynamoDB
    table.delete_item(Key={"recording_id": recording_id})

    return respond(200, {"deleted": True, "recording_id": recording_id})