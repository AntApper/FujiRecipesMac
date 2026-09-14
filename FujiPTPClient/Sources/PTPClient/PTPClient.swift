// MARK: - Re-exports from FujiRecipesCore
// The core PTP types live in FujiRecipesCore to avoid circular dependencies.
// This module re-exports them for convenience.

import FujiRecipesCore

/// Re-exported from FujiRecipesCore for backwards compatibility.
public typealias PTPClientProtocol = FujiRecipesCore.PTPClientProtocol
public typealias PTPCameraInfo = FujiRecipesCore.PTPCameraInfo
public typealias PTPPropertyResponse = FujiRecipesCore.PTPPropertyResponse
public typealias PTPError = FujiRecipesCore.PTPError
public typealias PTPClientPresetData = FujiRecipesCore.PTPClientPresetData
