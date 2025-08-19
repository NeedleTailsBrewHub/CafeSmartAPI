//
//  Tokens.swift
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

public struct RefreshToken: Codable, Sendable, Equatable {
	public var _id: String // user id
	public var token: String
	public var expiresAt: Date
	public var issuedAt: Date
}


