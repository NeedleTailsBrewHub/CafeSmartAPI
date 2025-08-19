//
//  Seating.swift
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

public struct SeatingArea: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var name: String
	public var defaultTurnMinutes: Int
	public var active: Bool
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

public struct Table: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var areaId: String
	public var name: String
	public var capacity: Int
	public var accessible: Bool
	public var highTop: Bool?
	public var outside: Bool?
	public var active: Bool
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}
