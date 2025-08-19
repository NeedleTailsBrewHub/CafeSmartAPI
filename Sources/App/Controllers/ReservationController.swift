//
//  ReservationController.swift
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
import MongoKitten
import Vapor
import Metrics

actor ReservationController {
    private let collection = "reservations"
    
    struct ReservationCreate: Content {
        let name: String
        let partySize: Int
        let startTime: Date
        let phone: String?
        let notes: String?
    }
    
    func list(req: Request) async throws -> ReservationsWrapper {
        let items = try await req.store.listReservations()
        return ReservationsWrapper(items: items)
    }
    
    func create(req: Request) async throws -> Reservation {
        let body = try req.content.decode(ReservationCreate.self)
        guard body.partySize > 0 else {
            throw Abort(.badRequest)
        }
        let model = Reservation(
            id: ObjectId().hexString,
            name: body.name,
            partySize: body.partySize,
            startTime: body.startTime,
            phone: body.phone,
            notes: body.notes)
        
        let created = try await req.store.create(reservation: model)
        CafeDomainMetrics.recordReservationCreated(
            reservationId: created.id,
            partySize: created.partySize,
            areaId: created.areaId,
            tableId: created.tableId)
        return created
    }
    
    func get(req: Request) async throws -> Reservation {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        guard let reservation = try await req.store.findReservation(by: id) else {
            throw Abort(.notFound)
        }
        return reservation
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteReservation(id: id)
        return .noContent
    }
}
