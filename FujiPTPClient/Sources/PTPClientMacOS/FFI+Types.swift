// FFI+Types.swift
// Swift 6 FFI bindings for libgphoto2 using dlopen/dlsym.

import Foundation
import FujiRecipesCore

// MARK: - Opaque Types

typealias GPCamera = UnsafeMutableRawPointer
typealias GPContext = UnsafeMutableRawPointer
typealias GPConfig = UnsafeRawPointer
typealias GPWidget = UnsafeMutableRawPointer
typealias GPFile = UnsafeMutableRawPointer
typealias GPPortInfoList = UnsafeMutableRawPointer
typealias GPPortInfo = UnsafeRawPointer
typealias GPPort = UnsafeMutableRawPointer

typealias GPResult = Int32
typealias GPWidgetType = Int32
typealias GPPicture = Int32

// MARK: - GPhoto Result String Helper

func gpResultAsString(_ result: GPResult) -> String {
    switch result {
    case 0: return "Success"
    case -1: return "Operation not permitted"
    case -2: return "Mode not supported"
    case -3: return "Illegal argument"
    case -4: return "Operation failed"
    case -5: return "IO error"
    case -6: return "Device or resource busy"
    case -7: return "An error occurred in the device"
    case -8: return "Out of memory"
    case -9: return "No data required"
    case -10: return "Unsupported hardware"
    case -11: return "Not ready"
    case -12: return "Invalid parameter"
    case -13: return "Invalid config"
    case -14: return "Invalid widget type"
    case -15: return "Invalid menu"
    default: return "Unknown error (\(result))"
    }
}

// MARK: - Function Types

