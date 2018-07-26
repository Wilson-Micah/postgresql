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
	public var longitude: Double
	
	/// The point's y coordinate.
	public var latitude: Double
	
	/// Create a new `Point`
	public init(longitude: Double, latitude: Double) {
		self.longitude = longitude
		self.latitude = latitude
	}
}

extension PostgreSQLGeometry: CustomStringConvertible {
	/// See `CustomStringConvertible`.
	public var description: String {
		return "SRID=4326;POINT(\(longitude) \(latitude))"
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
			let parts = string.lowercased().components(separatedBy: "point").last!.components(separatedBy: " ")
			let x = parts[0]
			let y = parts[1]
			let leftParen = x.first
			assert(leftParen == "(")
			
			let rightParen = y.last
			assert(rightParen == ")")
			return .init(longitude: Double(x.dropFirst())!, latitude: Double(y.dropLast())!)
		case .binary(let value):
			let x = value[0..<8]
			let y = value[8..<16]
			return .init(longitude: x.as(Double.self, default: 0), latitude: y.as(Double.self, default: 0))
		case .null: throw PostgreSQLError.decode(self, from: data)
		}
	}
	
	/// See `PostgreSQLDataConvertible`.
	public func convertToPostgreSQLData() throws -> PostgreSQLData {
		return PostgreSQLData(.geometry, text: description)
	}
}
