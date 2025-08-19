//
//  PredictorModels.swift
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

public enum PredictRuntime: String, Codable, Sendable, Equatable { case onnx, coreml }

public enum PredictorKind: String, Codable, Sendable, CaseIterable, Equatable {
	case workloadHourly
	case reservationsHourly
	case restockDaily
	case reservationDuration
}

public struct MLModelArtifact: Content, Sendable, Equatable, BSONResponseEncodable {
	public var _id: ObjectId
	public var id: String
	public var filename: String
	public var runtime: PredictRuntime
	public var kind: PredictorKind
	public var storedAt: String
	public var bytes: Int
	public var active: Bool
	public var uploadedAt: Date
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

public struct MLModelsWrapper: Content, Sendable, Equatable, BSONResponseEncodable {
    public var items: [MLModelArtifact]
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}


