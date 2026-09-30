import Foundation
import FujiRecipesCore
import PTPClientMacOS

@main
struct ImageCaptureCoreProbe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--verify-write") {
            guard arguments == ["--verify-write"] ||
                    (arguments.count == 3 && arguments[0] == "--verify-write" && arguments[1] == "--baseline-file") else {
                fputs("Usage: ImageCaptureCoreProbe --verify-write [--baseline-file new-file.json]\n", stderr)
                exit(EXIT_FAILURE)
            }
            let baselineURL = arguments.count == 3
                ? URL(fileURLWithPath: arguments[2]).standardizedFileURL
                : FileManager.default.temporaryDirectory.appendingPathComponent("fuji-image-capture-core-baseline-\(UUID().uuidString).json")
            let client = ImageCaptureCorePTPClient()
            do {
                try await client.connect()
                let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { baseline in
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    // Do not overwrite an earlier recovery baseline. Saving
                    // must succeed before the verifier attempts a sharpness write.
                    try encoder.encode(baseline).write(to: baselineURL, options: .withoutOverwriting)
                    print("baseline_file=\(baselineURL.path)")
                    fflush(stdout)
                }, report: { message in
                    print(message)
                    fflush(stdout)
                })
                client.disconnect()
                print("write_verification=\(result.verification.description)")
                print("sharpness_restoration=\(result.sharpnessRestoration.description)")
                print("selector_restoration=\(result.selectorRestoration.description)")
                if result.recoveryRequired {
                    var recovery: [String] = []
                    if result.mutationAttempted, result.sharpnessRestoration != .verified, let baseline = result.baseline {
                        recovery.append("restore C\(baseline.slot) sharpness=\(baseline.sharpness)")
                    }
                    if result.selectionAttempted, result.selectorRestoration != .verified, let original = result.originalSelector {
                        recovery.append("restore original selector C\(original)")
                    }
                    if result.baseline != nil {
                        recovery.append("baseline preserved at \(baselineURL.path)")
                    }
                    fputs("RECOVERY_REQUIRED: \(recovery.joined(separator: "; "))\n", stderr)
                }
                fflush(stdout)
                if result.succeeded {
                    print("VERIFY_WRITE_SUCCESS")
                    exit(EXIT_SUCCESS)
                }
                exit(EXIT_FAILURE)
            } catch {
                client.disconnect()
                fputs("Verify write failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        let slot = arguments.isEmpty ? 4 : (Int(arguments[0]) ?? 0)
        let repeatCount = arguments.count < 2 ? 1 : (Int(arguments[1]) ?? 0)
        guard arguments.count <= 2, (1...7).contains(slot), repeatCount > 0 else {
            fputs("Usage: ImageCaptureCoreProbe [slot 1-7] [repeat-count]\n", stderr)
            exit(EXIT_FAILURE)
        }

        for iteration in 1...repeatCount {
            let client = ImageCaptureCorePTPClient()
            do {
                try await client.connect()
                print("iteration=\(iteration)/\(repeatCount)")
                print("connected=\(client.cameraInfo.displayTitle)")
                print("slot=C\(slot)")
                let result = await ImageCaptureCoreReadProbe.readSlot(using: client, slot: slot, report: { message in
                    print(message)
                    fflush(stdout)
                })
                if let preset = result.preset {
                    print("name=\(preset.name)")
                    print("empty=\(preset.isEmptySlot)")
                    print("filmSimulation=\(preset.filmSimulation.map(String.init) ?? "nil")")
                    print("dynamicRange=\(preset.dynamicRange.map(String.init) ?? "nil")")
                    print("grainEffect=\(preset.grainEffect.map(String.init) ?? "nil")")
                    print("colorChrome=\(preset.colorChrome.map(String.init) ?? "nil")")
                    print("colorChromeFxBlue=\(preset.colorChromeFxBlue.map(String.init) ?? "nil")")
                    print("smoothSkin=\(preset.smoothSkin.map(String.init) ?? "nil")")
                    print("whiteBalance=\(preset.whiteBalance.map(String.init) ?? "nil")")
                    print("wbShiftRed=\(preset.wbShiftRed.map(String.init) ?? "nil")")
                    print("wbShiftBlue=\(preset.wbShiftBlue.map(String.init) ?? "nil")")
                    print("colorTemp=\(preset.colorTemp.map(String.init) ?? "nil")")
                    print("highlight=\(preset.highlight.map(String.init) ?? "nil")")
                    print("shadow=\(preset.shadow.map(String.init) ?? "nil")")
                    print("color=\(preset.color.map(String.init) ?? "nil")")
                    print("sharpness=\(preset.sharpness.map(String.init) ?? "nil")")
                    print("highIsoNr=\(preset.highIsoNr.map(String.init) ?? "nil")")
                    print("clarity=\(preset.clarity.map(String.init) ?? "nil")")
                    print("colorSpace=\(preset.colorSpace.map(String.init) ?? "nil")")
                }
                print("read_verification=\(result.verification.description)")
                print("selector_restoration=\(result.selectorRestoration.description)")
                fflush(stdout)
                client.disconnect()
                if result.recoveryRequired, let original = result.originalSelector {
                    fputs("RECOVERY_REQUIRED: restore original selector C\(original) after reconnecting\n", stderr)
                }
                guard result.succeeded else {
                    fputs("ImageCaptureCore probe failed on iteration \(iteration): \(result.verification.description); selector restoration \(result.selectorRestoration.description)\n", stderr)
                    exit(EXIT_FAILURE)
                }
                if iteration < repeatCount {
                    try await Task.sleep(for: .seconds(2))
                }
            } catch {
                client.disconnect()
                fputs(
                    "ImageCaptureCore probe failed on iteration \(iteration): \(error.localizedDescription)\n",
                    stderr
                )
                exit(EXIT_FAILURE)
            }
        }
    }
}
