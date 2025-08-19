//
//  InventoryController.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 2025-08-19.
//

@preconcurrency import BSON
import MongoKitten
import Vapor
import Metrics

actor InventoryController {
    private let collection = "inventory_items"
    
    struct InventoryItemCreate: Content {
        let sku: String
        let name: String
        let quantity: Int
        let reorderThreshold: Int
        let unit: String
        let supplier: String?
    }
    
    struct InventoryItemUpdate: Content {
        let name: String?
        let quantity: Int?
        let reorderThreshold: Int?
        let unit: String?
        let supplier: String?
    }
    
    func list(req: Request) async throws -> InventoryItemsWrapper {
        let items = try await req.store.listInventory()
        return InventoryItemsWrapper(items: items)
    }
    
    func create(req: Request) async throws -> InventoryItem {
        let body = try req.content.decode(InventoryItemCreate.self)
        let model = InventoryItem(
            id: ObjectId().hexString, sku: body.sku, name: body.name, quantity: body.quantity,
            reorderThreshold: body.reorderThreshold, unit: body.unit, supplier: body.supplier)
        let created = try await req.store.create(inventoryItem: model)
        CafeDomainMetrics.recordInventoryLevel(itemId: created.id, sku: created.sku, level: created.quantity, threshold: created.reorderThreshold)
        if created.quantity <= created.reorderThreshold {
            CafeDomainMetrics.recordInventoryLow(itemId: created.id, sku: created.sku, level: created.quantity, threshold: created.reorderThreshold)
        }
        return created
    }
    
    func get(req: Request) async throws -> InventoryItem {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard let item = try await req.store.findInventory(by: id) else {
            throw Abort(.notFound)
        }
        return item
    }
    
    func update(req: Request) async throws -> InventoryItem {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        let body = try req.content.decode(InventoryItemUpdate.self)
        guard var model = try await req.store.findInventory(by: id) else {
            throw Abort(.notFound)
        }
        if let name = body.name { model.name = name }
        if let qty = body.quantity { model.quantity = qty }
        if let threshold = body.reorderThreshold {
            model.reorderThreshold = threshold
        }
        if let unit = body.unit {
            model.unit = unit
        }
        if let supplier = body.supplier {
            model.supplier = supplier
        }
        let updated = try await req.store.update(inventoryItem: model)
        CafeDomainMetrics.recordInventoryLevel(itemId: updated.id, sku: updated.sku, level: updated.quantity, threshold: updated.reorderThreshold)
        if updated.quantity <= updated.reorderThreshold {
            CafeDomainMetrics.recordInventoryLow(itemId: updated.id, sku: updated.sku, level: updated.quantity, threshold: updated.reorderThreshold)
        }
        return updated
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else { throw Abort(.badRequest) }
        try await req.store.deleteInventory(id: id)
        return .noContent
    }
}
