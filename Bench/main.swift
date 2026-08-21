import AVFoundation
import FluidAudio
import Foundation

// murmur-bench: run every fixture recording through the STT engines and
// report word error rate and speed against hand-corrected references.
//
// Usage: murmur-bench [fixtures-dir] [--v3]
//   fixtures-dir defaults to bench/fixtures. Each fixture is NAME.wav plus
//   NAME.txt containing the exact words spoken.

struct Fixture {
    let name: String
    let audioURL: URL
    let reference: String
}

func loadFixtures(from directory: URL) -> [Fixture] {
    let fileManager = FileManager.default
    guard let files = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
    ) else { return [] }

    return files
        .filter { $0.pathExtension.lowercased() == "wav" }
        .compactMap { wav in
            let ref = wav.deletingPathExtension().appendingPathExtension("txt")
            guard let text = try? String(contentsOf: ref, encoding: .utf8) else {
                print("skipping \(wav.lastPathComponent): no matching .txt reference")
                return nil
            }
            return Fixture(
                name: wav.deletingPathExtension().lastPathComponent,
                audioURL: wav,
                reference: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        .sorted { $0.name < $1.name }
}

func audioSeconds(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    return Double(file.length) / file.processingFormat.sampleRate
}

func benchmark(version: AsrModelVersion, label: String, fixtures: [Fixture]) async {
    print("\n=== \(label) ===")
    let models: AsrModels
    do {
        models = try await AsrModels.downloadAndLoad(version: version)
    } catch {
        print("failed to load \(label): \(error)")
        return
    }
    let manager = AsrManager(config: .default)
    do {
        try await manager.loadModels(models)
    } catch {
        print("failed to initialize \(label): \(error)")
        return
    }

    var totalWer = 0.0
    var totalSeconds = 0.0
    var totalWall = 0.0
    let clock = ContinuousClock()

    print(String(format: "%-16s %8s %8s %8s", "fixture", "WER", "audio", "time"))
    for fixture in fixtures {
        do {
            var decoderState = try TdtDecoderState()
            let start = clock.now
            let result = try await manager.transcribe(
                fixture.audioURL, decoderState: &decoderState
            )
            let elapsed = start.duration(to: clock.now)
            let wall = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            let wer = WordErrorRate.compute(
                reference: fixture.reference, hypothesis: result.text
            )
            let seconds = audioSeconds(fixture.audioURL)
            totalWer += wer
            totalSeconds += seconds
            totalWall += wall
            print(String(
                format: "%-16s %7.1f%% %7.1fs %7.2fs",
                fixture.name, wer * 100, seconds, wall
            ))
        } catch {
            print("\(fixture.name): failed: \(error)")
        }
    }

    let count = Double(fixtures.count)
    guard count > 0, totalWall > 0 else { return }
    print(String(
        format: "avg WER %.1f%% · %.0fx realtime over %.0fs of audio",
        totalWer / count * 100, totalSeconds / totalWall, totalSeconds
    ))
}

let arguments = CommandLine.arguments.dropFirst()
let flags = arguments.filter { $0.hasPrefix("--") }
let positional = arguments.filter { !$0.hasPrefix("--") }

let fixturesDir = URL(
    fileURLWithPath: positional.first ?? "bench/fixtures",
    isDirectory: true
)
let fixtures = loadFixtures(from: fixturesDir)

guard !fixtures.isEmpty else {
    print("""
    No fixtures found in \(fixturesDir.path).

    Record clips of your real dictation conditions (quiet desk, AirPods,
    background noise), save each as NAME.wav with the exact words in NAME.txt,
    then run: make bench
    """)
    exit(1)
}

print("\(fixtures.count) fixtures from \(fixturesDir.path)")
await benchmark(version: .v2, label: "Parakeet TDT v2 (English)", fixtures: fixtures)
if flags.contains("--v3") {
    await benchmark(version: .v3, label: "Parakeet TDT v3 (multilingual)", fixtures: fixtures)
}
