//
//  ArrayResponseWrappers.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on August 19, 2025
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmartAPI Project
//

import Vapor
import BSON

public struct OrdersWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
	public var items: [Order]
	public func encodeResponse(for request: Request) async throws -> Response {
		var headers = HTTPHeaders()
		headers.add(name: .contentType, value: "application/bson")
		let body = try BSONEncoder().encode(self)
		return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
	}
}
public struct InventoryItemsWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
	public var items: [InventoryItem]
	public func encodeResponse(for request: Request) async throws -> Response {
		var headers = HTTPHeaders()
		headers.add(name: .contentType, value: "application/bson")
		let body = try BSONEncoder().encode(self)
		return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
	}
}
struct UsersWrapper: Content, Sendable, BSONResponseEncodable {
	public var items: [UserPublic]
	public func encodeResponse(for request: Request) async throws -> Response {
		var headers = HTTPHeaders()
		headers.add(name: .contentType, value: "application/bson")
		let body = try BSONEncoder().encode(self)
		return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
	}
}
public struct SeatingAreasWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
	public var items: [SeatingArea]
	public func encodeResponse(for request: Request) async throws -> Response {
		var headers = HTTPHeaders()
		headers.add(name: .contentType, value: "application/bson")
		let body = try BSONEncoder().encode(self)
		return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
	}
}
public struct TablesWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
	public var items: [Table]
	public func encodeResponse(for request: Request) async throws -> Response {
		var headers = HTTPHeaders()
		headers.add(name: .contentType, value: "application/bson")
		let body = try BSONEncoder().encode(self)
		return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
	}
}

