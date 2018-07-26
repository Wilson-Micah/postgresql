//
//  PostgreSQLData+Geometry.swift
//  Async
//
//  Created by Micah Wilson on 7/25/18.
//

import Foundation

/// A 2-dimenstional (double[2]) point.
public struct PostgreSQLGeometry: Codable, Equatable {
	/// The point's x coordinate.
	public var x: Double
	
	/// The point's y coordinate.
	public var y: Double
	
	/// Create a new `Point`
	public init(x: Double, y: Double) {
		self.x = x
		self.y = y
	}
}

extension PostgreSQLGeometry: CustomStringConvertible {
	/// See `CustomStringConvertible`.
	public var description: String {
		return "ST_GeomFromText('POINT(\(x) \(y)', 4326))"
	}
}

extension PostgreSQLGeometry: PostgreSQLDataConvertible {
	/// See `PostgreSQLDataConvertible`.
	public static func convertFromPostgreSQLData(_ data: PostgreSQLData) throws -> PostgreSQLGeometry {
		guard case .geometry = data.type else {
			throw PostgreSQLError.decode(self, from: data)
		}
		switch data.storage {
		case .text(let string):
			let parts = string.split(separator: ",")
			var x = parts[0]
			var y = parts[1]
			let leftParen = x.popFirst()
			assert(leftParen == "(")
			let rightParen = y.popLast()
			assert(rightParen == ")")
			return .init(x: Double(x)!, y: Double(y)!)
		case .binary(let value):
			let x = value[0..<8]
			let y = value[8..<16]
			return .init(x: x.as(Double.self, default: 0), y: y.as(Double.self, default: 0))
		case .null: throw PostgreSQLError.decode(self, from: data)
		}
	}
	
	/// See `PostgreSQLDataConvertible`.
	public func convertToPostgreSQLData() throws -> PostgreSQLData {
		return PostgreSQLData(.geometry, text: description)
	}
}
