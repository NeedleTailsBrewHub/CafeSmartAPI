//
//  Reservation.swift
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

public enum ReservationStatus: String, Codable, Sendable, Equatable { case active, completed, canceled }

public struct Reservation: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var name: String
	public var partySize: Int
	public var startTime: Date
	public var phone: String?
	public var notes: String?
	public var durationMinutes: Int?
	public var areaId: String?
	public var tableId: String?
	public var status: ReservationStatus?
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

public struct ReservationsWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
    public var items: [Reservation]
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


