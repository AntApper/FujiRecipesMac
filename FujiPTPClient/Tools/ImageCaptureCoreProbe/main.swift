import Foundation
import PTPClientMacOS

@main
struct ImageCaptureCoreProbe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
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
                print("highlight=\(preset.highlight.map(String.init) ?? "nil")")
                print("shadow=\(preset.shadow.map(String.init) ?? "nil")")
                print("color=\(preset.color.map(String.init) ?? "nil")")
                print("sharpness=\(preset.sharpness.map(String.init) ?? "nil")")
                client.disconnect()
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
