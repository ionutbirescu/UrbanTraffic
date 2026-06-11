# Urban Traffic Noise Mapper — Full Technical Documentation

---

## 1. What the System Does

The Urban Traffic Noise Mapper is a mobile application designed to crowdsource and analyse ambient sound across an urban environment. A user opens the app on their Android phone, presses a single button to start recording, and the application captures at least ten seconds of the surrounding soundscape. That audio is uploaded to the cloud where a machine learning model analyses it, determines what type of sound environment it represents, and two independent large language models each write a short contextual paragraph explaining what the soundscape reveals about that place at that specific moment in time — taking into account the time of day, current weather conditions, and GPS location.

Over time, as recordings accumulate from the same device, the user builds up a personal acoustic map of their city. Every recorded location appears as a colour-coded pin on a map, where the colour represents the dominant sound category. Locations visited multiple times cluster into a single pin with a count badge, and tapping it reveals the full history of recordings at that spot.

The system is composed of three distinct layers that communicate with each other: a Flutter mobile application running on Android, a serverless inference pipeline running on AWS Lambda inside a Docker container, and a lightweight API Lambda that retrieves stored results and serves them back to the app.

---

## 2. File Structure

### Flutter Application — `app/noise_mapper/lib/`

The mobile application is written entirely in Dart using the Flutter framework. All application logic lives in eight files inside the `lib/` directory.

**`main.dart`** is both the entry point of the application and the home of the recording functionality. It initialises the app, sets up the bottom navigation bar between the Record and History tabs, and contains the entire `RecordScreen` widget — the microphone button, the GPS status indicator, the weather status indicator, the upload logic, and the device ID management. When the user presses stop, this file orchestrates fetching the presigned S3 upload URL, uploading the WAV file, and posting the metadata to the backend API.

**`history_screen.dart`** presents all recordings made by the current device in two tabs: a scrollable list and an interactive map. The list renders each recording as a card showing its date, dominant sound category, and classification percentage. The map groups nearby recordings into clusters and allows navigation to individual detail screens from both a direct tap and a bottom sheet selection panel.

**`detail_screen.dart`** is the richest screen in the application. It presents the full breakdown of a single recording, including animated classification bars for the four sound categories, an expandable panel showing the raw YAMNet detections, two AI insight cards sourced from different language models, a weather summary, and a tappable location card that opens a full-screen map. It also contains the `_SingleRecordingMap` widget — a nested stateful widget that loads all recordings from the same device within twenty metres and displays them as a clustered, interactive map pin.

**`recording_model.dart`** defines the `Recording` Dart class, which mirrors the data structure returned by the API. It handles JSON parsing, including the nested classification scores, weather fields, raw guesses, and LLM insight fields. It also exposes computed getters such as `isDone`, `isPending`, `hasScores`, and `dominantClass` that the UI widgets rely on.

**`api_service.dart`** is a thin wrapper around the AWS HTTP API using the Dio HTTP client. It exposes four methods: `listRecordings` to fetch all recordings for a device, `getRecording` to fetch the full detail of a single recording, `getResult` for lightweight status polling, and `deleteRecording` to permanently remove a recording.

**`category_style.dart`** is a pure utility file that maps the four sound category names — Traffic, Nature, Human, and Construction — to consistent colours and Material Design icons used across all screens.

**`weather_screen.dart`** is a standalone full-screen widget that displays a rich weather breakdown including temperature, humidity, wind speed and direction, pressure, visibility, UV index, cloud cover, and precipitation. It is navigated to from the RecordScreen when the user taps the weather metadata indicator during or after a recording.

**`weather_service.dart`** wraps the WeatherAPI.com HTTP API. When a recording begins, this service is called with the current GPS coordinates and returns the live weather conditions at that location, which are then stored alongside the audio metadata.

### Backend — `backend/functions/`

**`inference/app.py`** is the core of the entire pipeline. It is a Python Lambda handler that receives an S3 event trigger whenever a new WAV file is uploaded, downloads the audio, runs it through the YAMNet TFLite model, maps the raw detections to the four application categories, builds a contextual prompt from the recording metadata, calls both the Groq and Gemini APIs, and writes all results back to DynamoDB. This file runs inside a Docker container and is the only backend file that requires a Docker rebuild when changed.

**`inference/Dockerfile`** defines the container image that Lambda runs. It specifies all system and Python dependencies, copies the YAMNet model files into the image, and registers `app.lambda_handler` as the Lambda entry point.

