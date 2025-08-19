import Foundation
import Testing
import Vapor
import BSON
import MongoKitten
import NIO
import NIOHTTP1
import WebSocketKit
@testable import cafe_smart_api


@Suite(.serialized)
struct EndpointTests {

    private func makeApp(adminEmail: String? = nil) async throws -> Application {
        if let adminEmail { setenv("ADMIN_USERNAMES", adminEmail, 1) }
        let app = try await Application.make(.testing)
        try await configure(app)
        return app
    }

    @Test func predictorModelLifecycleAndForecastEndpoints() async throws {
        let adminEmail = "admin12@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        defer {
            Task {
                try? await app.asyncShutdown()
            }
        }
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Activate model (no-op in testing but should return 200 and broadcast)
        struct ActivateReq: Content {
            let id: String
        }
        var res = try await request(app, .POST, "/api/predictor/models/activate", token: adminToken, bson: ActivateReq(id: ObjectId().hexString))
        #expect(res.status == .ok)

        // Instantiate predictors by kind (no-op in testing but should return 200)
        struct InstReq: Content {
            let kind: String
        }
        res = try await request(app, .POST, "/api/predictor/instantiate", token: adminToken, bson: InstReq(kind: "workloadHourly"))
        #expect(res.status == .ok)
        res = try await request(app, .POST, "/api/predictor/instantiate", token: adminToken, bson: InstReq(kind: "reservationsHourly"))
        #expect(res.status == .ok)
        res = try await request(app, .POST, "/api/predictor/instantiate", token: adminToken, bson: InstReq(kind: "restockDaily"))
        #expect(res.status == .ok)

        // Forecast endpoints should succeed in testing and return synthetic points
        struct WorkloadReq: Content { let hoursAhead: Int }
        struct ResvReq: Content { let hoursAhead: Int }
        struct RestockReq: Content { let daysAhead: Int; let menuItemId: String }
        struct FCPoint: Content { let date: Date; let value: Double }
        struct FCResp: Content { let points: [FCPoint] }

        res = try await request(app, .POST, "/api/predictor/forecast/workload-hourly", token: adminToken, bson: WorkloadReq(hoursAhead: 3))
        #expect(res.status == .ok)
        var fc = try res.content.decode(FCResp.self)
        #expect(fc.points.count == 3)

        res = try await request(app, .POST, "/api/predictor/forecast/reservations-hourly", token: adminToken, bson: ResvReq(hoursAhead: 2))
        #expect(res.status == .ok)
        fc = try res.content.decode(FCResp.self)
        #expect(fc.points.count == 2)

        res = try await request(app, .POST, "/api/predictor/forecast/restock-daily", token: adminToken, bson: RestockReq(daysAhead: 5, menuItemId: "m1"))
        #expect(res.status == .ok)
        fc = try res.content.decode(FCResp.self)
        #expect(fc.points.count == 5)

