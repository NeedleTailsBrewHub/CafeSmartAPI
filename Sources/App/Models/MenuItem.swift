//
//  MenuItem.swift
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

import Foundation
import Vapor
import BSON

public struct MenuItem: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var name: String
	public var description: String?
	public var priceCents: Int
	public var isAvailable: Bool
	public var category: String?
	public var createdAt: Date
    // Optional fields used by seed data
    public var prepSeconds: Int? = nil
    public var prepStation: String? = nil
    public enum Allergen: String, Codable, Sendable, Equatable { case milk, gluten, nuts, soy }
    public struct SizeOption: Codable, Sendable, Equatable { public var name: String; public var priceDeltaCents: Int }
    public var allergens: [Allergen]? = nil
    public var sizeOptions: [SizeOption]? = nil
	public func encodeResponse(for request: Request) async throws -> Response {
		var headers = HTTPHeaders()
		headers.add(name: .contentType, value: "application/bson")
		let body = try BSONEncoder().encode(self)
		return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
	}
}

public struct MenuItemsWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
    public var items: [MenuItem]
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


