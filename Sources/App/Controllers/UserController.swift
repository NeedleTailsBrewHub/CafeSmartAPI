//
//  UserController.swift
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
import Crypto
import JWT
import MongoKitten
import Vapor

struct UserPublic: Codable, Sendable, AsyncResponseEncodable {
    
    let id: String
    let email: String
    let name: String?
    let isAdmin: Bool
    
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

struct RegisterRequest: Content {
    let email: String
    let password: String
    let name: String?
    let isAdmin: Bool
}

struct LoginRequest: Content {
    let email: String
    let password: String
}

struct TokenResponse: Codable, Sendable, AsyncResponseEncodable {
    let token: String
    let refreshToken: String?
    let expiresAt: Date
    let user: UserPublic
    
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

struct UserJWT: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
        case subject = "sub"
    }
    var subject: SubjectClaim
    var expiration: ExpirationClaim
    func verify(using signer: some JWTAlgorithm) throws { try expiration.verifyNotExpired() }
}

struct ChangePasswordRequest: Content {
    let oldPassword: String
    let newPassword: String
}

actor UserController {
    // Create
    func register(req: Request) async throws -> UserPublic {
        let register = try req.content.decode(RegisterRequest.self)
        guard register.email.contains("@"), register.password.count >= 8 else {
            throw Abort(.badRequest, reason: "Invalid email or password too short")
        }
        if try await req.store.findUser(byEmail: register.email.lowercased()) != nil {
            throw Abort(.conflict, reason: "User already exists")
        }
        let passwordHash = try await req.password.async.hash(register.password)
        let user = User(
            id: ObjectId().hexString,
            email: register.email.lowercased(),
            name: register.name,
            isAdmin: register.isAdmin,
            passwordHash: passwordHash,
            symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            createdAt: Date())
        try await req.store.createUser(user)
        return UserPublic(
            id: user.id,
            email: user.email,
            name: user.name,
            isAdmin: user.isAdmin)
    }
    
    // Login -> token + public user
    func login(req: Request) async throws -> TokenResponse {
        let login = try req.content.decode(LoginRequest.self)
        guard let user = try await req.store.findUser(byEmail: login.email.lowercased()) else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        guard try await req.password.async.verify(login.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        let expirationDate = Date().addingTimeInterval(60 * 60 * 24)
        let payload = UserJWT(
            subject: .init(value: user.id), expiration: .init(value: expirationDate))
        let token = try await req.jwt.sign(payload)
        // Create and persist a refresh token, return as base64-encoded string
        let issuedAt = Date()
        let refreshExpiry = issuedAt.addingTimeInterval(60 * 60 * 24 * 30) // 30 days
        let refreshRandom = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let refreshSecret = Data(refreshRandom).base64EncodedString()
        let refresh = RefreshToken(
            _id: user.id,
            token: refreshSecret,
            expiresAt: refreshExpiry,
            issuedAt: issuedAt
        )
        let encryptedRefresh: Data = try await req.store.createRefreshToken(
            refresh,
            symmetricKey: SymmetricKey(data: user.symmetricKey)
        )
        let refreshTokenB64 = encryptedRefresh.base64EncodedString()
        return TokenResponse(
            token: token,
            refreshToken: refreshTokenB64,
            expiresAt: expirationDate,
            user: UserPublic(id: user.id, email: user.email, name: user.name, isAdmin: user.isAdmin))
    }
    
    // Read list
    func list(req: Request) async throws -> UsersWrapper {
        let users = try await req.store.listUsers()
        let publics = users.map { UserPublic(id: $0.id, email: $0.email, name: $0.name, isAdmin: $0.isAdmin) }
        return UsersWrapper(items: publics)
    }
    
    // Read single
    func get(req: Request) async throws -> UserPublic {
        guard let id = req.parameters.get("id"), let user = try await req.store.findUser(byId: id) else {
            throw Abort(.notFound)
        }
        return UserPublic(
            id: user.id,
            email: user.email,
            name: user.name,
            isAdmin: user.isAdmin)
    }
    
    // Update (name/email only; not password)
    struct UserUpdateRequest: Content {
        let email: String?
        let name: String?
    }
    func update(req: Request) async throws -> UserPublic {
        guard let id = req.parameters.get("id"), var user = try await req.store.findUser(byId: id)
        else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(UserUpdateRequest.self)
        if let email = body.email {
            user = User(
                id: user.id, email: email.lowercased(), name: user.name, isAdmin: user.isAdmin, passwordHash: user.passwordHash,
                symmetricKey: user.symmetricKey, createdAt: user.createdAt)
        }
        if let name = body.name {
            user = User(
                id: user.id, email: user.email, name: name, isAdmin: user.isAdmin, passwordHash: user.passwordHash,
                symmetricKey: user.symmetricKey, createdAt: user.createdAt)
        }
        let updated = try await req.store.updateUser(user)
        return UserPublic(
            id: updated.id,
            email: updated.email,
            name: updated.name,
            isAdmin: updated.isAdmin)
    }
    
    // Change password
    func changePassword(req: Request) async throws -> TokenResponse {
        guard let id = req.parameters.get("id"), var user = try await req.store.findUser(byId: id)
        else {
            throw Abort(.notFound)
        }
        let request = try req.content.decode(ChangePasswordRequest.self)
        guard try await req.password.async.verify(request.oldPassword, created: user.passwordHash)
        else {
            throw Abort(.unauthorized, reason: "Old password is incorrect")
        }
        user.passwordHash = try await req.password.async.hash(request.newPassword)
        try await req.store.updatePassword(user: user)
        let expirationDate = Date().addingTimeInterval(60 * 60 * 24)
        let payload = UserJWT(
            subject: .init(value: user.id), expiration: .init(value: expirationDate))
        let token = try await req.jwt.sign(payload)
        // Create and persist a refresh token, return as base64-encoded string
        let issuedAt = Date()
        let refreshExpiry = issuedAt.addingTimeInterval(60 * 60 * 24 * 30) // 30 days
        let refreshRandom = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let refreshSecret = Data(refreshRandom).base64EncodedString()
        let refresh = RefreshToken(
            _id: user.id,
            token: refreshSecret,
            expiresAt: refreshExpiry,
            issuedAt: issuedAt
        )
        let encryptedRefresh: Data = try await req.store.createRefreshToken(
            refresh,
            symmetricKey: SymmetricKey(data: user.symmetricKey)
        )
        let refreshTokenB64 = encryptedRefresh.base64EncodedString()
        return TokenResponse(
            token: token,
            refreshToken: refreshTokenB64,
            expiresAt: expirationDate,
            user: UserPublic(
                id: user.id,
                email: user.email,
                name: user.name,
                isAdmin: user.isAdmin))
    }
    
    // Logout current user (invalidate refresh tokens)
    func logout(req: Request) async throws -> HTTPStatus {
        guard let user = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        try await req.store.removeUserTokens(user)
        return .ok
    }
    
    // Update password for the authenticated user
    struct UpdatePasswordRequest: Content { let oldPassword: String; let newPassword: String }
    func updatePassword(req: Request) async throws -> HTTPStatus {
        guard var user = req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        let payload = try req.content.decode(UpdatePasswordRequest.self)
        guard try await req.password.async.verify(payload.oldPassword, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Old password is incorrect")
        }
        user.passwordHash = try await req.password.async.hash(payload.newPassword)
        try await req.store.updatePassword(user: user)
        return .ok
    }
    
    // Delete the authenticated user's account
    func deleteAccount(req: Request) async throws -> HTTPStatus {
        guard let user =  req.storage.get(UserKey.self) else {
            throw Abort(.unauthorized)
        }
        // Best effort: remove tokens then delete user
        try await req.store.removeUserTokens(user)
        try await req.store.deleteUser(id: user.id)
        return .noContent
    }
    // Delete
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        try await req.store.deleteUser(id: id)
        return .noContent
    }
    
    // Refresh access token
    func refreshToken(req: Request) async throws -> TokenResponse {
        let incoming = try await req.jwt.verify(as: UserJWT.self)
        let newExp = Date().addingTimeInterval(60 * 60 * 24)
        let newPayload = UserJWT(subject: incoming.subject, expiration: .init(value: newExp))
        let token = try await req.jwt.sign(newPayload)
        // Fetch user for convenience
        guard let user = try await req.store.findUser(byId: incoming.subject.value) else {
            throw Abort(.notFound)
        }
        return TokenResponse(
            token: token,
            refreshToken: nil,
            expiresAt: newExp,
            user: UserPublic(
                id: user.id,
                email: user.email,
                name: user.name,
                isAdmin: user.isAdmin))
    }
}