        // No forecast websocket route anymore; skip WS verification here
    }
    private func request(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        if let token {
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.authorization, value: "Bearer \(token)")
        }
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/bson")
        return try await app.responder.respond(to: req).get()
    }

    private func request<T: Content>(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String? = nil,
        bson: T
    ) async throws -> Response {
        let req = Request(
            application: app,
            method: method,
            url: URI(path: path),
            on: app.eventLoopGroup.next()
        )
        if let token {
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.authorization, value: "Bearer \(token)")
        }
        try req.content.encode(bson, as: .bson)
        req.headers.replaceOrAdd(name: HTTPHeaders.Name.accept, value: "application/bson")
        return try await app.responder.respond(to: req).get()
    }

    private func registerAndLogin(app: Application, email: String, password: String, name: String? = nil, isAdmin: Bool = true) async throws -> (user: UserPublic, token: String) {
        struct RegisterRequest: Content {
            let email: String
            let password: String
            let name: String?
            let isAdmin: Bool
        }
        let register = RegisterRequest(email: email, password: password, name: name, isAdmin: isAdmin)
        _ = try await request(app, .POST, "/api/auth/register", bson: register)

        struct LoginRequest: Content { let email: String; let password: String }
        struct TokenResponse: Content { let token: String; let expiresAt: Date; let user: UserPublic }
        let loginReq = LoginRequest(email: email, password: password)
        let res = try await request(app, .POST, "/api/auth/login", bson: loginReq)
        #expect(res.status == .ok)
        let body = try res.content.decode(TokenResponse.self)
        return (body.user, body.token)
    }

    // MARK: Tests

    @Test func authRegisterLoginRefresh() async throws {
        let app = try await makeApp()

        let (user, token) = try await registerAndLogin(app: app, email: "user@example.com", password: "password123", name: "Test User")
        #expect(user.email == "user@example.com")
        #expect(!token.isEmpty)

        struct TokenResponse: Content { let token: String; let expiresAt: Date; let user: UserPublic }
        let refresh = try await request(app, .POST, "/api/auth/refresh-token", token: token)
        #expect(refresh.status == .ok)
        let refreshed = try refresh.content.decode(TokenResponse.self)
        #expect(!refreshed.token.isEmpty)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func menuCrudWithAdmin() async throws {
        let adminEmail = "admin@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct Create: Content { let name: String; let description: String?; let priceCents: Int; let isAvailable: Bool; let category: String? }
        let create = Create(name: "Latte", description: "Milk", priceCents: 499, isAvailable: true, category: "Drinks")
        var res = try await request(app, .POST, "/api/menu", token: adminToken, bson: create)
        #expect(res.status == .ok || res.status == .created)

        res = try await request(app, .GET, "/api/menu", token: adminToken)
        #expect(res.status == .ok)
        let list = try res.content.decode(MenuItemsWrapper.self).items
        #expect(list.count == 1)
        let item = list[0]

        // GET by id
        res = try await request(app, .GET, "/api/menu/\(item.id)", token: adminToken)
        #expect(res.status == .ok)

        struct Update: Content { let name: String?; let description: String?; let priceCents: Int?; let isAvailable: Bool?; let category: String? }
        let update = Update(name: "Iced Latte", description: nil, priceCents: 599, isAvailable: nil, category: nil)
        res = try await request(app, .PUT, "/api/menu/\(item.id)", token: adminToken, bson: update)
        #expect(res.status == .ok)
        let updated = try res.content.decode(MenuItem.self)
        #expect(updated.name == "Iced Latte")
        #expect(updated.priceCents == 599)

        res = try await request(app, .DELETE, "/api/menu/\(item.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func ordersFlowUserAndAdmin() async throws {
        let adminEmail = "admin2@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        let (_, userToken) = try await registerAndLogin(app: app, email: "user2@example.com", password: "password123")
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct OrderItemReq: Content { let menuItemId: String; let quantity: Int; let notes: String? }
        struct OrderCreateReq: Content { let customerName: String?; let items: [OrderItemReq]; let pickupTime: Date? }
        let body = OrderCreateReq(customerName: "Bob", items: [OrderItemReq(menuItemId: "sku-1", quantity: 2, notes: nil)], pickupTime: nil)
        var res = try await request(app, .POST, "/api/orders", token: userToken, bson: body)
        #expect(res.status == .ok || res.status == .created)
        let order = try res.content.decode(Order.self)

        // GET list
        res = try await request(app, .GET, "/api/orders", token: userToken)
        #expect(res.status == .ok)
        let list = try res.content.decode(OrdersWrapper.self).items
        #expect(list.count == 1)

        // GET by id
        res = try await request(app, .GET, "/api/orders/\(order.id)", token: userToken)
        #expect(res.status == .ok)

        struct StatusUpdate: Content { let status: OrderStatus }
        res = try await request(app, .PATCH, "/api/orders/\(order.id)/status", token: adminToken, bson: StatusUpdate(status: .completed))
        #expect(res.status == .ok)
        let updated = try res.content.decode(Order.self)
        #expect(updated.status == .completed)

        res = try await request(app, .DELETE, "/api/orders/\(order.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func reservationsFlowUserAndAdminDelete() async throws {
        let adminEmail = "admin3@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        let (_, userToken) = try await registerAndLogin(app: app, email: "user3@example.com", password: "password123")
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct ReservationCreateReq: Content { let name: String; let partySize: Int; let startTime: Date; let phone: String?; let notes: String? }
        let now = Date().addingTimeInterval(3600)
        let body = ReservationCreateReq(name: "Alice", partySize: 4, startTime: now, phone: nil, notes: nil)
        var res = try await request(app, .POST, "/api/reservations", token: userToken, bson: body)
        #expect(res.status == .ok || res.status == .created)
        let created = try res.content.decode(Reservation.self)

        // GET list
        res = try await request(app, .GET, "/api/reservations", token: userToken)
        #expect(res.status == .ok)
        let list = try res.content.decode(ReservationsWrapper.self).items
        #expect(list.count == 1)

        // GET by id
        res = try await request(app, .GET, "/api/reservations/\(created.id)", token: userToken)
        #expect(res.status == .ok)

        res = try await request(app, .DELETE, "/api/reservations/\(created.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func inventoryCrudAdminOnly() async throws {
        let adminEmail = "admin4@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct Create: Content { let sku: String; let name: String; let quantity: Int; let reorderThreshold: Int; let unit: String; let supplier: String? }
        let create = Create(sku: "SKU-1", name: "Beans", quantity: 10, reorderThreshold: 5, unit: "bag", supplier: nil)
        var res = try await request(app, .POST, "/api/inventory", token: adminToken, bson: create)
        #expect(res.status == .ok || res.status == .created)

        // GET list
        res = try await request(app, .GET, "/api/inventory", token: adminToken)
        #expect(res.status == .ok)
        let list = try res.content.decode(InventoryItemsWrapper.self).items
        #expect(list.count == 1)
        let item = list[0]

        // GET by id
        res = try await request(app, .GET, "/api/inventory/\(item.id)", token: adminToken)
        #expect(res.status == .ok)

        struct Update: Content { let name: String?; let quantity: Int?; let reorderThreshold: Int?; let unit: String?; let supplier: String? }
        let update = Update(name: "Premium Beans", quantity: 12, reorderThreshold: nil, unit: nil, supplier: nil)
        res = try await request(app, .PUT, "/api/inventory/\(item.id)", token: adminToken, bson: update)
        #expect(res.status == .ok)
        let updated = try res.content.decode(InventoryItem.self)
        #expect(updated.name == "Premium Beans")
        #expect(updated.quantity == 12)

        res = try await request(app, .DELETE, "/api/inventory/\(item.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func loyaltyAndPredictorEndpoints() async throws {
        let adminEmail = "admin5@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (user, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        struct Enroll: Content { let userId: String }
        var res = try await request(app, .POST, "/api/loyalty/enroll", token: adminToken, bson: Enroll(userId: user.id))
        #expect(res.status == .ok)

        // GET loyalty account by id should succeed
        struct LoyaltyAccountPublic: Content { let id: String; let userId: String; let points: Int; let tier: String }
        let enrolled = try res.content.decode(LoyaltyAccountPublic.self)
        res = try await request(app, .GET, "/api/loyalty/\(enrolled.id)", token: adminToken)
        #expect(res.status == .ok)

        struct Accrue: Content { let userId: String; let points: Int }
        res = try await request(app, .POST, "/api/loyalty/accrue", token: adminToken, bson: Accrue(userId: user.id, points: 120))
        #expect(res.status == .ok)

        struct Redeem: Content { let userId: String; let points: Int }
        res = try await request(app, .POST, "/api/loyalty/redeem", token: adminToken, bson: Redeem(userId: user.id, points: 20))
        #expect(res.status == .ok)

        // Redeem too many points should fail with 400
        res = try await request(app, .POST, "/api/loyalty/redeem", token: adminToken, bson: Redeem(userId: user.id, points: 999_999))
        #expect(res.status == .badRequest)

        struct PredictorReq: Content { let horizonDays: Int }
        res = try await request(app, .POST, "/api/predictor/generate", token: adminToken, bson: PredictorReq(horizonDays: 3))
        #expect(res.status == .ok)

        res = try await request(app, .GET, "/api/predictor/latest", token: adminToken)
        #expect(res.status == .ok)

        // Export CSV should return text/csv
        res = try await request(app, .GET, "/api/predictor/export", token: adminToken)
        #expect(res.status == .ok)
        #expect(res.headers.first(name: .contentType) == "text/csv; charset=utf-8")

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func recipesCrudAndListByMenuItem() async throws {
        let adminEmail = "admin6@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Create a menu item to attach a recipe to
        struct MenuCreate: Content { let name: String; let description: String?; let priceCents: Int; let isAvailable: Bool; let category: String? }
        let mc = MenuCreate(name: "Cappuccino", description: nil, priceCents: 399, isAvailable: true, category: "Drinks")
        var res = try await request(app, .POST, "/api/menu", token: adminToken, bson: mc)
        #expect(res.status == .ok || res.status == .created)
        let createdItem = try res.content.decode(MenuItem.self)

        // Create a recipe
        let comps = [RecipeComponent(sku: "BEANS", unitsPerItem: 18.0, wastageRate: 0.05), RecipeComponent(sku: "MILK", unitsPerItem: 160.0, wastageRate: nil)]
        struct RecipeCreate: Content { let menuItemId: String; let components: [RecipeComponent] }
        let rc = RecipeCreate(menuItemId: createdItem.id, components: comps)
        res = try await request(app, .POST, "/api/recipes", token: adminToken, bson: rc)
        #expect(res.status == .ok || res.status == .created)
        let recipe = try res.content.decode(Recipe.self)

        // List recipes
        res = try await request(app, .GET, "/api/recipes", token: adminToken)
        #expect(res.status == .ok)
        let recipes = try res.content.decode(RecipesWrapper.self).items
        #expect(recipes.count == 1)

        // Get by id
        res = try await request(app, .GET, "/api/recipes/\(recipe.id)", token: adminToken)
        #expect(res.status == .ok)

        // List for menu item
        res = try await request(app, .GET, "/api/menu/\(createdItem.id)/recipes", token: adminToken)
        #expect(res.status == .ok)
        let forItem = try res.content.decode(RecipesWrapper.self).items
        #expect(forItem.count == 1)

        // Update recipe components
        struct RecipeUpdate: Content { let components: [RecipeComponent]? }
        let updatedComps = [RecipeComponent(sku: "BEANS", unitsPerItem: 20.0, wastageRate: 0.05)]
        res = try await request(app, .PUT, "/api/recipes/\(recipe.id)", token: adminToken, bson: RecipeUpdate(components: updatedComps))
        #expect(res.status == .ok)

        // Delete
        res = try await request(app, .DELETE, "/api/recipes/\(recipe.id)", token: adminToken)
        #expect(res.status == .noContent)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func seatingAreasAndTablesCrudWithCascade() async throws {
        let adminEmail = "admin7@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Create area
        struct AreaCreate: Content { let name: String; let defaultTurnMinutes: Int; let active: Bool }
        var res = try await request(app, .POST, "/api/seating/areas", token: adminToken, bson: AreaCreate(name: "Main Hall", defaultTurnMinutes: 90, active: true))
        #expect(res.status == .ok || res.status == .created)
        let area = try res.content.decode(SeatingArea.self)

        // List areas
        res = try await request(app, .GET, "/api/seating/areas", token: adminToken)
        #expect(res.status == .ok)

        // Create table
        struct TableCreate: Content { let areaId: String; let name: String; let capacity: Int; let accessible: Bool; let highTop: Bool?; let outside: Bool?; let active: Bool }
        res = try await request(app, .POST, "/api/seating/tables", token: adminToken, bson: TableCreate(areaId: area.id, name: "T1", capacity: 2, accessible: false, highTop: nil, outside: nil, active: true))
        #expect(res.status == .ok || res.status == .created)
        let table = try res.content.decode(Table.self)

        // Get area by id
        res = try await request(app, .GET, "/api/seating/areas/\(area.id)", token: adminToken)
        #expect(res.status == .ok)

        // List tables in area
        res = try await request(app, .GET, "/api/seating/areas/\(area.id)/tables", token: adminToken)
        #expect(res.status == .ok)
        var tables = try res.content.decode(TablesWrapper.self).items
        #expect(tables.count == 1)

        // List all tables
        res = try await request(app, .GET, "/api/seating/tables", token: adminToken)
        #expect(res.status == .ok)

        // Get table by id
        res = try await request(app, .GET, "/api/seating/tables/\(table.id)", token: adminToken)
        #expect(res.status == .ok)

        // Update table
        struct TableUpdate: Content { let name: String?; let capacity: Int? }
        res = try await request(app, .PUT, "/api/seating/tables/\(table.id)", token: adminToken, bson: TableUpdate(name: "T1-Window", capacity: 3))
        #expect(res.status == .ok)

        // Cascade: delete area should remove tables
        res = try await request(app, .DELETE, "/api/seating/areas/\(area.id)", token: adminToken)
        #expect(res.status == .noContent)
        res = try await request(app, .GET, "/api/seating/areas/\(area.id)/tables", token: adminToken)
        #expect(res.status == .ok)
        tables = try res.content.decode(TablesWrapper.self).items
        #expect(tables.count == 0)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func businessConfigUpsertAndGet() async throws {
        let adminEmail = "admin8@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Unauthorized without token
        var res = try await request(app, .GET, "/api/config")
        #expect(res.status == .unauthorized)

        // Initially 404 when authorized but no config present
        res = try await request(app, .GET, "/api/config", token: adminToken)
        #expect(res.status == .notFound)

        // Upsert
        let hours: [BusinessHours] = [BusinessHours(weekday: 2, open: "07:00", close: "19:00"), BusinessHours(weekday: 3, open: "07:00", close: "19:00")]
        let staffing = StaffingRules(ordersPerBaristaPerHour: 40, ordersPerBakerPerHour: 30, guestsPerHostPerHour: 50)
        let cfg = BusinessConfig(id: ObjectId().hexString, timezone: "America/New_York", hours: hours, seatingCapacity: 45, staffing: staffing)
        res = try await request(app, .PUT, "/api/config", token: adminToken, bson: cfg)
        #expect(res.status == .ok)

        // Get should return 200
        res = try await request(app, .GET, "/api/config", token: adminToken)
        #expect(res.status == .ok)
        let fetched = try res.content.decode(BusinessConfig.self)
        #expect(fetched.timezone == "America/New_York")

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    // MARK: WebSocket Tests

    @Test func websocketMerchantRequiresAdmin() async throws {
        let app = try await makeApp()
        // Start server on a random port
        app.http.server.configuration.port = 0
        try await app.http.server.shared.start(address: nil)
        guard let port = app.http.server.shared.localAddress?.port else { #expect(Bool(false), "Missing port"); return }

        // Attempt to connect without Authorization should fail the upgrade
        do {
            try await WebSocket.connect(
                to: "ws://127.0.0.1:\(port)/api/ws/merchant",
                on: app.eventLoopGroup,
                onUpgrade: { _ async in }
            )
            #expect(Bool(false), "WebSocket connection should have failed without auth")
        } catch {
            // Expected: invalid response status
            #expect(String(describing: error).contains("invalidResponseStatus") || String(describing: error).contains("401"))
        }

        // Gracefully stop the HTTP server before shutting the app down
        await app.http.server.shared.shutdown()
        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func websocketOrdersPingPong() async throws {
        let app = try await makeApp()
        let (_, token) = try await registerAndLogin(app: app, email: "wsuser@example.com", password: "password123")

        // Start server on a random port
        app.http.server.configuration.port = 0
        try await app.http.server.shared.start(address: nil)
        guard let port = app.http.server.shared.localAddress?.port else { #expect(Bool(false), "Missing port"); return }

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(token)")

        let pongPromise = app.eventLoopGroup.any().makePromise(of: Void.self)

        try await WebSocket.connect(
            to: "ws://127.0.0.1:\(port)/api/ws/customer",
            headers: headers,
            on: app.eventLoopGroup
        ) { ws async in
            ws.onPong { _, _ async in
                pongPromise.succeed(())
                try? await ws.close()
            }
            try? await ws.sendPing()
        }

        try await pongPromise.futureResult.get()
        // Gracefully stop the HTTP server before shutting the app down
        await app.http.server.shared.shutdown()
        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func userAccountEndpointsLogoutUpdatePasswordDeleteAccount() async throws {
        let app = try await makeApp()
        let email = "acct@example.com"
        let originalPassword = "password123"

        // Register and login
        let (_, token) = try await registerAndLogin(app: app, email: email, password: originalPassword)

        // Logout should succeed
        var res = try await request(app, .POST, "/api/auth/logout", token: token)
        #expect(res.status == .ok)

        // Update password
        struct UpdatePasswordReq: Content { let oldPassword: String; let newPassword: String }
        let newPassword = "newPassword456"
        res = try await request(app, .POST, "/api/auth/update-password", token: token, bson: UpdatePasswordReq(oldPassword: originalPassword, newPassword: newPassword))
        #expect(res.status == .ok)

        // Login with old password should fail
        struct LoginRequest: Content { let email: String; let password: String }
        res = try await request(app, .POST, "/api/auth/login", bson: LoginRequest(email: email, password: originalPassword))
        #expect(res.status == .unauthorized)

        // Login with new password should succeed
        res = try await request(app, .POST, "/api/auth/login", bson: LoginRequest(email: email, password: newPassword))
        #expect(res.status == .ok)

        // Delete account
        let res2 = try await request(app, .POST, "/api/auth/login", bson: LoginRequest(email: email, password: newPassword))
        #expect(res2.status == .ok)
        let tokenRes = try res2.content.decode(TokenResponse.self)
        let del = try await request(app, .DELETE, "/api/auth/account", token: tokenRes.token)
        #expect(del.status == .noContent)

        // Login should now fail
        let afterDel = try await request(app, .POST, "/api/auth/login", bson: LoginRequest(email: email, password: newPassword))
        #expect(afterDel.status == .unauthorized)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func inventoryAuthRequirements() async throws {
        let adminEmail = "admin9@example.com"
        let app = try await makeApp(adminEmail: adminEmail)

        // Without token => 401
        var res = try await request(app, .GET, "/api/inventory")
        #expect(res.status == .unauthorized)

        // With non-admin token => custom 995 code
        let (_, userToken) = try await registerAndLogin(app: app, email: "notadmin@example.com", password: "password123", isAdmin: false)
        res = try await request(app, .GET, "/api/inventory", token: userToken)
        #expect(res.status.code == 995)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func ordersCreateValidatesItems() async throws {
        let app = try await makeApp()
        let (_, token) = try await registerAndLogin(app: app, email: "orderfail@example.com", password: "password123")

        struct OrderItemReq: Content { let menuItemId: String; let quantity: Int; let notes: String? }
        struct OrderCreateReq: Content { let customerName: String?; let items: [OrderItemReq]; let pickupTime: Date? }
        let bad = OrderCreateReq(customerName: "Bob", items: [], pickupTime: nil)
        let res = try await request(app, .POST, "/api/orders", token: token, bson: bad)
        #expect(res.status == .badRequest)

        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func websocketInventoryRequiresAdminAndBroadcasts() async throws {
        let adminEmail = "admin10@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, userToken) = try await registerAndLogin(app: app, email: "wsnonadmin@example.com", password: "password123", isAdmin: false)
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Start server on a random port
        app.http.server.configuration.port = 0
        try await app.http.server.shared.start(address: nil)
        guard let port = app.http.server.shared.localAddress?.port else { #expect(Bool(false), "Missing port"); return }

        // Non-admin should be rejected
        do {
            var headers = HTTPHeaders(); headers.add(name: .authorization, value: "Bearer \(userToken)")
            try await WebSocket.connect(
                to: "ws://127.0.0.1:\(port)/api/ws/merchant",
                headers: headers,
                on: app.eventLoopGroup,
                onUpgrade: { _ async in }
            )
            #expect(Bool(false), "WebSocket connection should have failed for non-admin")
        } catch {
            #expect(String(describing: error).contains("invalidResponseStatus") || String(describing: error).contains("995") || String(describing: error).contains("401"))
        }

        // Admin connects and receives broadcast
        var headers = HTTPHeaders(); headers.add(name: .authorization, value: "Bearer \(adminToken)")
        let packetPromise = app.eventLoopGroup.any().makePromise(of: RealtimeHub.MessagePacket.self)

        try await WebSocket.connect(
            to: "ws://127.0.0.1:\(port)/api/ws/merchant",
            headers: headers,
            on: app.eventLoopGroup
        ) { ws async in
            ws.onBinary { _, buf async in
                let data = [UInt8](buf.readableBytesView)
                let doc = Document(data: Data(data))
                do {
                    let packet = try BSONDecoder().decode(RealtimeHub.MessagePacket.self, from: doc)
                    packetPromise.succeed(packet)
                } catch {
                    packetPromise.fail(error)
                }
                try? await ws.close()
            }
        }

        // Allow subscription registration
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Publish an inventory restocked packet
        let item = InventoryItem(id: ObjectId().hexString, sku: "SKU-INV", name: "Milk", quantity: 5, reorderThreshold: 2, unit: "L", supplier: nil)
        await app.realtime.publish(.inventory(.restocked(item)), to: .merchant)

        let received = try await packetPromise.futureResult.get()
        switch received {
        case .inventory(let info):
            switch info {
            case .restocked(let rec):
                #expect(rec.sku == item.sku)
                #expect(rec.name == item.name)
            default:
                #expect(Bool(false), "Expected inventory.restocked packet")
            }
        default:
            #expect(Bool(false), "Expected inventory packet")
        }

        await app.http.server.shared.shutdown()
        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

    @Test func websocketForecastRequiresAdmin() async throws {
        let adminEmail = "admin11@example.com"
        let app = try await makeApp(adminEmail: adminEmail)
        let (_, userToken) = try await registerAndLogin(app: app, email: "wsnonadmin2@example.com", password: "password123", isAdmin: false)
        let (_, adminToken) = try await registerAndLogin(app: app, email: adminEmail, password: "password123")

        // Start server on a random port
        app.http.server.configuration.port = 0
        try await app.http.server.shared.start(address: nil)
        guard let port = app.http.server.shared.localAddress?.port else { #expect(Bool(false), "Missing port"); return }

        // Non-admin should be rejected
        do {
            var headers = HTTPHeaders(); headers.add(name: .authorization, value: "Bearer \(userToken)")
            try await WebSocket.connect(
                to: "ws://127.0.0.1:\(port)/api/ws/merchant",
                headers: headers,
                on: app.eventLoopGroup,
                onUpgrade: { _ async in }
            )
            #expect(Bool(false), "WebSocket connection should have failed for non-admin")
        } catch {
            #expect(String(describing: error).contains("invalidResponseStatus") || String(describing: error).contains("995") || String(describing: error).contains("401"))
        }

        // Admin ping/pong check
        var headers2 = HTTPHeaders(); headers2.add(name: .authorization, value: "Bearer \(adminToken)")
        let pongPromise = app.eventLoopGroup.any().makePromise(of: Void.self)
        try await WebSocket.connect(
            to: "ws://127.0.0.1:\(port)/api/ws/merchant",
            headers: headers2,
            on: app.eventLoopGroup
        ) { ws async in
            ws.onPong { _, _ async in
                pongPromise.succeed(())
                try? await ws.close()
            }
            try? await ws.sendPing()
        }
        _ = try await pongPromise.futureResult.get()

        await app.http.server.shared.shutdown()
        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }
}

