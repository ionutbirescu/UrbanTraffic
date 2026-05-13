import json
import os
import uuid
import boto3
from botocore.config import Config

REGION = os.environ.get("AWS_REGION", "eu-central-1")

s3 = boto3.client(
    "s3",
    region_name=REGION,
    config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
)

BUCKET = os.environ["RECORDINGS_BUCKET"]
URL_TTL_SECONDS = 300


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    device_id = params.get("device_id")

    if not device_id:
        return _response(400, {"error": "missing device_id"})

    recording_id = str(uuid.uuid4())
    key = f"recordings/{device_id}/{recording_id}.wav"

    upload_url = s3.generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": BUCKET,
            "Key": key,
            "ContentType": "audio/wav",
        },
        ExpiresIn=URL_TTL_SECONDS,
    )

    return _response(200, {
        "recording_id": recording_id,
        "upload_url": upload_url,
        "key": key,
        "expires_in": URL_TTL_SECONDS,
    })


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }