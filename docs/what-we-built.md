# Urban Traffic Noise Mapper — What We Built

This is a plain-English account of everything that was built, fixed, and deployed for this project. No jargon where it can be avoided.

---

## What the app does

You open the app on your phone, hit record, and it captures 10+ seconds of ambient sound around you. It uploads that audio to the cloud, where an AI model listens to it and figures out what kind of sound it is — traffic, people talking, nature, construction. A few seconds later you can open the recording in the app and see a breakdown of what was detected, where you were, what the weather was like, and two short AI-written paragraphs explaining what the soundscape says about that place at that moment.

Over time, as more recordings pile up, you can see your city on a map — colored pins for different sound categories, clusters where the same location was recorded multiple times.

---

## The pieces

### The phone app (Flutter)
Built in Flutter so it runs on Android. Three main screens:

- **Record screen** — big mic button, shows your GPS and current weather while you record
- **History screen** — list of all your recordings, plus a map view
- **Detail screen** — full breakdown of a single recording: classification bars, AI insights, weather, location

### The backend (AWS)
When you hit stop on the recording, the audio goes to S3 (Amazon's file storage). That triggers a Lambda function (a small piece of code that runs in the cloud) which:
1. Downloads the audio
2. Runs it through YAMNet — a Google AI model that recognizes 521 types of sound
3. Groups those raw detections into 4 categories: Traffic, Nature, Human, Construction
4. Calls Gemini (Google's AI) to write a contextual insight about the recording
5. Tries Groq (another AI service running Llama 3.3) for a second opinion — if that fails, calls a lighter Gemini model instead
6. Saves everything to DynamoDB (Amazon's database)

A separate Lambda function handles fetching recordings when the app asks for them.

---

## What was fixed and built in this session

### 1. Map clustering in the History screen

**The problem:** If you recorded at the same spot multiple times, the map would show a separate pin for each recording, all stacked on top of each other. Tapping would only ever open the top one — you couldn't get to the others.

**What we did:** Rewrote the map section of `history_screen.dart` to group recordings that are within 20 metres of each other into a single cluster. That cluster shows one pin with a small number badge (like "3") in the corner. If you tap a single-recording pin it opens that recording directly. If you tap a cluster pin it shows a list of all recordings at that location — date, category, percentage — and you pick which one to open.

The 20-metre threshold is the same one already used elsewhere in the app, so behaviour is consistent everywhere.

---

### 2. LLM insights — getting them to actually work

This took several attempts across two sessions. Here's the honest account of what went wrong and how it was fixed.

**What the feature is:** After a recording is classified, two AI models each write 2-3 sentences explaining the soundscape in context — connecting the sound type to the time of day, weather, and location. The results appear as two cards in the detail screen.

**Problem 1 — Gemini model was shut down.**
The code was calling `gemini-1.5-flash`, which Google retired. The request returned a 404. Fixed by switching to `gemini-2.5-flash`.

**Problem 2 — Gemini responses were truncated.**
`gemini-2.5-flash` does internal reasoning before it answers, which eats into the token budget. With `maxOutputTokens: 150` there was almost nothing left for the actual text — you'd get half a sentence. Fixed by raising the limit to 500 and removing `thinkingConfig` (which caused its own 400 error on this API endpoint).

**Problem 3 — Groq was blocked by Cloudflare.**
Lambda functions run from Amazon's datacenters. Groq's API sits behind Cloudflare, which blocks requests from datacenter IP ranges that use Python's default network headers. The fix was to add a browser-like `User-Agent` header to the request. This may or may not fully resolve it depending on Cloudflare's current rules — so the code now falls back to a second Gemini model (`gemini-2.5-flash-lite`) if Groq fails, meaning both insight cards will always have content.

**Problem 4 — Gemini quota was depleted.**
The API key being used had run out of free daily credits from testing. Fixed by switching to a fresh API key on a new Google project with its own clean quota.

**Problem 5 — The wrong `app.py` was being deployed.**
The project exists in two places: `C:\SAPDevelop\UrbanTraffic\` (this laptop, for editing) and `D:\UrbanTraffic\` (the other laptop with Docker, for building). Fixes were being applied to this laptop's copy but Docker was building the other laptop's copy. The files were synced and the correct build folder (`D:\UrbanTraffic\app\noise_mapper\backend\functions\inference\`) was identified as the one that actually goes into the Docker image.

**Problem 6 — Model name labels not being stored.**
The insight cards in the app show which model wrote each insight ("Gemini 2.5 Flash", "Llama 3.3 70B", etc.). But `app.py` wasn't saving the model name to the database, and `get_recording.py` wasn't passing it through to the app. Both were fixed — the model name is now stored alongside the insight text and the app displays it dynamically.

---

## Current state of the two insight cards

| Card | Primary | Fallback |
|------|---------|----------|
| Blue (Gemini) | Gemini 2.5 Flash | — |
| Purple (second model) | Groq / Llama 3.3 70B | Gemini 2.5 Flash-Lite |

Both cards will always show content. If Groq is available you get two different AI perspectives. If Groq is blocked you get two Gemini models with slightly different styles.

---

