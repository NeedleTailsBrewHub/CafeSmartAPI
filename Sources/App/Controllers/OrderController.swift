@preconcurrency import BSON
import MongoKitten
//
//  OrderController.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  All rights reserved. Unauthorized copying, distribution, or use
//  of this software is strictly prohibited.
//
//  This file is part of the CafeSmartAPI Project
//
import Vapor
import Metrics

actor OrderController {
    private let collection = "orders"
    
    func list(req: Request) async throws -> OrdersWrapper {
        let items = try await req.store.listOrders()
        return OrdersWrapper(items: items)
    }
    
    func create(req: Request) async throws -> Order {
        let create = try req.content.decode(OrderCreateRequest.self)
        guard !create.items.isEmpty else {
            throw Abort(.badRequest, reason: "Order requires at least one item")
        }
        let now = Date()
        let model = Order(
            id: ObjectId().hexString, status: .pending, customerName: create.customerName,
            items: create.items, pickupTime: create.pickupTime, createdAt: now)
        let created = try await req.store.create(order: model)
        
        // Emit via domain metrics facade
        CafeDomainMetrics.recordOrderCreated(
            orderId: created.id,
            channel: created.channel?.rawValue,
            serviceType: created.serviceType?.rawValue)
        
        for item in created.items {
            
            CafeDomainMetrics.recordOrderItemDemand(
                orderId: created.id,
                menuItemId: item.menuItemId,
                channel: created.channel?.rawValue,
                serviceType: created.serviceType?.rawValue,
                quantity: Double(item.quantity))
            
        }
        return created
    }
    
    func get(req: Request) async throws -> Order {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard let order = try await req.store.findOrder(by: id) else {
            throw Abort(.notFound)
        }
        return order
    }
    
    func updateStatus(req: Request) async throws -> Order {
        let body = try req.content.decode(OrderStatusUpdateRequest.self)
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard var order = try await req.store.findOrder(by: id) else {
            throw Abort(.notFound)
        }
        order.status = body.status
        let updated = try await req.store.update(order: order)
        if body.status == .completed {
            
            CafeDomainMetrics.recordOrderCompleted(
                orderId: updated.id,
                channel: updated.channel?.rawValue,
                serviceType: updated.serviceType?.rawValue,
                seconds: Date().timeIntervalSince(updated.createdAt))
            
        } else if body.status == .canceled {
            CafeDomainMetrics.recordOrderCanceled(
                orderId: updated.id,
                channel: updated.channel?.rawValue,
                serviceType: updated.serviceType?.rawValue)
        }
        return updated
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteOrder(id: id)
        return .noContent
    }
}