**`inference/yamnet.tflite`** is the YAMNet audio classification model serialised in TensorFlow Lite format. It is baked into the Docker image at build time and loaded into memory once when the Lambda container initialises, avoiding the overhead of loading it on every invocation.

**`inference/yamnet_class_map.csv`** is a lookup table mapping YAMNet's 521 numeric class indices to human-readable label names such as "Speech", "Car horn", or "Dog". It is read once at container startup alongside the model.

**`get_recording/get_recording.py`** is a separate Lambda function responsible for reading a recording from DynamoDB and returning it to the app as clean JSON. It handles two endpoints: a full detail endpoint that returns classification scores, raw guesses, weather, and LLM insights, and a lightweight result endpoint used for polling that returns only the status and classification.

---

## 3. System Architecture

To understand how these files interact, it helps to trace a single recording from start to finish.

When the user taps the stop button, the Flutter app makes a GET request to the `/upload-url` endpoint to receive a presigned S3 URL and a freshly generated `recording_id`. It then uploads the WAV file directly to S3 using that URL, bypassing the Lambda API entirely for the large binary transfer. Immediately after, it POSTs the recording metadata — device ID, GPS coordinates, weather data, and timestamp — to the `/metadata` endpoint, which writes a new item to DynamoDB with status set to `PENDING`.

The arrival of the WAV file in S3 automatically triggers the inference Lambda. This trigger is configured in AWS and requires no action from the app. The Lambda downloads the audio from S3 to a temporary file in `/tmp`, runs the YAMNet analysis, calls both language model APIs, and updates the DynamoDB item with the results, setting the status to `DONE`.

Meanwhile, the app has navigated the user to the Detail screen for that recording, which begins polling the `/result/{id}` endpoint every five seconds. Each poll checks the status field. As soon as the Lambda finishes and the status becomes `DONE`, the app makes a final call to `/recordings/{id}` to fetch the full detail — all scores, all insights, all weather fields — and renders the complete screen.

```
Phone
 │
 ├─ GET /upload-url          → recording_id + presigned S3 URL
 ├─ PUT audio.wav            → S3 bucket (direct upload, no Lambda)
 └─ POST /metadata           → DynamoDB (status: PENDING)

S3 event trigger
 │
 └─ Lambda (inference)
     ├─ download WAV from S3
     ├─ run YAMNet (TFLite, windowed)
     ├─ map 521 classes → 4 categories
     ├─ call Groq API  → insight text
     ├─ call Gemini API → insight text
     └─ DynamoDB update (status: DONE, scores, insights)

Phone (polling every 5s)
 │
 ├─ GET /result/{id}         → status: PENDING ... DONE
 └─ GET /recordings/{id}     → full JSON (scores, insights, weather)

Lambda (get_recording)
 └─ read DynamoDB → shape JSON → return to app
```

---

## 4. How Docker and YAMNet Work Together

### Why Docker Is Necessary

AWS Lambda in its standard form executes Python code in a managed Amazon Linux environment. It supports deploying plain ZIP archives of up to 250 MB uncompressed, which is sufficient for most API handlers. However, the inference function requires TensorFlow CPU (approximately 400 MB installed), the librosa audio processing library which in turn depends on a native system library called `libsndfile` not present in the standard Lambda environment, and the YAMNet model file itself. Together these dependencies exceed Lambda's ZIP deployment limits and require native OS packages that cannot be installed at deploy time in the standard runtime.

Docker containers solve all of these problems simultaneously. The entire environment — operating system, system libraries, Python packages, and model files — is assembled once at build time into a single container image. That image is pushed to AWS ECR (Elastic Container Registry) and Lambda is instructed to run that image instead of a ZIP archive. Container images on Lambda support up to 10 GB, far exceeding what is needed here.

### The Dockerfile in Detail

The Dockerfile begins from `public.ecr.aws/lambda/python:3.12`, which is Amazon's official base image for Lambda Python functions. It already has the Lambda runtime and the correct directory structure. The first build step installs `libsndfile` using `dnf`, the package manager of the Amazon Linux variant used by this base image. This native library is what librosa uses to decode audio files.

