# Murmur voice server

Local mlx-audio server for the expressive read-back engines (Chatterbox,
Qwen3-TTS). The System and Kokoro engines do not need it.

## Run

```sh
make tts-serve        # from the Murmur folder; serves on localhost:8000
```

First request per model loads it into memory (a few seconds). Model
weights live in `~/.cache/huggingface/hub/`:

- `mlx-community/chatterbox-turbo-8bit` — Chatterbox with its built-in
  voice (the app's Chatterbox engine)
- `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit` — Qwen3-TTS
  preset voices (Vivian, Ethan, ...)
- `mlx-community/chatterbox-multilingual-v3` — clone-only variant, kept
  for a future "read back in my own voice" feature; it needs an
  `audio_prompt` reference clip and has no default voice

## Re-download or update

```sh
.venv/bin/hf download mlx-community/chatterbox-turbo-8bit
.venv/bin/hf download mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit
```

## Try it by hand

```sh
curl -X POST http://localhost:8000/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"model": "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit", "input": "Hello from Murmur!", "voice": "Vivian"}' \
  --output hello.wav && afplay hello.wav
```

The `.venv` was created with `uv venv --python 3.12` and
`uv pip install "mlx-audio[tts]"`. It is gitignored.
