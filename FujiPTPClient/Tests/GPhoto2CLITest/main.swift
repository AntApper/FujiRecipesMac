import Foundation
import GPhoto2CLI

let client = GPhoto2PTPClient()
print("📡 Connecting...")

do {
    try await client.connect()
    print("✅ Connected: \(client.cameraInfo.model)")
    
    client.disconnect()
    print("✅ Disconnected")
} catch {
    print("❌ Error: \(error)")
}