The Python dependencies are then installed in a single `pip install` layer. `setuptools<81` is pinned because newer versions removed the `pkg_resources` module that both librosa and numba attempt to import at runtime. `tensorflow-cpu==2.18.0` is the CPU-only build of TensorFlow, chosen because Lambda has no GPU and the CPU build is significantly smaller. `librosa==0.10.1` handles loading and resampling the WAV audio to the 16 kHz mono format that YAMNet expects. `numpy==1.26.4` is pinned for compatibility with this specific TensorFlow version. `boto3` is the AWS SDK for interacting with S3 and DynamoDB.

The YAMNet model file (`yamnet.tflite`) and its class map (`yamnet_class_map.csv`) are copied to `/opt/` inside the container. This directory is accessible at runtime and, crucially, these files are loaded into memory once during the container's cold start rather than on every invocation. Lambda containers stay warm between invocations for a period of time, meaning subsequent recordings processed by the same container instance pay no model loading cost at all.

Finally, `app.py` is copied to `${LAMBDA_TASK_ROOT}`, which is the directory Lambda looks in for the handler function, and the entry point is set to `app.lambda_handler`.

### How YAMNet Processes Audio

YAMNet (Yet Another Mobile Network) is a deep convolutional neural network developed by Google and trained on AudioSet, a large-scale dataset of over 2 million human-labelled 10-second clips from YouTube covering 521 distinct sound categories. The model operates on a fixed-length input window of exactly 15,600 audio samples, which at 16 kHz corresponds to approximately 0.975 seconds of audio. For each window it produces a probability score between 0 and 1 for all 521 classes simultaneously.

Because the recordings in this application are at least ten seconds long, a single YAMNet invocation would only see less than one second of audio and could be misled by a transient sound. Instead, `app.py` implements a windowed inference strategy: the audio is sliced into consecutive non-overlapping windows of exactly 15,600 samples, each window is passed through the TFLite interpreter independently, and the resulting 521-dimensional score vectors are averaged across all windows. A 13-second recording produces approximately 13 windows, and the averaged result reflects the character of the whole recording rather than any single moment.

The averaging is performed using NumPy's `mean` function applied along the window axis of a stacked array of score vectors. The top five classes by averaged score are extracted, logged, and stored as `raw_guesses` in DynamoDB. These are the values shown in the expandable "What the AI heard" panel in the Detail screen.

### Mapping 521 Classes to 4 Categories

Presenting 521 individual sound labels to a user is not practical for a mobile application. The application reduces the YAMNet output to four human-meaningful urban sound categories: Human, Traffic, Nature, and Construction. This mapping is implemented as a keyword dictionary in `app.py`. Each of the 521 YAMNet class names is checked against a list of keywords for each category. If the class name contains any of the keywords, its averaged score is added to that category's total. Classes that match no keyword are silently discarded.

The four category totals are then normalised so that they sum to 100%, giving percentage values that represent the relative composition of the soundscape. The category with the highest percentage becomes the `top_class` for the recording. A recording captured in a busy street will typically show Traffic dominating; a recording in a park will show Nature; an indoor office environment will show Human.

The keyword lists were designed to be inclusive of YAMNet's varied naming conventions. For example, the Traffic category matches not only "car" and "engine" but also "train", "aircraft", "helicopter", "skid", and "accelerat" (as a substring that catches both "accelerating" and "acceleration"). This avoids the brittle exact-match problem that would arise from trying to enumerate every possible class name precisely.

---

## 5. The LLM Insight Pipeline

One of the most distinctive features of this application is that every classified recording receives a written analysis from two independent large language models. Rather than showing the user only percentages and bar charts, the application presents a natural-language interpretation of what those numbers mean in the context of the specific time, place, and weather conditions of the recording.

### Constructing the Prompt

After classification, `app.py` assembles a structured prompt that gives the language model all the information it needs to produce a genuinely contextual response. The prompt includes the full day and date formatted in natural language (for example, "Tuesday, 10 June 2026 at 19:45"), the GPS coordinates with the city name, the four category scores, the top five raw YAMNet detections with their percentages, and the complete weather picture at recording time: temperature in Celsius, weather condition description, wind speed in km/h, precipitation in millimetres, and humidity as a percentage.

The prompt instructs the model to act as an urban environmental sound analyst and to write two to three sentences connecting the dominant sound category to the time of day and weather, explaining why the soundscape makes sense for that specific moment and place. The instruction explicitly asks the model to be specific and not merely restate the numbers.

### Groq and Llama 3.3 70B

