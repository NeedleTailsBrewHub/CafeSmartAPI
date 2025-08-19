//
//  RecipeController.swift
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

actor RecipeController {
    
    func list(req: Request) async throws -> RecipesWrapper {
        let items = try await req.store.listRecipes()
        return RecipesWrapper(items: items)
    }
    
    func listForMenuItem(req: Request) async throws -> RecipesWrapper {
        guard let menuItemId = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        let items = try await req.store.findRecipes(menuItemId: menuItemId)
        return RecipesWrapper(items: items)
    }
    
    struct Create: Content {
        let menuItemId: String
        let components: [RecipeComponent]
    }
    
    func create(req: Request) async throws -> Recipe {
        let body = try req.content.decode(Create.self)
        let rec = Recipe(
            id: ObjectId().hexString,
            menuItemId: body.menuItemId,
            components: body.components,
            createdAt: Date())
        return try await req.store.create(recipe: rec)
    }
    
    func get(req: Request) async throws -> Recipe {
        guard let id = req.parameters.get("id"), let rec = try await req.store.findRecipe(by: id) else {
            throw Abort(.notFound)
        }
        return rec
    }
    
    struct Update: Content {
        let components: [RecipeComponent]?
    }
    
    func update(req: Request) async throws -> Recipe {
        guard let id = req.parameters.get("id"), var rec = try await req.store.findRecipe(by: id) else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(Update.self)
        if let comps = body.components {
            rec = Recipe(
                id: rec.id,
                menuItemId: rec.menuItemId,
                components: comps,
                createdAt: rec.createdAt)
        }
        return try await req.store.update(recipe: rec)
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteRecipe(id: id)
        return .noContent
    }
}


