import Foundation
import FujiRecipesCore
import PTPClientMacOS

@main
struct ImageCaptureCoreProbe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--verify-write") {
            let slot = 4
            let client = ImageCaptureCorePTPClient()
            do {
                try await client.connect()
                let initial = try await client.readPresetSlot(slot)
                print("initial_sharpness=\(initial.sharpness ?? 0)")
                let targetValue: Int32 = initial.sharpness == 20 ? 0 : 20
                print("writing sharpness=\(targetValue)")
                try await client.writeProperty(0xD1A0, value: targetValue)
                let updated = try await client.readPresetSlot(slot)
                print("observed_updated_sharpness=\(updated.sharpness ?? 0)")
                guard updated.sharpness == targetValue else {
                    fputs("Write verification failed: expected \(targetValue), got \(String(describing: updated.sharpness))\n", stderr)
                    client.disconnect()
                    exit(EXIT_FAILURE)
                }
                print("restoring initial sharpness=\(initial.sharpness ?? 10)")
                try await client.writeProperty(0xD1A0, value: initial.sharpness ?? 10)
                let restored = try await client.readPresetSlot(slot)
                print("observed_restored_sharpness=\(restored.sharpness ?? 0)")
                guard restored.sharpness == initial.sharpness else {
                    fputs("Restore verification failed: expected \(String(describing: initial.sharpness)), got \(String(describing: restored.sharpness))\n", stderr)
                    client.disconnect()
                    exit(EXIT_FAILURE)
                }
                client.disconnect()
                print("VERIFY_WRITE_SUCCESS")
                exit(EXIT_SUCCESS)
            } catch {
                client.disconnect()
                fputs("Verify write failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        let slot = arguments.first.flatMap(Int.init) ?? 4
        let repeatCount = arguments.dropFirst().first.flatMap(Int.init) ?? 1
        guard (1...7).contains(slot), repeatCount > 0 else {
            fputs("Usage: ImageCaptureCoreProbe [slot 1-7] [repeat-count]\n", stderr)
            exit(EXIT_FAILURE)
        }

        for iteration in 1...repeatCount {
            let client = ImageCaptureCorePTPClient()
            do {
                try await client.connect()
                let preset = try await client.readPresetSlot(slot)
                print("iteration=\(iteration)/\(repeatCount)")
                print("connected=\(client.cameraInfo.displayTitle)")
                print("slot=C\(slot)")
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
                client.disconnect()
                if iteration < repeatCount {
                    try? await Task.sleep(for: .seconds(2))
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
