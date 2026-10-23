# Explainly

An oral exam in your pocket. Upload a lecture, answer out loud, and get an
honest check: which key points you named, which you missed, and the slide
to read again. The first version works in English.

## How it works

```
app (Flutter) → server (FastAPI) → Whisper → search in your files (pgvector) → AI check → feedback
```

1. **Upload.** The server reads the `.pdf` / `.pptx`, keeps every slide with its
   number, and asks the model for topics, questions and 2–4 key points each.
2. **Answer out loud.** The app records your voice, Whisper turns it into text.
3. **Honest check.** For every key point the model only answers "did the student
   say this, yes or no". Python counts the score. A missed point links to its slide.
4. **Topic map.** A topic's percent is the average of its last 3 answers:
   below 50 is red, from 80 is green.

## Run it

You need Docker, Python 3.12 and Flutter.

```bash
docker compose up -d                                   # the database, on port 5433
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Then, in another terminal:

```bash
cd mobile
flutter run -d chrome                                  # in the browser
flutter run --dart-define=API_URL=http://<your-computer-ip>:8000   # on a phone
```

`./start.sh` does the first and the third step in one go, and stops an old server first.
Then the app is open in the browser at `http://localhost:8000` (the server gives out
the web version from `mobile/build/web`; rebuild it with `flutter build web` after app changes).

### Android

```bash
./emulator.sh        # a virtual phone on this computer, with the app in it
./build_apk.sh       # builds the app and puts it on every connected device
./install_apk.sh     # after plugging the phone in again: link it to the server and open the app
```

The phone reaches the server through the USB cable (`adb reverse`), so it
works in any network, also on mobile data. The phone needs "USB debugging"
switched on in the developer options.

`./build_apk.sh wifi` builds an app that uses Wi-Fi instead of the cable.
Then phone and computer must be in the same network.

`http://localhost:8000/docs` shows every request of the server and lets you try it.

## The AI model

The model writes the questions and checks the answers. `.env` says which one to use.

**Local (Ollama), no key.** This is what `.env` is set to now. `docker compose up -d`
starts Ollama; download the model once:

```bash
docker exec explainly-ollama ollama pull qwen2.5:7b
```

It needs an NVIDIA card with about 6 GB.

**Cloud (OpenAI, Groq, OpenRouter).** Put the key and address in `.env`,
see `.env.example`.

**No model at all.** With the placeholder key the app runs in offline mode:
questions are made from slide titles and the check compares meanings with
vectors. That check is rough and only good for trying the screens.

## Where things are

| File | What it does |
|---|---|
| `app/main.py` | The server: receives requests, returns answers |
| `app/services.py` | The steps: add a material, check an answer, build the topic map |
| `app/extract.py` | File → slides with numbers |
| `app/rubric.py` | Slides → topics, questions, key points |
| `app/check.py` | Answer → which key points were named |
| `app/transcribe.py` | Voice → text (Whisper, local or API) |
| `app/embed.py` | Text → vector, for search |
| `app/db.py` | The database tables |
| `app/llm.py` | The only file that talks to the AI model |
| `mobile/lib/screens/` | The three screens: Subjects, Practice, Progress |
| `mobile/lib/api.dart` | The only file in the app that talks to the server |
| `run_demo.py` | The first milestone: the same idea in the terminal |

## Tests

```bash
.venv/bin/python -m pytest          # server, uses a separate test database
cd mobile && flutter test           # app
```

## Not done yet

- English only. Russian and Kazakh were tried: the local model checks Russian
  well, but under-counts Kazakh answers, so they are left for a later version.

- No accounts: one server holds one student's subjects.
- Scanned PDFs (pictures of text) are not read.
- iOS was not built.
