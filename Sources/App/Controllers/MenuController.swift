@preconcurrency import BSON
import MongoKitten
//
//  MenuController.swift
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

actor MenuController {
    private let collection = "menu_items"
    
    struct MenuItemCreate: Content {
        let name: String
        let description: String?
        let priceCents: Int
        let isAvailable: Bool
        let category: String?
    }
    
    struct MenuItemUpdate: Content {
        let name: String?
        let description: String?
        let priceCents: Int?
        let isAvailable: Bool?
        let category: String?
    }
    
    func list(req: Request) async throws -> MenuItemsWrapper {
        let items = try await req.store.listMenu()
        return MenuItemsWrapper(items: items)
    }
    
    func create(req: Request) async throws -> MenuItem {
        let create = try req.content.decode(MenuItemCreate.self)
        let model = MenuItem(
            id: ObjectId().hexString, name: create.name, description: create.description,
            priceCents: create.priceCents, isAvailable: create.isAvailable, category: create.category,
            createdAt: Date())
        let created = try await req.store.create(menuItem: model)
        CafeDomainMetrics.recordMenuPriceCents(menuItemId: created.id, priceCents: created.priceCents)
        CafeDomainMetrics.recordMenuAvailability(menuItemId: created.id, isAvailable: created.isAvailable)
        return created
    }
    
    func get(req: Request) async throws -> MenuItem {
        guard let idParam = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard let item = try await req.store.findMenuItem(by: idParam) else {
            throw Abort(.notFound)
        }
        return item
    }
    
    func update(req: Request) async throws -> MenuItem {
        guard let idParam = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        let body = try req.content.decode(MenuItemUpdate.self)
        guard var model = try await req.store.findMenuItem(by: idParam) else {
            throw Abort(.notFound)
        }
        if let name = body.name {
            model.name = name
        }
        if let description = body.description {
            model.description = description
        }
        if let price = body.priceCents {
            model.priceCents = price
        }
        if let avail = body.isAvailable {
            model.isAvailable = avail
        }
        if let category = body.category {
            model.category = category
        }
        let updated = try await req.store.update(menuItem: model)
        CafeDomainMetrics.recordMenuPriceCents(menuItemId: updated.id, priceCents: updated.priceCents)
        CafeDomainMetrics.recordMenuAvailability(menuItemId: updated.id, isAvailable: updated.isAvailable)
        return updated
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let idParam = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteMenuItem(id: idParam)
        return .noContent
    }
}
