//
//  User.swift
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

public struct User: Content, Sendable, Equatable, BSONResponseEncodable {
	public var id: String
	public var email: String
	public var name: String?
	public var isAdmin: Bool
	public var passwordHash: String
	public var symmetricKey: Data
	public var createdAt: Date
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


