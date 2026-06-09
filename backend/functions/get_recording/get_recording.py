import json
import os
import boto3
from decimal import Decimal
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["RECORDINGS_TABLE"]
table = dynamodb.Table(TABLE_NAME)


def decimal_to_float(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, dict):
        return {k: decimal_to_float(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [decimal_to_float(i) for i in obj]
    return obj


def get_recording_item(recording_id):
    resp = table.get_item(Key={"recording_id": recording_id})
    return resp.get("Item")


def shape_full(item):
    out = {
        "recording_id": item["recording_id"],
        "device_id":    item.get("device_id"),
        "timestamp":    item.get("timestamp"),
        "lat":          float(item["lat"]) if "lat" in item else None,
        "lon":          float(item["lon"]) if "lon" in item else None,
        "status":       item.get("status"),
        "duration_s":   float(item["duration_s"]) if "duration_s" in item else None,
        "weather":      decimal_to_float(item.get("weather")),
    }
    if item.get("status") == "DONE" and "classification" in item:
        raw = decimal_to_float(item["classification"])
        top_class = max(raw, key=raw.get)
        out["classification"] = {
            "scores": raw,
            "top_class": top_class,
        }
    if "raw_guesses" in item:
        out["raw_guesses"] = decimal_to_float(item["raw_guesses"])
    if "insight_groq" in item:
        out["insight_groq"] = item["insight_groq"]
    if "insight_gemini" in item:
        out["insight_gemini"] = item["insight_gemini"]
    return out


def shape_result(item):
    out = {
        "recording_id": item["recording_id"],
        "status":       item.get("status"),
    }
    if item.get("status") == "DONE" and "classification" in item:
        raw = decimal_to_float(item["classification"])
        top_class = max(raw, key=raw.get)
        out["classification"] = {
            "scores": raw,
            "top_class": top_class,
        }
    return out


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    path = event.get("rawPath", "")
    recording_id = (event.get("pathParameters") or {}).get("id")

    if not recording_id:
        return respond(400, {"error": "missing_recording_id"})

    if not isinstance(recording_id, str) or len(recording_id) < 8 or len(recording_id) > 64:
        return respond(400, {"error": "invalid_recording_id"})

    item = get_recording_item(recording_id)

    if item is None:
        return respond(404, {"error": "not_found", "recording_id": recording_id})

    if path.startswith("/result"):
        return respond(200, shape_result(item))
    else:
        return respond(200, shape_full(item))