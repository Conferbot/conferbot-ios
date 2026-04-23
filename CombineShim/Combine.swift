// Combine shim for Linux compilation/CI
// Provides minimal type stubs matching Apple's Combine framework
// so the SDK core compiles for syntax/type checking on Linux.
// On iOS/macOS, the real Combine framework is used.

import Foundation

// MARK: - Publisher Protocol

public protocol Publisher {
    associatedtype Output
    associatedtype Failure: Error
}

// MARK: - AnyPublisher

public struct AnyPublisher<Output, Failure: Error>: Publisher {
    public init<P: Publisher>(_ publisher: P) where P.Output == Output, P.Failure == Failure {}
}

// MARK: - Published Property Wrapper

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public var projectedValue: Published<Value>.Publisher

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
        self.projectedValue = Publisher()
    }

    public struct Publisher {
        public func eraseToAnyPublisher() -> AnyPublisher<Value, Never> {
            return AnyPublisher<Value, Never>(self)
        }
    }
}

extension Published.Publisher: Combine.Publisher {
    public typealias Output = Value
    public typealias Failure = Never
}

// MARK: - ObservableObject

public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher = ObservableObjectPublisher
    var objectWillChange: ObjectWillChangePublisher { get }
}

public extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var objectWillChange: ObservableObjectPublisher {
        return ObservableObjectPublisher()
    }
}

public class ObservableObjectPublisher: Publisher {
    public typealias Output = Void
    public typealias Failure = Never
    public func send() {}
}

// MARK: - Cancellable

public protocol Cancellable {
    func cancel()
}

public class AnyCancellable: Cancellable, Hashable {
    private let _cancel: () -> Void

    public init(_ cancel: @escaping () -> Void) {
        self._cancel = cancel
    }

    public init<C: Cancellable>(_ cancellable: C) {
        self._cancel = { cancellable.cancel() }
    }

    public func cancel() {
        _cancel()
    }

    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public func store(in set: inout Set<AnyCancellable>) {
        set.insert(self)
    }
}

// MARK: - Subject

public protocol Subject: Publisher {
    func send(_ value: Output)
    func send(completion: Subscribers.Completion<Failure>)
}

public enum Subscribers {
    public enum Completion<Failure: Error> {
        case finished
        case failure(Failure)
    }
}

public class PassthroughSubject<Output, Failure: Error>: Subject {
    public init() {}
    public func send(_ value: Output) {}
    public func send(completion: Subscribers.Completion<Failure>) {}

    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> {
        return AnyPublisher<Output, Failure>(self)
    }

    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        return AnyCancellable {}
    }
}

extension PassthroughSubject: Publisher {}

public class CurrentValueSubject<Output, Failure: Error>: Subject {
    public var value: Output

    public init(_ value: Output) {
        self.value = value
    }

    public func send(_ value: Output) {
        self.value = value
    }

    public func send(completion: Subscribers.Completion<Failure>) {}

    public func eraseToAnyPublisher() -> AnyPublisher<Output, Failure> {
        return AnyPublisher<Output, Failure>(self)
    }

    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        return AnyCancellable {}
    }
}

extension CurrentValueSubject: Publisher {}

// MARK: - Just

public struct Just<Output>: Publisher {
    public typealias Failure = Never
    public let output: Output

    public init(_ output: Output) {
        self.output = output
    }

    public func eraseToAnyPublisher() -> AnyPublisher<Output, Never> {
        return AnyPublisher<Output, Never>(self)
    }
}

// MARK: - Never conformance

extension Never: Error {}
