//
//  CBPeripheralExtensions.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 19/10/2020.
//  Copyright © 2020 Bjørn Inge Vikhammermo Berg. All rights reserved.
//

import CoreBluetooth
import Foundation

public protocol PeripheralProtocol {
    var name: String? { get }
    var name2: String { get }

    var asStringIdentifier: String { get }
}

public enum Either<A, B> {
  case Left(A)
  case Right(B)
}

public typealias SomePeripheral = Either<CBPeripheral, MockedPeripheral>

extension SomePeripheral: PeripheralProtocol, Identifiable, Hashable, Equatable {
    public static func == (lhs: Either<A, B>, rhs: Either<A, B>) -> Bool {
        lhs.asStringIdentifier == rhs.asStringIdentifier
    }

    public var id: String {
        actualPeripheral.asStringIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(actualPeripheral.asStringIdentifier)
    }

    private var actualPeripheral: PeripheralProtocol {
        switch self {
        case let .Left(real):
            return real
        case let .Right(mocked):
            return mocked
        }
    }
    public var name: String? {
        actualPeripheral.name
    }

    public var name2: String {
        actualPeripheral.name2
    }

    public var asStringIdentifier: String {
        actualPeripheral.asStringIdentifier
    }
}

extension CBPeripheral: PeripheralProtocol, Identifiable {
    public var name2: String {
        self.name ?? ""
    }

    public var asStringIdentifier: String {
        self.identifier.uuidString
    }
}

public class MockedPeripheral: PeripheralProtocol, Identifiable {
    public var name: String?

    public var name2: String {
        name ?? "unknown-device"
    }

    public var asStringIdentifier: String {
        name2
    }

    public init(name: String) {
        self.name = name
    }
}
