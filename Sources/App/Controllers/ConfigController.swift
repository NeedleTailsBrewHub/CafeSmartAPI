//
//  ConfigController.swift
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