internal typealias LibraryInitFunc = () -> GPResult
internal typealias LibraryExitFunc = () -> Void
internal typealias CameraNewFunc = (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult
internal typealias CameraFreeFunc = (UnsafeMutableRawPointer?) -> Void
internal typealias CameraInitFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> GPResult
internal typealias CameraExitFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
internal typealias CameraGetConfigFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult
internal typealias CameraSetConfigFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?) -> GPResult
internal typealias CameraCapturePreviewFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult
internal typealias CameraGetSummaryFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int8>?) -> GPResult
internal typealias CameraGetPortPathFunc = (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<Int8>?) -> GPResult
internal typealias CameraGetIDFunc = (UnsafeMutableRawPointer, UnsafeMutablePointer<Int8>?) -> GPResult
internal typealias CameraGetPortFunc = (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult
internal typealias CameraSetPortFunc = (UnsafeMutableRawPointer?, UnsafePointer<Int8>?) -> GPResult
internal typealias CameraSetTimeoutFunc = (UnsafeMutableRawPointer?, UInt32) -> GPResult
internal typealias PortInfoListNewFunc = () -> UnsafeMutableRawPointer?
internal typealias PortInfoListCountFunc = (UnsafeRawPointer?) -> Int32
internal typealias PortInfoListGetInfoFunc = (UnsafeRawPointer?, Int32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult
internal typealias PortInfoListFreeFunc = (UnsafeMutableRawPointer?) -> Void
internal typealias PortInfoGetNoteFunc = (UnsafeRawPointer?) -> UnsafePointer<Int8>?
internal typealias PortInfoSetNoteFunc = (UnsafeMutableRawPointer?, UnsafePointer<Int8>?) -> GPResult
internal typealias ConfigWidgetGetValueFunc = (UnsafeRawPointer?, UnsafeMutablePointer<UnsafePointer<Int8>?>?) -> GPResult
internal typealias ConfigWidgetSetValueFunc = (UnsafeMutableRawPointer?, UnsafePointer<Int8>?) -> GPResult
internal typealias ConfigWidgetGetChildValueFunc = (UnsafeRawPointer?, UnsafePointer<Int8>?, UnsafeMutablePointer<UnsafePointer<Int8>?>?) -> GPResult
internal typealias ConfigWidgetSetChildValueFunc = (UnsafeMutableRawPointer?, UnsafePointer<Int8>?, UnsafePointer<Int8>?) -> GPResult
internal typealias ConfigWidgetGetLabelFunc = (UnsafeRawPointer?) -> UnsafePointer<Int8>?
internal typealias ConfigWidgetGetNameFunc = (UnsafeRawPointer?) -> UnsafePointer<Int8>?
internal typealias ConfigWidgetGetTypeFunc = (UnsafeRawPointer?) -> GPWidgetType
internal typealias ConfigWidgetCountChoicesFunc = (UnsafeRawPointer?) -> Int32
internal typealias ConfigWidgetGetChoiceFunc = (UnsafeRawPointer?, Int32, UnsafeMutablePointer<UnsafePointer<Int8>?>?) -> GPResult
internal typealias ConfigGetChildFunc = (UnsafeRawPointer?, UnsafePointer<Int8>?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult
internal typealias PortSendFunc = (UnsafeMutableRawPointer?, UnsafePointer<UInt8>, UInt32, UnsafeMutablePointer<UInt32>?) -> GPResult
internal typealias PortGetFunc = (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>, UInt32, UnsafeMutablePointer<UInt32>?) -> GPResult
internal typealias PortOpenFunc = (UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UInt32) -> GPResult
internal typealias PortCloseFunc = (UnsafeMutableRawPointer?) -> Void
internal typealias PortSetTimeoutFunc = (UnsafeMutableRawPointer?, UInt32) -> GPResult
internal typealias ContextNewFunc = (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> GPResult

// MARK: - Function Registry

public struct Libgphoto2Functions: @unchecked Sendable {
    var `init`: LibraryInitFunc?
    var exit: LibraryExitFunc?
    var cameraNew: CameraNewFunc?
    var cameraFree: CameraFreeFunc?
    var cameraInit: CameraInitFunc?
    var cameraExit: CameraExitFunc?
    var cameraGetConfig: CameraGetConfigFunc?
    var cameraSetConfig: CameraSetConfigFunc?
    var cameraCapturePreview: CameraCapturePreviewFunc?
    var cameraGetSummary: CameraGetSummaryFunc?
    var cameraGetPortPath: CameraGetPortPathFunc?
    var cameraGetID: CameraGetIDFunc?
    var cameraGetPort: CameraGetPortFunc?
    var cameraSetPort: CameraSetPortFunc?
    var cameraSetTimeout: CameraSetTimeoutFunc?
    var portInfoListNew: PortInfoListNewFunc?
    var portInfoListCount: PortInfoListCountFunc?
    var portInfoListGetInfo: PortInfoListGetInfoFunc?
    var portInfoListFree: PortInfoListFreeFunc?
    var portInfoGetNote: PortInfoGetNoteFunc?
    var portInfoSetNote: PortInfoSetNoteFunc?
    var configWidgetGetValue: ConfigWidgetGetValueFunc?
    var configWidgetSetValue: ConfigWidgetSetValueFunc?
    var configWidgetGetChildValue: ConfigWidgetGetChildValueFunc?
    var configWidgetSetChildValue: ConfigWidgetSetChildValueFunc?
    var configWidgetGetLabel: ConfigWidgetGetLabelFunc?
    var configWidgetGetName: ConfigWidgetGetNameFunc?
    var configWidgetGetType: ConfigWidgetGetTypeFunc?
    var configWidgetCountChoices: ConfigWidgetCountChoicesFunc?
    var configWidgetGetChoice: ConfigWidgetGetChoiceFunc?
    var configGetChild: ConfigGetChildFunc?
    var portSend: PortSendFunc?
    var portGet: PortGetFunc?
    var portOpen: PortOpenFunc?
    var portClose: PortCloseFunc?
    var portSetTimeout: PortSetTimeoutFunc?
    var contextNew: ContextNewFunc?

    public init(handle: UnsafeMutableRawPointer?) {
        // Initialize all to nil first
        self.`init` = nil
        self.exit = nil
        self.cameraNew = nil
        self.cameraFree = nil
        self.cameraInit = nil
        self.cameraExit = nil
        self.cameraGetConfig = nil
        self.cameraSetConfig = nil
        self.cameraCapturePreview = nil
        self.cameraGetSummary = nil
        self.cameraGetPortPath = nil
        self.cameraGetID = nil
        self.cameraGetPort = nil
        self.cameraSetPort = nil
        self.cameraSetTimeout = nil
        self.portInfoListNew = nil
        self.portInfoListCount = nil
        self.portInfoListGetInfo = nil
        self.portInfoListFree = nil
        self.portInfoGetNote = nil
        self.portInfoSetNote = nil
        self.configWidgetGetValue = nil
        self.configWidgetSetValue = nil
        self.configWidgetGetChildValue = nil
        self.configWidgetSetChildValue = nil
        self.configWidgetGetLabel = nil
        self.configWidgetGetName = nil
        self.configWidgetGetType = nil
        self.configWidgetCountChoices = nil
        self.configWidgetGetChoice = nil
        self.configGetChild = nil
        self.portSend = nil
        self.portGet = nil
        self.portOpen = nil
        self.portClose = nil
        self.portSetTimeout = nil
        self.contextNew = nil

        guard let h = handle else { return }

        func load<T>(_ name: String) -> T? {
            guard let sym = dlsym(h, name) else { return nil }
            // C function pointers must be loaded with unsafeBitCast, not by
            // dereferencing the symbol pointer.
            return unsafeBitCast(sym, to: T.self)
        }

        self.`init` = load("gp_library_init")
        self.exit = load("gp_library_exit")
        self.cameraNew = load("gp_camera_new")
        self.cameraFree = load("gp_camera_free")
        self.cameraInit = load("gp_camera_init")
        self.cameraExit = load("gp_camera_exit")
        self.cameraGetConfig = load("gp_camera_get_config")
        self.cameraSetConfig = load("gp_camera_set_config")
        self.cameraCapturePreview = load("gp_camera_capture_preview")
        self.cameraGetSummary = load("gp_camera_get_summary")
        self.cameraGetPortPath = load("gp_camera_get_port_path")
        self.cameraGetID = load("gp_camera_get_id")
        self.cameraGetPort = load("gp_camera_get_port")
        self.cameraSetPort = load("gp_camera_set_port")
        self.cameraSetTimeout = load("gp_camera_set_timeout")
        self.portInfoListNew = load("gp_port_info_list_new")
        self.portInfoListCount = load("gp_port_info_list_count")
        self.portInfoListGetInfo = load("gp_port_info_list_get_info")
        self.portInfoListFree = load("gp_port_info_list_free")
        self.portInfoGetNote = load("gp_port_info_get_note")
        self.portInfoSetNote = load("gp_port_info_set_note")
        self.configWidgetGetValue = load("gp_widget_get_value")
        self.configWidgetSetValue = load("gp_widget_set_value")
        self.configWidgetGetChildValue = load("gp_widget_get_child_value")
        self.configWidgetSetChildValue = load("gp_widget_set_child_value")
        self.configWidgetGetLabel = load("gp_widget_get_label")
        self.configWidgetGetName = load("gp_widget_get_name")
        self.configWidgetGetType = load("gp_widget_get_type")
        self.configWidgetCountChoices = load("gp_widget_count_choices")
        self.configWidgetGetChoice = load("gp_widget_get_choice")
        self.configGetChild = load("gp_config_get_child")
        self.portSend = load("gp_port_send")
        self.portGet = load("gp_port_get")
        self.portOpen = load("gp_port_open")
        self.portClose = load("gp_port_close")
        self.portSetTimeout = load("gp_port_set_timeout")
        self.contextNew = load("gp_context_new")
    }
}

// MARK: - libgphoto2 Library Handle

public final class Libgphoto2 {
    nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = {
        let candidates = [
            "/opt/homebrew/lib/libgphoto2.6.dylib",
        ]
        for path in candidates {
            if let h = dlopen(path, RTLD_LAZY) {
                return h
            }
        }
        return nil
    }()

    public static let functions = Libgphoto2Functions(handle: handle)
}
