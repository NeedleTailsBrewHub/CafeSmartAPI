//
//  ConfigController.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 2025-08-19.
//

@preconcurrency import BSON
import Vapor

actor ConfigController {
    func get(req: Request) async throws -> BusinessConfig {
        if let cfg = try await req.store.getBusinessConfig() {
            return cfg
        }
        throw Abort(.notFound)
    }
    
    func upsert(req: Request) async throws -> BusinessConfig {
        let cfg = try req.content.decode(BusinessConfig.self)
        return try await req.store.upsertBusinessConfig(cfg)
    }
}


