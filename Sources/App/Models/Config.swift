//
//  Config.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//
//  This file is part of the CafeSmartAPI Project

import Vapor
import BSON

public struct BusinessHours: Codable, Sendable, Equatable {
	public var weekday: Int
	public var open: String
	public var close: String
}

public struct StaffingRules: Codable, Sendable, Equatable {
	public var ordersPerBaristaPerHour: Int
	public var ordersPerBakerPerHour: Int
	public var guestsPerHostPerHour: Int
}

public struct BusinessConfig: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var timezone: String
	public var hours: [BusinessHours]
	public var seatingCapacity: Int
	public var staffing: StaffingRules
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


