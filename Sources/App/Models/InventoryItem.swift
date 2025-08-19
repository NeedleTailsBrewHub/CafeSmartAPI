//
//  InventoryItem.swift
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

public struct InventoryItem: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var sku: String
	public var name: String
	public var quantity: Int
	public var reorderThreshold: Int
	public var unit: String
	public var supplier: String?

	public var storage: StorageType? = nil
	public var shelfLifeDays: Int? = nil
	public var leadTimeDays: Int? = nil
	public var safetyStock: Int? = nil
	public var parLevel: Int? = nil
	public var reorderQuantity: Int? = nil

    public enum StorageType: String, Codable, Sendable, Equatable {
        case ambient, refrigerated, frozen
    }
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


