@preconcurrency import BSON
import JWT
//
//  AuthenticationMiddleware.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  All rights reserved. Unauthorized copying, distribution, or use
//  of this software is strictly prohibited.
//
//  This file is part of the CafeSmartAPI Project
//
import Vapor

/// Middleware for authenticating API requests in the NeedleTail system.
///
/// This middleware validates JWT tokens and user credentials for REST API
/// requests. It extracts user information from request headers, verifies
/// the JWT token using the user's device HMAC key, and stores authenticated
/// user data in the request storage for use by subsequent handlers.
///
/// ## Authentication Flow
/// 1. Extract nickname and token from request headers
/// 2. Look up user in database using username
/// 3. Verify device exists in user's verified devices
/// 4. Verify JWT token using device's HMAC key
/// 5. Check token expiration
/// 6. Store authenticated user data in request storage
///
/// ## Required Headers
/// - `x-nickname`: User's nickname with device ID
/// - `x-token`: JWT token for authentication
///
/// ## Custom Error Codes
/// - `997`: API Info Missing (missing required headers)
/// - `998`: User Not Found For Request (user not in database)
/// - `999`: User Device Not Found Denied Access (device not verified)
///
/// ## Usage
/// ```swift
/// // Apply to routes that require authentication
/// app.group("api") { api in
///     api.group(AuthenticationMiddleware()) { protected in
///         protected.get("user", "profile") { req in
///             // Access authenticated user data
///             let user = try req.auth.require(User.self)
///             return user
///         }
///     }
/// }
/// ```
struct AuthenticationMiddleware: AsyncMiddleware {

  /**
   * Processes the request and authenticates the user.
   *
   * This method extracts authentication information from request headers,
   * validates the user and device, verifies the JWT token, and stores
   * the authenticated user data for use by subsequent handlers.
   *
   * - Parameters:
   *   - request: The incoming HTTP request
   *   - next: The next responder in the middleware chain
   * - Returns: The response from the next handler or an error response
   * - Throws: Various errors during authentication process
   */
  func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
    // Expect Authorization: Bearer <token>
    guard let authHeader = request.headers.bearerAuthorization else {
      return Response(status: .unauthorized)
    }
    do {
      let verified = try await request.jwt.verify(authHeader.token, as: UserJWT.self)
      // Load user
      guard let user = try await request.store.findUser(byId: verified.subject.value) else {
        return Response(status: .unauthorized)
      }
      // Store minimal context
      await request.storage.setWithAsyncShutdown(UserKey.self, to: user)
        await request.storage.setWithAsyncShutdown(IsAdminKey.self, to: user.isAdmin)
      return try await next.respond(to: request)
    } catch {
      throw error
    }
  }
}

/// Storage key for the authenticated user.
///
/// This key is used to store the complete User object of the
/// authenticated user in the request storage.
struct UserKey: StorageKey {
  typealias Value = User
}

/// Storage key for the server admin flag.
///
/// This key is used to store whether the authenticated user
/// has server admin privileges in the request storage.
struct IsAdminKey: StorageKey {
  typealias Value = Bool
}