The first insight is generated by Groq, a cloud AI inference platform that runs Meta's Llama 3.3 70B language model on custom hardware optimised for low-latency inference. The model has 70 billion parameters and produces high-quality, nuanced prose. The API call is made using Python's standard `urllib` library with an explicit `User-Agent` header set to a browser-like string. This header is necessary because Groq's API sits behind Cloudflare's bot protection, which by default blocks requests originating from AWS Lambda IP ranges when they carry Python's default `urllib` User-Agent string. The header causes Cloudflare to treat the request as a legitimate browser-originated API call.

### Gemini 2.5 Flash-Lite

The second insight is generated by Google's Gemini 2.5 Flash-Lite model via the Gemini API. Flash-Lite was chosen over the full Flash model after discovering that Gemini 2.5 Flash performs internal chain-of-thought reasoning before generating its final response. This internal thinking consumes a large portion of the token budget, leaving very few tokens for the actual output text and causing responses to be cut off mid-sentence. Flash-Lite does not perform this internal reasoning step, meaning the entire `maxOutputTokens: 500` budget is available for the response text, producing complete and well-formed paragraphs.

### Fallback Behaviour

Both LLM calls are made independently and both can fail without crashing the pipeline. If Groq is unavailable — for example if the Cloudflare block returns despite the User-Agent header, or if the API rate limit is hit — the code falls back to making a second Gemini call using Flash-Lite, labelling the result accordingly. This means both insight cards in the app will always contain text as long as the Gemini API is reachable, which has proven to be highly reliable from AWS Lambda's network environment.

The model name that actually produced each insight is stored in DynamoDB alongside the text itself, under the fields `insight_groq_model` and `insight_gemini_model`. The Flutter app reads these fields and displays them as the card header, so if the fallback activates, the user sees "Gemini 2.5 Flash-Lite (Google)" rather than the Groq label, and the labelling is always accurate.

---

## 6. The Flutter Application — Screen by Screen

### RecordScreen

The RecordScreen is the first thing the user sees when the app opens. At its centre is a large circular button that begins audio recording when tapped. Below the button, two status chips show whether GPS and weather data have been acquired. These are important because both are captured at recording time and stored permanently with the audio — the app does not allow the user to upload without a GPS fix if location services are enabled, though it degrades gracefully if GPS is unavailable.

When the user taps stop, the recording must be at least ten seconds long. The app then performs a three-step upload sequence: first it requests a presigned S3 upload URL from the backend, then it uploads the WAV file directly to that URL, and finally it posts the recording metadata to a separate endpoint. This separation keeps large binary transfers out of the Lambda function entirely, which would be slow and expensive.

The device identity is managed in this screen. On first launch, a UUID is generated and persisted in SharedPreferences. This UUID serves as the `device_id` for every recording made on this phone, allowing the History screen and the backend to associate all recordings with the same device without requiring user accounts or authentication.

### HistoryScreen

The HistoryScreen presents the user's full recording history in two tabs that share the same underlying data. The data is fetched once on screen load and can be refreshed by pulling down on the list. A refresh button is also available in the app bar.

The List tab renders each recording as a card. The card's left side shows a category icon in a coloured rounded square — Traffic in red, Nature in green, Human in blue, Construction in amber. If the recording is still being processed, a small animated circular progress indicator appears instead, along with the text "Processing…". If processing failed, the card shows an error state. If processing succeeded but no dominant sound category was detected — which happens when a recording captures mostly silence — the card notes this explicitly rather than showing misleading percentage values.

The Map tab is where the clustering behaviour lives. When the tab is displayed, `app.py` groups all recordings that have GPS coordinates into clusters by proximity. Any recordings within twenty metres of each other are merged into a single cluster represented by one map pin. The pin is coloured according to the dominant category of the most recent recording in that cluster. If the cluster contains more than one recording, a small black circular badge in the top-right corner of the pin displays the count. Tapping a single-recording pin navigates directly to that recording's Detail screen. Tapping a multi-recording pin opens a bottom sheet — a panel that slides up from the bottom of the screen — listing all recordings in the cluster with their dates, categories, and percentages. The user taps the desired recording from the list to open its Detail screen.

### DetailScreen

The DetailScreen is the most information-dense screen in the application and is designed to present a layered picture of the recording: what the AI detected, what context surrounded the recording, and what meaning can be drawn from it.

