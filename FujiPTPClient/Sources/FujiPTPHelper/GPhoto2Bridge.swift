// GPhoto2Bridge.swift
// Swift bridge to the C GPhoto2Wrapper library.

import Foundation
import GPhoto2Wrapper

typealias GPResult = Int32
let GP_OK: GPResult = 0

// MARK: - C Function Wrappers

func cameraNew() -> UnsafeMutableRawPointer? {
    var camera: UnsafeMutableRawPointer? = nil
    let result = gphoto2_camera_new(&camera)
    return result == GP_OK ? camera : nil
}

func cameraFree(_ camera: UnsafeMutableRawPointer?) {
    gphoto2_camera_free(camera)
}

func cameraInit(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer) -> GPResult {
    return gphoto2_camera_init(camera, context)
}

func cameraExit(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer) -> GPResult {
    return gphoto2_camera_exit(camera, context)
}

func cameraGetConfig(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    var config: UnsafeMutableRawPointer? = nil
    let result = gphoto2_camera_get_config(camera, &config, context)
    return result == GP_OK ? config : nil
}

func cameraSetConfig(_ camera: UnsafeMutableRawPointer, _ config: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer) -> GPResult {
    return gphoto2_camera_set_config(camera, config, context)
}

func cameraGetAbout(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer) -> String? {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let result = gphoto2_camera_get_about(camera, &buffer, context)
    guard result == GP_OK else { return nil }
    if let nullIndex = buffer.firstIndex(of: 0) {
        return String(bytes: buffer[..<nullIndex], encoding: .utf8)
    }
    return String(bytes: buffer, encoding: .utf8)
}

func cameraGetAbilities(_ camera: UnsafeMutableRawPointer) -> String? {
    var abilities = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 8)
    defer { abilities.deallocate() }
    let result = gphoto2_camera_get_abilities(camera, abilities)
    guard result == GP_OK else { return nil }
    return "ok"
}

func cameraSetPortInfo(_ camera: UnsafeMutableRawPointer, _ info: UnsafeMutableRawPointer) -> GPResult {
    return gphoto2_camera_set_port_info(camera, info)
}

// Port info list
func portInfoListNew() -> UnsafeMutableRawPointer? {
    return gphoto2_port_info_list_new()
}

func portInfoListCount(_ list: UnsafeMutableRawPointer) -> Int32 {
    return Int32(gphoto2_port_info_list_count(list))
}

func portInfoListGetInfo(_ list: UnsafeMutableRawPointer, _ index: Int32) -> UnsafeMutableRawPointer? {
    var info: UnsafeMutableRawPointer? = nil
    let result = gphoto2_port_info_list_get_info(list, index, &info)
    return result == GP_OK ? info : nil
}

func portInfoListFree(_ list: UnsafeMutableRawPointer?) {
    gphoto2_port_info_list_free(list)
}

// Widget functions
func configWidgetGetValue(_ widget: UnsafeMutableRawPointer) -> String? {
    var value: UnsafeMutableRawPointer? = nil
    let result = gphoto2_widget_get_value(widget, &value)
    guard result == GP_OK, let value = value else { return nil }
    let cStr = UnsafeMutableRawPointer(value).assumingMemoryBound(to: Int8.self)
    return String(cString: cStr)
    return nil
}

func configWidgetGetType(_ widget: UnsafeMutableRawPointer) -> Int32 {
    var type: Int32 = 0
    let result = gphoto2_widget_get_type(widget, &type)
    guard result == GP_OK else { return 0 }
    return type
}

func configWidgetCountChoices(_ widget: UnsafeMutableRawPointer) -> Int32 {
    return Int32(gphoto2_widget_count_choices(widget))
}

func configWidgetGetChoice(_ widget: UnsafeMutableRawPointer, _ index: Int32) -> String? {
    var choice: UnsafePointer<Int8>? = nil
    let result = gphoto2_widget_get_choice(widget, index, &choice)
    guard result == GP_OK, let choice = choice else { return nil }
    return String(cString: choice)
}

func configGetChildByName(_ config: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer? {
    var child: UnsafeMutableRawPointer? = nil
    let cName = (name as NSString).utf8String!
    let result = gphoto2_widget_get_child_by_name(config, cName, &child)
    return result == GP_OK ? child : nil
}

// Port operations
func portOpen(_ port: UnsafeMutableRawPointer) -> GPResult {
    return gphoto2_port_open(port)
}

func portClose(_ port: UnsafeMutableRawPointer) {
    gphoto2_port_close(port)
}

// Context
func contextNew() -> UnsafeMutableRawPointer? {
    return gphoto2_context_new()
}

// Config value read/write
func getConfigValue(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer, _ path: String) -> String? {
    var buffer = [UInt8](repeating: 0, count: 512)
    let cPath = (path as NSString).utf8String!
    let result = gphoto2_get_config_value(camera, context, cPath, UnsafeMutableRawPointer(&buffer).assumingMemoryBound(to: Int8.self), 512)
    guard result == GP_OK else { return nil }
    if let nullIndex = buffer.firstIndex(of: 0) {
        return String(bytes: buffer[..<nullIndex], encoding: .utf8)
    }
    return String(bytes: buffer, encoding: .utf8)
}

func setConfigValue(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer, _ path: String, _ value: String) -> GPResult {
    let cPath = (path as NSString).utf8String!
    let cValue = (value as NSString).utf8String!
    return gphoto2_set_config_value(camera, context, cPath, cValue)
}
