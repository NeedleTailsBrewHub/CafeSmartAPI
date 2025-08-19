//
//  Order.swift
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

public enum OrderStatus: String, Codable, Sendable, Equatable {
	case pending
	case preparing
	case ready
	case completed
	case canceled
}

public struct OrderItem: Content, Sendable, Equatable {
	public var menuItemId: String
	public var quantity: Int
	public var notes: String?
}

public struct Order: Content, Sendable, Equatable, BSONResponseEncodable {
	public enum OrderChannel: String, Codable, Sendable, Equatable { case dineIn, takeaway, pickup, delivery }
	public enum ServiceType: String, Codable, Sendable, Equatable { case barista, kitchen, bakery }

	public var id: String
	public var status: OrderStatus
	public var customerName: String?
	public var items: [OrderItem]
	public var pickupTime: Date?
	public var channel: OrderChannel?
	public var serviceType: ServiceType?
	public var tableId: String?
	public var guests: Int?
	public var reservationId: String?
	public var createdAt: Date
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