At the top, a formatted timestamp shows the day and time of the recording. Below that, the Classification card presents four horizontal progress bars, one for each sound category, each coloured with the category's assigned colour and labelled with its percentage. If the recording detected no meaningful sounds, a plain text note replaces the bars. At the bottom of the Classification card, an expandable "What the AI heard (raw)" section can be tapped to reveal the top five YAMNet detections with their individual percentages — giving technically curious users a view into the raw model output before it was mapped to categories.

Below the classification card, two AI insight cards appear stacked vertically. The blue card is headed with the Gemini model name and a star icon; the purple card is headed with the Groq or fallback model name and a brain icon. Each card contains the full natural-language analysis generated by that model. If neither insight is available — which only occurs for recordings made before the LLM feature was implemented — a single grey card appears with an explanatory note.

The Weather card follows, showing temperature, condition description, wind speed and direction, precipitation, and humidity, all at the time and location of the recording. After that, the Location card shows the GPS coordinates as a tappable link. Tapping it opens `_SingleRecordingMap`.

The Detail screen also manages the lifecycle of a recording that is still being processed. If the status is `PENDING` when the screen loads, a timer is started that calls the `/result/{id}` endpoint every five seconds. As soon as the response status becomes `DONE`, the timer is cancelled and the full detail is fetched and rendered. This polling runs for a maximum of two minutes — 24 polls — after which it stops regardless of status, preventing indefinite background activity.

### The Single Recording Map

`_SingleRecordingMap` is a full-screen map widget embedded at the bottom of `detail_screen.dart` as a private class. It renders the recording's GPS location as a coloured pin on an OpenStreetMap tile layer. On initialisation, it calls `listRecordings` for the device and filters the results to those within twenty metres of the current recording's coordinates. If multiple recordings share the location, the pin shows a count badge and becomes tappable, opening a bottom sheet identical in design to the one in the HistoryScreen map. Tapping any recording in the list closes the sheet and navigates to that recording's Detail screen. If the user is already viewing one of the recordings in the list, it is labelled "current" and its row is non-navigable.

---

## 7. Data Model

Every recording is stored as a single item in a DynamoDB table. DynamoDB is a NoSQL key-value and document database — items do not need to conform to a fixed schema, which means fields like `insight_groq` simply do not exist on older recordings made before the LLM feature was added, rather than being stored as null values. The Flutter app handles absent fields gracefully throughout.

The `recording_id` field is a UUID v4 string generated by the backend at upload time and serves as the primary key. The `device_id` is a UUID generated by the phone on first install. The `timestamp` is an ISO 8601 datetime string in UTC. The `status` field is a string that progresses from `PENDING` to either `DONE` or `ERROR` as the inference Lambda runs.

The `classification` field is a map of the four category names to their normalised percentage scores stored as DynamoDB `Number` types. Because DynamoDB does not support native float storage, all floating-point values are stored as `Decimal` from Python's `decimal` module and converted back to `float` by `get_recording.py` before being sent to the app.

The `raw_guesses` field is a list of maps, each containing a `label` string and a `score` number representing one of the top five YAMNet detections. The `weather` field is a nested map containing all weather fields captured at recording time.

The four LLM fields — `insight_groq`, `insight_groq_model`, `insight_gemini`, and `insight_gemini_model` — store the text and model name for each insight respectively. Storing the model name alongside the text means the app can always display accurate attribution regardless of which fallback path was taken.

---

## 8. Implementation Challenges and How They Were Resolved

### Gemini Model Retirement

The initial implementation called `gemini-1.5-flash`, which at the time of development was a current and actively maintained model. By the time of deployment and testing, Google had retired all Gemini 1.5 models and all requests to them returned a 404 Not Found error. The fix was straightforward once the cause was identified: switching the model name to `gemini-2.5-flash`, which is the current generation. Model names are stored as Lambda environment variables rather than being hardcoded in `app.py`, so the change required only updating the environment variable rather than rebuilding the Docker image.

### Gemini Response Truncation

After switching to `gemini-2.5-flash`, responses were consistently cut off mid-sentence. The root cause was that Gemini 2.5 Flash performs internal reasoning — sometimes called "thinking" — before composing its final response. This internal process consumes tokens from the same budget as the output text. With `maxOutputTokens` set to 150, the thinking phase consumed nearly the entire budget, leaving only a handful of tokens for the actual response text. The solution was to switch to `gemini-2.5-flash-lite`, a model variant that does not perform internal reasoning, making the full token budget available for the response. The token limit was also raised to 500 to ensure complete paragraphs.

