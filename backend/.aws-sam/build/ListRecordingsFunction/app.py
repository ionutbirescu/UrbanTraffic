import json
import os
import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["RECORDINGS_TABLE"])


def handler(event, context):
    # Read device_id from query string
    qs = event.get("queryStringParameters") or {}
    device_id = qs.get("device_id")

    if not device_id:
        return _response(400, {"error": "missing_device_id"})

    if not isinstance(device_id, str) or not (8 <= len(device_id) <= 64):
        return _response(400, {"error": "invalid_device_id"})

    try:
        # Scan with filter 
        response = table.scan(
            FilterExpression=Attr("device_id").eq(device_id)
        )
        items = response.get("Items", [])
    except Exception as e:
        print(f"DynamoDB scan failed: {e}")
        return _response(500, {"error": "db_read_failed"})

    items.sort(key=lambda x: x.get("timestamp", ""), reverse=True)

    recordings = [_shape_item(item) for item in items]

    return _response(200, {"recordings": recordings, "count": len(recordings)})


def _shape_item(item):
    """Convert DynamoDB item to API response shape."""
    shaped = {
        "recording_id": item.get("recording_id"),
        "timestamp": item.get("timestamp"),
        "status": item.get("status"),
    }

    try:
        shaped["lat"] = float(item["lat"])
        shaped["lon"] = float(item["lon"])
    except (KeyError, ValueError, TypeError):
        shaped["lat"] = None
        shaped["lon"] = None

    if "classification" in item:
        shaped["classification"] = {
            k: float(v) for k, v in item["classification"].items()
        }

    return shaped


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }