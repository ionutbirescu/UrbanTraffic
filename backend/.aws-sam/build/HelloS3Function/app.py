import json


def handler(event, context):
    # S3 sends one or more records per event. For our use case it's always one.
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        size = record["s3"]["object"].get("size", "?")
        print(f"New upload: s3://{bucket}/{key} ({size} bytes)")

    # TODO 
    return {"status": "ok"}