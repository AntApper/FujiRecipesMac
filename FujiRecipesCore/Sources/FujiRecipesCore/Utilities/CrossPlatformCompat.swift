import Foundation

#if canImport(Combine)
@_exported import Combine
#else
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    public init(initialValue: Value) {
        self.wrappedValue = initialValue
    }
    public var projectedValue: Published<Value> {
        get { self }
        set { self = newValue }
    }
}
#endif