### Groq Cloudflare Block

Groq's API is protected by Cloudflare. Cloudflare maintains lists of known datacenter IP ranges and by default applies bot protection rules to requests originating from them that carry non-browser User-Agent strings. AWS Lambda functions run from Amazon's datacenter IP space and Python's `urllib` library sends `Python-urllib/3.12` as its default User-Agent — a string that Cloudflare's rules flag as a bot. The result was a 403 Forbidden response with Cloudflare error code 1010. The fix was to set an explicit `User-Agent` header in the request that mimics a browser: `Mozilla/5.0 (compatible; NoisMapper/1.0)`. This caused Cloudflare to pass the request through to Groq's API, and the call succeeded.

### Quota Depletion

During the testing phase, the Gemini API key in use ran out of its free daily quota, causing all Gemini calls to fail with a `RESOURCE_EXHAUSTED` error. The solution was to create a fresh API key linked to a new Google Cloud project, which starts with its own independent daily quota. The free tier for Gemini 2.5 Flash-Lite is approximately 1,500 requests per day, which is more than sufficient for demonstration and regular use.

### Two-Laptop Development Environment

The project was developed across two laptops: a work laptop used for code editing with AWS CLI access, and a personal laptop with Docker Desktop for building container images. Because Docker was not available on the work laptop, every change to `app.py` required manually copying the file to the other laptop before running the build and push commands. This also meant that changes applied on the work laptop were occasionally not reflected in the deployed Lambda because the wrong version of `app.py` was in the Docker build directory. The files were explicitly synchronised and the correct build directory (`D:\UrbanTraffic\app\noise_mapper\backend\functions\inference\`) was identified as the authoritative source for Docker builds.

---

## 9. Results

All core features of the application are functioning correctly as of the final deployment. The following table summarises the status of each component.

| Feature | Status |
|---------|--------|
| Audio recording, minimum 10 seconds, WAV format | Working |
| GPS coordinate capture during recording | Working |
| Live weather fetch at recording GPS location | Working |
| Direct audio upload to S3 via presigned URL | Working |
| Metadata storage in DynamoDB on upload | Working |
| S3 event trigger to inference Lambda | Working |
| YAMNet windowed inference, averaged across windows | Working |
| 521-class to 4-category keyword mapping | Working |
| Top 5 raw YAMNet detections stored and displayed | Working |
| Groq / Llama 3.3 70B insight generation | Working |
| Gemini 2.5 Flash-Lite insight generation | Working |
| Groq-to-Gemini fallback when Groq is unavailable | Working |
| Dynamic model name labels in insight cards | Working |
| History list with status-aware recording cards | Working |
| History map with 20-metre proximity clustering | Working |
| Cluster count badge on map pins | Working |
| Bottom sheet recording selector on cluster tap | Working |
| Detail screen with all cards and panels | Working |
| Location map opened from detail screen | Working |
| Multi-recording bottom sheet on detail map | Working |
| Automatic polling from PENDING to DONE | Working |
| Delete recording with confirmation dialog | Working |

### Example Output — Real Recording

The following insight was generated from a recording made indoors on a warm summer evening. YAMNet detected computer keyboard sounds, typing, and throat clearing, all mapping to the Human category at 100%.

**Llama 3.3 70B via Groq:**

> "This soundscape reveals a quiet, indoor urban environment in Timisoara, Romania, on a warm summer evening, with the dominant human sounds suggesting a residential or office setting. The presence of typing, computer keyboard, and throat clearing sounds indicates a focused, possibly work-related activity, while the cough and throat clearing detections may imply a slight discomfort due to the relatively low humidity. The overall silence and lack of outdoor sounds suggest a secluded, air-conditioned space, sheltered from the external environment."

**Gemini 2.5 Flash-Lite via Google:**

> Generated contextual analysis connecting the detected Human-dominant soundscape to the evening time, indoor environment, and local weather conditions in Timisoara.

The Llama 3.3 response demonstrates the quality achievable with the full 70B model — it makes specific inferences about humidity and comfort, correctly identifies the indoor setting, and connects multiple observations into a coherent narrative without being prompted to do so explicitly. Both cards populate reliably on every recording made after the final deployment.
