import Foundation

/// Result of RAF conversion or camera preview capture.
public struct JPEGFile: Sendable {
    public let name: String
    public let data: Data
    public let size: UInt32
    public let storageID: UInt32
    public let objectHandle: UInt32
    
    public init(name: String, data: Data, size: UInt32, storageID: UInt32, objectHandle: UInt32) {
        self.name = name
        self.data = data
        self.size = size
        self.storageID = storageID
        self.objectHandle = objectHandle
    }
}

/// A RAF (Fujifilm RAW) file ready for upload to the camera.
public struct RAFFile: Sendable {
    public let name: String           // Filename e.g. "DSCF0001.RAF"
    public let data: Data             // Raw RAF bytes
    public let mimeType: String       // "application/octet-stream"
    public let encoding: UInt16       // 0x0001 = packed
    public let compression: UInt16    // 0x0001 = deflate
    public let storageID: UInt32      // Usually 0xFFFFFFFF (auto-assign)
    public let objectFormat: UInt16   // 0x300B = RAF/RAW
    public let thumbnail: Data?       // Optional preview thumbnail
    
    public init(name: String, data: Data, thumbnail: Data? = nil) {
        self.name = name
        self.data = data
        self.mimeType = "application/octet-stream"
        self.encoding = 0x0001
        self.compression = 0x0001
        self.storageID = 0xFFFFFFFF
        self.objectFormat = 0x300B
        self.thumbnail = thumbnail
    }
}
