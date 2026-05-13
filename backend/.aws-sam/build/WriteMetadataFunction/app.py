import json
import os
import boto3
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["RECORDINGS_TABLE"])


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "invalid_json"})

    required = ["recording_id", "device_id", "lat", "lon", "timestamp"]
    missing = [f for f in required if f not in body]
    if missing:
        return _response(400, {"error": "missing_fields", "fields": missing})

    # Validate IDs look like UUIDs (length sanity, not strict format)
    for id_field in ("recording_id", "device_id"):
        val = body[id_field]
        if not isinstance(val, str) or not (8 <= len(val) <= 64):
            return _response(400, {"error": "invalid_id", "field": id_field})

    # Validate lat/lon
    try:
        lat = float(body["lat"])
        lon = float(body["lon"])
    except (TypeError, ValueError):
        return _response(400, {"error": "invalid_coordinates"})

    if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
        return _response(400, {"error": "coordinates_out_of_range"})

    # Validate timestamp is ISO 8601
    try:
        datetime.fromisoformat(body["timestamp"].replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return _response(400, {"error": "invalid_timestamp", "expected": "ISO 8601"})

    # Validate weather is a dict if present
    weather = body.get("weather")
    if weather is not None and not isinstance(weather, dict):
        return _response(400, {"error": "weather_must_be_object"})

    item = {
        "recording_id": body["recording_id"],
        "device_id": body["device_id"],
        "lat": str(lat),
        "lon": str(lon),
        "timestamp": body["timestamp"],
        "status": "PENDING",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    if weather:
        item["weather"] = {k: str(v) for k, v in weather.items()}

    try:
        table.put_item(Item=item)
    except Exception as e:
        print(f"DynamoDB put_item failed: {e}")
        return _response(500, {"error": "db_write_failed"})

    return _response(200, {"status": "ok", "recording_id": body["recording_id"]})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }