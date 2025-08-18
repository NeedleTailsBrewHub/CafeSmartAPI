@preconcurrency import BSON
import JWT
//
//  AdminMiddleware.swift
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

/// Middleware for enforcing admin-only access to API endpoints.
///
/// This middleware extends the AuthenticationMiddleware to add admin
/// authorization checks. It verifies that the authenticated user has
/// admin privileges before allowing access to protected endpoints.
struct AdminMiddleware: AsyncMiddleware {

  /// Reads the ADMIN_USERNAMES env var at request time to avoid stale caching in tests/process lifetime.
  private func currentAdminUsernames() -> Set<String> {
    let adminList = Environment.get("ADMIN_USERNAMES") ?? ""
    return Set(adminList.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
  }

  func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
    // Already marked as admin upstream
    if request.storage.get(IsAdminKey.self) == true {
      return try await next.respond(to: request)
    }

    // Require authenticated user in storage
    guard let user = request.storage.get(UserKey.self) else {
      return Response(
        status: .custom(code: 996, reasonPhrase: "Admin Check Failed - User Not Found"))
    }

    // Check against environment-driven admin list
    if currentAdminUsernames().contains(user.email) {
      await request.storage.setWithAsyncShutdown(IsAdminKey.self, to: true)
      return try await next.respond(to: request)
    } else {
      return Response(status: .custom(code: 995, reasonPhrase: "Admin Access Required"))
    }
  }
}

/// Extension to make it easy to check admin status in controllers.
extension Request {
  var isAdmin: Bool {
    get async { storage.get(IsAdminKey.self) ?? false }
  }
}
