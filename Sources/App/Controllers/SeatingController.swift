//
//  SeatingController.swift
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

@preconcurrency import BSON
import Vapor

actor SeatingController {
    
    // Areas
    struct AreaCreate: Content {
        let name: String
        let defaultTurnMinutes: Int
        let active: Bool
    }
    
    struct AreaUpdate: Content {
        let name: String?
        let defaultTurnMinutes: Int?
        let active: Bool?
    }
    
    func listAreas(req: Request) async throws -> SeatingAreasWrapper {
        let items = try await req.store.listSeatingAreas()
        return SeatingAreasWrapper(items: items)
    }
    
    func createArea(req: Request) async throws -> SeatingArea {
        let body = try req.content.decode(AreaCreate.self)
        let area = SeatingArea(
            id: ObjectId().hexString,
            name: body.name,
            defaultTurnMinutes: body.defaultTurnMinutes,
            active: body.active)
        return try await req.store.create(seatingArea: area)
    }
    
    func getArea(req: Request) async throws -> SeatingArea {
        guard let id = req.parameters.get("id"), let area = try await req.store.findSeatingArea(by: id) else {
            throw Abort(.notFound)
        }
        return area
    }
    
    func updateArea(req: Request) async throws -> SeatingArea {
        guard let id = req.parameters.get("id"), var area = try await req.store.findSeatingArea(by: id) else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(AreaUpdate.self)
        if let name = body.name {
            area.name = name
        }
        if let turn = body.defaultTurnMinutes {
            area.defaultTurnMinutes = turn
        }
        if let active = body.active {
            area.active = active
        }
        return try await req.store.update(seatingArea: area)
    }
    
    func deleteArea(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteSeatingArea(id: id)
        return .noContent
    }
    
    // Tables
    struct TableCreate: Content {
        let areaId: String
        let name: String
        let capacity: Int
        let accessible: Bool
        let highTop: Bool?
        let outside: Bool?
        let active: Bool
    }
    struct TableUpdate: Content {
        let areaId: String?
        let name: String?
        let capacity: Int?
        let accessible: Bool?
        let highTop: Bool?
        let outside: Bool?
        let active: Bool?
    }
    
    func listTables(req: Request) async throws -> TablesWrapper {
        let items = try await req.store.listTables()
        return TablesWrapper(items: items)
    }
    
    func listTablesInArea(req: Request) async throws -> TablesWrapper {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        let items = try await req.store.listTables(in: id)
        return TablesWrapper(items: items)
    }
    
    func createTable(req: Request) async throws -> Table {
        let body = try req.content.decode(TableCreate.self)
        let table = Table(
            id: ObjectId().hexString,
            areaId: body.areaId,
            name: body.name,
            capacity: body.capacity,
            accessible: body.accessible,
            highTop: body.highTop,
            outside: body.outside,
            active: body.active)
        return try await req.store.create(table: table)
    }
    
    func getTable(req: Request) async throws -> Table {
        guard let id = req.parameters.get("id"), let table = try await req.store.findTable(by: id) else {
            throw Abort(.notFound)
        }
        return table
    }
    
    func updateTable(req: Request) async throws -> Table {
        guard let id = req.parameters.get("id"), var table = try await req.store.findTable(by: id) else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(TableUpdate.self)
        if let areaId = body.areaId {
            table.areaId = areaId
        }
        if let name = body.name {
            table.name = name
        }
        if let capacity = body.capacity {
            table.capacity = capacity
        }
        if let accessible = body.accessible {
            table.accessible = accessible
        }
        if let highTop = body.highTop {
            table.highTop = highTop
        }
        if let outside = body.outside {
            table.outside = outside
        }
        if let active = body.active {
            table.active = active
        }
        return try await req.store.update(table: table)
    }
    
    func deleteTable(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteTable(id: id)
        return .noContent
    }
}


