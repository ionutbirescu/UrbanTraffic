import json
import os
import csv
import urllib.request
import urllib.error

# numba (used by librosa) needs a writable cache dir; Lambda only allows /tmp
os.environ["NUMBA_CACHE_DIR"] = "/tmp"

import boto3
import numpy as np
import librosa
import tensorflow as tf
import tempfile
from decimal import Decimal
from botocore.exceptions import ClientError

# ── AWS clients ──────────────────────────────────────────────────────────────
s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["RECORDINGS_TABLE"]
table = dynamodb.Table(TABLE_NAME)

# ── LLM config (keys + model names as Lambda environment variables) ──────────
GROQ_API_KEY   = os.environ.get("GROQ_API_KEY", "")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GROQ_MODEL     = os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile")
GEMINI_MODEL   = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")

# ── Paths inside the container ───────────────────────────────────────────────
MODEL_PATH = "/opt/yamnet.tflite"
CSV_PATH   = "/opt/yamnet_class_map.csv"

# ── Load class names once at cold start ──────────────────────────────────────
def load_class_names(csv_path):
    class_names = []
    with open(csv_path) as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            class_names.append(row[2])
    return class_names

class_names = load_class_names(CSV_PATH)

# ── Load TFLite interpreter once at cold start ───────────────────────────────
interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
interpreter.allocate_tensors()

input_details  = interpreter.get_input_details()
output_details = interpreter.get_output_details()
expected_input_length = input_details[0]["shape"][0]  # 15600 samples (~0.975s)


# ── Inference ─────────────────────────────────────────────────────────────────
def run_inference(wav_path):
    audio_data, _ = librosa.load(wav_path, sr=16000, mono=True)

    win = expected_input_length
    windows = []
    if len(audio_data) <= win:
        padded = np.pad(audio_data, (0, win - len(audio_data)), "constant")
        windows.append(padded)
    else:
        start = 0
        while start < len(audio_data):
            chunk = audio_data[start:start + win]
            if len(chunk) < win:
                chunk = np.pad(chunk, (0, win - len(chunk)), "constant")
            windows.append(chunk)
            start += win

    all_scores = []
    for w in windows:
        interpreter.set_tensor(input_details[0]["index"], w.astype(np.float32))
        interpreter.invoke()
        out = interpreter.get_tensor(output_details[0]["index"])
        all_scores.append(np.mean(out, axis=0))

    mean_scores = np.mean(np.array(all_scores), axis=0)
    print(f"Analyzed {len(windows)} windows covering {len(audio_data)/16000:.1f}s of audio")

    top5_idx = np.argsort(mean_scores)[::-1][:5]
    raw_guesses = []
    for idx in top5_idx:
        label = class_names[idx]
        pct = round(float(mean_scores[idx]) * 100, 1)
        raw_guesses.append({"label": label, "score": pct})
        print(f"RAW YAMNet: {label} = {pct:.1f}%")

    category_map = {
        "Human":        ["speech", "conversation", "shout", "laughter", "human", "narration",
                          "babbling", "singing", "child", "crowd", "cheering", "clapping",
                          "footsteps", "whistling", "yell", "chatter"],
        "Traffic":      ["vehicle", "car", "engine", "honk", "horn", "siren", "traffic",
                          "motorcycle", "truck", "bus", "tire", "skid", "accelerat", "idling",
                          "train", "rail", "subway", "aircraft", "helicopter", "motor"],
        "Nature":       ["animal", "bird", "chirp", "tweet", "wind", "rain", "raindrop",
                          "water", "stream", "dog", "cat", "rustling", "thunder", "insect",
                          "cricket", "frog", "leaves", "ocean", "wave", "fowl", "bee", "fly"],
        "Construction": ["tools", "hammer", "drill", "construction", "saw", "jackhammer",
                          "grinder", "sander", "power tool", "sawing", "chainsaw", "machine"],
    }

    app_results = {"Traffic": 0.0, "Nature": 0.0, "Human": 0.0, "Construction": 0.0}
    for i, score in enumerate(mean_scores):
        if score > 0.01:
            name_lower = class_names[i].lower()
            for cat, keywords in category_map.items():
                if any(k in name_lower for k in keywords):
                    app_results[cat] += float(score)
                    break

    total = sum(app_results.values())
    if total > 0:
        for cat in app_results:
            app_results[cat] = round((app_results[cat] / total) * 100, 2)

    top_class = max(app_results, key=app_results.get)
    return app_results, top_class, raw_guesses


