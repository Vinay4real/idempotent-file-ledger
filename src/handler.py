import os
import time

import boto3

from ledger_logic import compute_sha256, decide_action

TABLE_NAME = os.environ["TABLE_NAME"]

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def handler(event, context):
    table = dynamodb.Table(TABLE_NAME)
    results = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        file_hash = compute_sha256(body)

        existing = table.get_item(Key={"file_hash": file_hash}).get("Item")
        now = _now()
        decision = decide_action(existing, now)

        table.put_item(
            Item={
                "file_hash": file_hash,
                "file_name": key,
                "status": decision["status"],
                "first_seen_at": decision["first_seen_at"],
                "last_seen_at": now,
                "attempt_count": decision["attempt_count"],
            }
        )
        results.append({"key": key, "file_hash": file_hash, "status": decision["status"]})

    return {"results": results}
