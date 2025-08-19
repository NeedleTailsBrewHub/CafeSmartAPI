//
//  OrderRequests.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 2025-08-19.
//

import Vapor

public struct OrderCreateRequest: Content, Sendable {
	public var customerName: String?
	public var items: [OrderItem]
	public var pickupTime: Date?
}

public struct OrderStatusUpdateRequest: Content, Sendable {
	public var status: OrderStatus
}


