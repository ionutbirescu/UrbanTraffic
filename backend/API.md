# Backend API — Urban Noise Mapping

This is the contract between the Flutter app and the AWS backend. If you're working on the app, this is the document to keep open.

**Base URL:** `https://xc2v8ify10.execute-api.eu-central-1.amazonaws.com`

Everything is JSON. All timestamps are ISO 8601 in UTC (e.g. `2026-05-12T20:43:00Z`).

---

## The upload flow

A recording moves through the system in three steps. The app drives the first two, the backend drives the third.

1. App asks the backend for an upload URL → `GET /upload-url`
2. App uploads the WAV directly to S3 using that URL, then tells the backend it's done → `POST /metadata`
3. The inference Lambda picks up the WAV from S3, runs YAMNet, and writes the classification result back to DynamoDB. The app polls for the result (endpoint coming in W3).

The reason we hand out a presigned URL instead of accepting the WAV through API Gateway is simple: API Gateway has a 10 MB payload limit and is expensive per request. S3 is cheap, has no size limit, and the backend never has to touch the audio bytes.

---

## GET /upload-url

Ask the backend for a temporary URL you can upload a WAV to.

**No request body, no query parameters.**

**You get back:**
```json