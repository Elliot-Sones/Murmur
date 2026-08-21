# Murmur STT bench

Measures word error rate (WER) and speed of the speech engines on your own
voice, mic, and vocabulary. Blog benchmarks do not know your accent or your
jargon; this does.

## Record fixtures

Cover your real conditions. Aim for about 20 clips total:

1. Quiet desk, MacBook mic (7 clips)
2. AirPods (7 clips)
3. Background noise, cafe or fan (6 clips)

For each clip:

1. Record 10 to 30 seconds of natural dictation (QuickTime > File > New Audio
   Recording works). Export or convert to WAV.
2. Save it here as `fixtures/desk-01.wav`, `fixtures/airpods-01.wav`, etc.
3. Write the exact words you spoke into `fixtures/desk-01.txt` (same name,
   `.txt`). This is the ground truth; correct it by hand.

Recordings stay local: `fixtures/` is gitignored.

## Run

    make bench                 # Parakeet v2 (current engine)
    make bench BENCH_FLAGS=--v3  # also Parakeet v3 (downloads a second model)

The report shows per-fixture WER, audio length, and processing time, plus
averages per engine. Switch Murmur's default engine only if the data says so.