# ── LLM helpers ───────────────────────────────────────────────────────────────
def build_prompt(scores, top_class, raw_guesses, metadata):
    timestamp = metadata.get("timestamp", "unknown time")
    lat = metadata.get("lat", "unknown")
    lon = metadata.get("lon", "unknown")
    weather = metadata.get("weather", {})

    try:
        from datetime import datetime
        dt = datetime.fromisoformat(str(timestamp).replace("Z", "+00:00"))
        time_str = dt.strftime("%A, %d %B %Y at %H:%M")
    except Exception:
        time_str = str(timestamp)

    raw_str = ", ".join([f"{g['label']} ({g['score']}%)" for g in raw_guesses])
    score_str = ", ".join([f"{k}: {v:.0f}%" for k, v in scores.items()])

    def wval(d, k):
        v = d.get(k) if isinstance(d, dict) else None
        if isinstance(v, dict):
            return v.get("S") or v.get("N") or "?"
        return v if v is not None else "?"

    temp      = wval(weather, "temp_c")
    condition = wval(weather, "condition")
    wind      = wval(weather, "wind_kph")
    precip    = wval(weather, "precip_mm")
    humidity  = wval(weather, "humidity")

    return f"""You are an urban sound analyst. Analyze this environmental audio recording and provide a concise, insightful contextual explanation (2-3 sentences max).

Recording details:
- Time: {time_str}
- Location: {lat}, {lon} (Timisoara, Romania)
- Dominant sound: {top_class}
- Category scores: {score_str}
- Raw AI detections: {raw_str}
- Weather: {condition}, {temp}C, wind {wind} km/h, precipitation {precip}mm, humidity {humidity}%

Explain what the soundscape reveals about this urban environment at this specific time and place. Consider the weather, time of day, and detected sounds to draw meaningful conclusions."""


def call_groq(prompt):
    if not GROQ_API_KEY:
        print("Groq: no API key set")
        return None
    payload = json.dumps({
        "model": GROQ_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 150,
        "temperature": 0.7,
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {GROQ_API_KEY}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
            return data["choices"][0]["message"]["content"].strip()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        print(f"Groq HTTP {e.code}: {body[:300]}")
        return None


def call_gemini(prompt):
    if not GEMINI_API_KEY:
        print("Gemini: no API key set")
        return None
    payload = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"maxOutputTokens": 150, "temperature": 0.7},
    }).encode("utf-8")
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
    )
    req = urllib.request.Request(
        url, data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
            return data["candidates"][0]["content"]["parts"][0]["text"].strip()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        print(f"Gemini HTTP {e.code}: {body[:300]}")
        return None


# ── Lambda handler ─────────────────────────────────────────────────────────────
def lambda_handler(event, context):
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key    = record["s3"]["object"]["key"]
        filename     = key.split("/")[-1]
        recording_id = filename.replace(".wav", "")

        print(f"Processing recording_id={recording_id} from s3://{bucket}/{key}")

        # 1. Fetch existing metadata from DynamoDB for LLM context
        existing = table.get_item(Key={"recording_id": recording_id}).get("Item", {})

        # 2. Download WAV
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = tmp.name
        try:
            s3.download_file(bucket, key, tmp_path)
        except ClientError as e:
            print(f"Failed to download {key}: {e}")
            continue

        # 3. Run YAMNet inference
        try:
            scores, top_class, raw_guesses = run_inference(tmp_path)
        except Exception as e:
            print(f"Inference failed for {recording_id}: {e}")
            table.update_item(
                Key={"recording_id": recording_id},
                UpdateExpression="SET #s = :s",
                ExpressionAttributeNames={"#s": "status"},
                ExpressionAttributeValues={":s": "ERROR"},
            )
            continue
        finally:
            os.unlink(tmp_path)

        # 4. Build metadata for the LLM prompt
        def get_field(item, k):
            v = item.get(k, "")
            if isinstance(v, dict):
                return v.get("S", "") or v.get("N", "")
            return str(v) if v != "" else ""

        metadata = {
            "timestamp": get_field(existing, "timestamp"),
            "lat":       get_field(existing, "lat"),
            "lon":       get_field(existing, "lon"),
            "weather":   existing.get("weather", {}),
        }
        prompt = build_prompt(scores, top_class, raw_guesses, metadata)

        # 5. Call both LLMs independently
        insight_groq = insight_gemini = None
        try:
            insight_groq = call_groq(prompt)
            print(f"Groq OK: {(insight_groq or 'None')[:80]}")
        except Exception as e:
            print(f"Groq error: {e}")
        try:
            insight_gemini = call_gemini(prompt)
            print(f"Gemini OK: {(insight_gemini or 'None')[:80]}")
        except Exception as e:
            print(f"Gemini error: {e}")

        # 6. Write everything to DynamoDB
        scores_decimal = {k: Decimal(str(v)) for k, v in scores.items()}
        raw_decimal = [
            {"label": g["label"], "score": Decimal(str(g["score"]))}
            for g in raw_guesses
        ]
        update_expr = "SET #s = :s, classification = :c, top_class = :t, raw_guesses = :r"
        expr_values = {
            ":s": "DONE",
            ":c": scores_decimal,
            ":t": top_class,
            ":r": raw_decimal,
        }
        if insight_groq:
            update_expr += ", insight_groq = :ig"
            expr_values[":ig"] = insight_groq
        if insight_gemini:
            update_expr += ", insight_gemini = :im"
            expr_values[":im"] = insight_gemini

        table.update_item(
            Key={"recording_id": recording_id},
            UpdateExpression=update_expr,
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues=expr_values,
        )
        print(f"Done: {recording_id} top_class={top_class} scores={scores}")

    return {"statusCode": 200}