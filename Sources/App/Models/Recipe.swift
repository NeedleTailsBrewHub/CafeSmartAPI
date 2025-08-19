//
//  Recipe.swift
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

public struct RecipeComponent: Codable, Sendable, Equatable {
	public var sku: String
	public var unitsPerItem: Double
	public var wastageRate: Double?
}

public struct Recipe: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var menuItemId: String
	public var components: [RecipeComponent]
	public var createdAt: Date
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

public struct RecipesWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
    public var items: [Recipe]
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


