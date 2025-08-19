//
//  TestableMongoStore.swift
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
import Foundation
import Vapor

public actor TestableMongoStore: MongoStore {
    public let id = UUID()
    
    // In-memory collections
    private var users: [User] = []
    private var orders: [Order] = []
    private var inventoryItems: [InventoryItem] = []
    private var menuItems: [MenuItem] = []
    private var reservations: [Reservation] = []
    private var recipes: [Recipe] = []
    private var seatingAreas: [SeatingArea] = []
    private var tables: [Table] = []
    private var businessConfig: BusinessConfig? = nil
    private var modelArtifacts: [MLModelArtifact] = []
    
    // Refresh tokens stored with userId and expiry (no need to decrypt in tests)
    private struct StoredRefresh: Equatable {
        let userId: String
        let expiresAt: Date
        let data: Data
    }
    
    // MARK: - ML Model Artifacts (testing cache)
    
    public func createModelArtifact(_ artifact: MLModelArtifact) async throws {
        modelArtifacts.removeAll { $0._id == artifact._id }
        modelArtifacts.append(artifact)
    }
    
    public func listModelArtifacts() async throws -> [MLModelArtifact] { modelArtifacts }
    
    public func findModelArtifact(by id: String) async throws -> MLModelArtifact? {
        guard let oid = ObjectId(id) else { return nil }
        return modelArtifacts.first { $0._id == oid }
    }
    
    public func setActiveModel(id: String) async throws {
        guard let oid = ObjectId(id) else { return }
        // Single active per kind: deactivate same kind, activate target
        if let target = modelArtifacts.first(where: { $0._id == oid }) {
            let kind = target.kind
            modelArtifacts = modelArtifacts.map { item in
                var m = item
                if m.kind == kind { m.active = (m._id == oid) } else { /* keep as is */ }
                return m
            }
        }
    }
    
    public func deleteModelArtifact(id: String) async throws {
        guard let oid = ObjectId(id) else { return }
        modelArtifacts.removeAll { $0._id == oid }
    }
    private var refreshTokens: [StoredRefresh] = []
    
    // MARK: Init
    public init(seedDummyData: Bool = false) {
        var shouldSeed = seedDummyData
        let seedEnv = (
            Environment.get("SEED_TEST_DATA")
            ?? ""
        ).lowercased()
        if seedEnv == "true" {
             shouldSeed = true 
             }
        if shouldSeed {
            let bundle = Self.makeDummyData()
            self.users = bundle.users
            self.inventoryItems = bundle.inventory
            self.menuItems = bundle.menu
            self.recipes = bundle.recipes
            self.seatingAreas = bundle.areas
            self.tables = bundle.tables
            self.reservations = bundle.reservations
            self.orders = bundle.orders
            self.businessConfig = bundle.config
        }
    }
    
    // MARK: Users
    public func createUser(_ user: User) async throws {
        users.removeAll { $0.id == user.id }
        users.append(user)
    }
    
    public func listUsers() async throws -> [User] { users }
    
    public func findUser(byId id: String) async throws -> User? { users.first { $0.id == id } }
    
    public func findUser(byEmail emailLowercased: String) async throws -> User? {
        users.first { $0.email.lowercased() == emailLowercased }
    }
    
    public func updateUser(_ user: User) async throws -> User {
        if let idx = users.firstIndex(where: { $0.id == user.id }) {
            users[idx] = user
        } else {
            users.append(user)
        }
        return user
    }
    
    public func updatePassword(user: User) async throws {
        if let idx = users.firstIndex(where: { $0.id == user.id }) { users[idx] = user }
    }
    
    public func deleteUser(id: String) async throws { users.removeAll { $0.id == id } }
    
    // MARK: Orders
    public func create(order: Order) async throws -> Order {
        orders.removeAll { $0.id == order.id }
        orders.append(order)
        return order
    }
    
    public func listOrders() async throws -> [Order] { orders }
    
    public func findOrder(by id: String) async throws -> Order? { orders.first { $0.id == id } }
    
    public func update(order: Order) async throws -> Order {
        if let idx = orders.firstIndex(where: { $0.id == order.id }) {
            orders[idx] = order
        } else {
            orders.append(order)
        }
        return order
    }
    
    public func deleteOrder(id: String) async throws { orders.removeAll { $0.id == id } }
    
    // MARK: Inventory
    public func create(inventoryItem: InventoryItem) async throws -> InventoryItem {
        inventoryItems.removeAll { $0.id == inventoryItem.id }
        inventoryItems.append(inventoryItem)
        return inventoryItem
    }
    
    public func listInventory() async throws -> [InventoryItem] {
        inventoryItems
    }
    
    public func findInventory(by id: String) async throws -> InventoryItem? {
        inventoryItems.first { $0.id == id }
    }
    
    public func update(inventoryItem: InventoryItem) async throws -> InventoryItem {
        if let idx = inventoryItems.firstIndex(where: { $0.id == inventoryItem.id }) {
            inventoryItems[idx] = inventoryItem
        } else {
            inventoryItems.append(inventoryItem)
        }
        return inventoryItem
    }
    
    public func deleteInventory(id: String) async throws { inventoryItems.removeAll { $0.id == id } }
    
    // MARK: Menu
    public func create(menuItem: MenuItem) async throws -> MenuItem {
        menuItems.removeAll { $0.id == menuItem.id }
        menuItems.append(menuItem)
        return menuItem
    }
    
    public func listMenu() async throws -> [MenuItem] { menuItems }
    
    public func findMenuItem(by id: String) async throws -> MenuItem? {
        menuItems.first { $0.id == id }
    }
    
    public func update(menuItem: MenuItem) async throws -> MenuItem {
        if let idx = menuItems.firstIndex(where: { $0.id == menuItem.id }) {
            menuItems[idx] = menuItem
        } else {
            menuItems.append(menuItem)
        }
        return menuItem
    }
    
    public func deleteMenuItem(id: String) async throws { menuItems.removeAll { $0.id == id } }
    
    // MARK: Reservations
    public func create(reservation: Reservation) async throws -> Reservation {
        reservations.removeAll { $0.id == reservation.id }
        reservations.append(reservation)
        return reservation
    }
    
    public func listReservations() async throws -> [Reservation] { reservations }
    
    public func findReservation(by id: String) async throws -> Reservation? {
        reservations.first { $0.id == id }
    }
    
    public func deleteReservation(id: String) async throws { reservations.removeAll { $0.id == id } }
    
    // MARK: Refresh tokens & cleanup
    public func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws
    -> Data
    {
        let data = try BSONEncoder().encode(token).makeData()
        let sealed = try AES.GCM.seal(data, using: symmetricKey)
        guard let combined = sealed.combined else { throw Abort(.badRequest) }
        // Track by userId and expiry for fast lookups in tests
        refreshTokens.append(
            StoredRefresh(userId: token._id, expiresAt: token.expiresAt, data: combined))
        return combined
    }
    
    public func findUser(refreshToken: Data) async throws -> User? {
        if let stored = refreshTokens.first(where: { $0.data == refreshToken }) {
            return try await findUser(byId: stored.userId)
        }
        return nil
    }
    
    public func cleanupExpiredTokens() async throws {
        let now = Date()
        refreshTokens.removeAll { $0.expiresAt < now }
    }
    
    public func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey)
    async throws
    {
        let now = Date()
        refreshTokens.removeAll { $0.userId == username && $0.expiresAt < now }
    }
    
    public func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws {
        refreshTokens.removeAll { $0.userId == id }
    }
    
    public func removeUserTokens(_ user: User) async throws {
        refreshTokens.removeAll { $0.userId == user.id }
    }
    
    // MARK: Recipes
    public func create(recipe: Recipe) async throws -> Recipe {
        recipes.removeAll { $0.id == recipe.id }
        recipes.append(recipe)
        return recipe
    }
    
    public func listRecipes() async throws -> [Recipe] { recipes }
    
    public func findRecipe(by id: String) async throws -> Recipe? { recipes.first { $0.id == id } }
    
    public func findRecipes(menuItemId: String) async throws -> [Recipe] {
        recipes.filter { $0.menuItemId == menuItemId }
    }
    
    public func update(recipe: Recipe) async throws -> Recipe {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.append(recipe)
        }
        return recipe
    }
    
    public func deleteRecipe(id: String) async throws { recipes.removeAll { $0.id == id } }
    
    // MARK: Seating Areas
    public func create(seatingArea: SeatingArea) async throws -> SeatingArea {
        seatingAreas.removeAll { $0.id == seatingArea.id }
        seatingAreas.append(seatingArea)
        return seatingArea
    }
    
    public func listSeatingAreas() async throws -> [SeatingArea] { seatingAreas }
    
    public func findSeatingArea(by id: String) async throws -> SeatingArea? {
        seatingAreas.first { $0.id == id }
    }
    
    public func update(seatingArea: SeatingArea) async throws -> SeatingArea {
        if let idx = seatingAreas.firstIndex(where: { $0.id == seatingArea.id }) {
            seatingAreas[idx] = seatingArea
        } else {
            seatingAreas.append(seatingArea)
        }
        return seatingArea
    }
    
    public func deleteSeatingArea(id: String) async throws {
        seatingAreas.removeAll { $0.id == id }
        tables.removeAll { $0.areaId == id }
    }
    
    // MARK: Tables
    public func create(table: Table) async throws -> Table {
        tables.removeAll { $0.id == table.id }
        tables.append(table)
        return table
    }
    
    public func listTables() async throws -> [Table] { tables }
    
    public func findTable(by id: String) async throws -> Table? { tables.first { $0.id == id } }
    
    public func listTables(in areaId: String) async throws -> [Table] { tables.filter { $0.areaId == areaId } }
    
    public func update(table: Table) async throws -> Table {
        if let idx = tables.firstIndex(where: { $0.id == table.id }) {
            tables[idx] = table
        } else {
            tables.append(table)
        }
        return table
    }
    
    public func deleteTable(id: String) async throws { tables.removeAll { $0.id == id } }
    
    // MARK: Business Config
    public func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig {
        businessConfig = config
        return config
    }
    
    public func getBusinessConfig() async throws -> BusinessConfig? {
        businessConfig
    }
    
    // MARK: - Seeding
    private struct SeedBundle {
        let users: [User]
        let inventory: [InventoryItem]
        let menu: [MenuItem]
        let recipes: [Recipe]
        let areas: [SeatingArea]
        let tables: [Table]
        let reservations: [Reservation]
        let orders: [Order]
        let config: BusinessConfig
    }
    
    private static func makeDummyData() -> SeedBundle {
        let now = Date()
        
        // Users
        let adminId = ObjectId().hexString
        let userId = ObjectId().hexString
        let adminHash: String = (try? Bcrypt.hash("AdminPass123!")) ?? "$2b$12$H1Jg3b7xFQwN4k4ZlQp2xOUxJqzq0vWbQe7j8dQ8d2oT6i6vL2U9y"
        let userHash: String = (try? Bcrypt.hash("UserPass123!")) ?? "$2b$12$H1Jg3b7xFQwN4k4ZlQp2xOUxJqzq0vWbQe7j8dQ8d2oT6i6vL2U9y"
        let admin = User(
            id: adminId,
            email: "admin@cafesmart.test",
            name: "Cafe Admin",
            isAdmin: true,
            passwordHash: adminHash,
            symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            createdAt: now.addingTimeInterval(-86400)
        )
        let regular = User(
            id: userId,
            email: "jane.doe@cafesmart.test",
            name: "Jane Doe",
            isAdmin: false,
            passwordHash: userHash,
            symmetricKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            createdAt: now.addingTimeInterval(-43200)
        )
        let users = [admin, regular]
        
        // Inventory
        var invBeans = InventoryItem(
            id: ObjectId().hexString, sku: "BEANS-ESP-1KG", name: "Espresso Beans 1kg", quantity: 4,
            reorderThreshold: 5, unit: "bag", supplier: "Roasters Inc.")
        // Configure optional fields for variety
        invBeans.leadTimeDays = 3 // onHand(4) <= safety(5) even without forecast => restock
        var invMilk = InventoryItem(
            id: ObjectId().hexString, sku: "DAIRY-MILK-1L", name: "Whole Milk 1L", quantity: 60,
            reorderThreshold: 15, unit: "carton", supplier: "Local Dairy")
        invMilk.storage = .refrigerated
        invMilk.shelfLifeDays = 10
        invMilk.leadTimeDays = 2 // ROP smaller; onHand stays high => no restock
        let invCroissant = InventoryItem(
            id: ObjectId().hexString, sku: "BAKERY-DOUGH-CROIS", name: "Croissant Dough", quantity: 200,
            reorderThreshold: 50, unit: "unit", supplier: "Bakery Supply")
        let invSugar = InventoryItem(
            id: ObjectId().hexString, sku: "SWEET-SUGAR-1KG", name: "Granulated Sugar 1kg", quantity: 30,
            reorderThreshold: 5, unit: "bag", supplier: "Sweet Co.")
        let inventory = [invBeans, invMilk, invCroissant, invSugar]
        
        // Menu
        let espressoId = ObjectId().hexString
        var espresso = MenuItem(
            id: espressoId, name: "Espresso", description: "Rich shot of espresso",
            priceCents: 300, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-7200)
        )
        espresso.prepSeconds = 60
        espresso.prepStation = "Barista"
        
        let cappuccinoId = ObjectId().hexString
        var cappuccino = MenuItem(
            id: cappuccinoId, name: "Cappuccino", description: "Espresso with steamed milk and foam",
            priceCents: 450, isAvailable: true, category: "Coffee", createdAt: now.addingTimeInterval(-7000)
        )
        cappuccino.prepSeconds = 180
        cappuccino.prepStation = "Barista"
        cappuccino.allergens = [.milk]
        cappuccino.sizeOptions = [
            .init(name: "Small", priceDeltaCents: 0),
            .init(name: "Medium", priceDeltaCents: 50),
            .init(name: "Large", priceDeltaCents: 100),
        ]
        
        let croissantId = ObjectId().hexString
        var croissant = MenuItem(
            id: croissantId, name: "Butter Croissant", description: "Flaky French pastry",
            priceCents: 350, isAvailable: true, category: "Bakery", createdAt: now.addingTimeInterval(-6800)
        )
        croissant.prepSeconds = 600
        croissant.prepStation = "Bakery"
        croissant.allergens = [.gluten, .milk]
        
        let menu = [espresso, cappuccino, croissant]
        
        // Recipes (tie to inventory SKUs)
        let recipeEspresso = Recipe(
            id: ObjectId().hexString,
            menuItemId: espressoId,
            components: [
                .init(sku: invBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invSugar.sku, unitsPerItem: 0.0),
            ],
            createdAt: now
        )
        let recipeCappuccino = Recipe(
            id: ObjectId().hexString,
            menuItemId: cappuccinoId,
            components: [
                .init(sku: invBeans.sku, unitsPerItem: 0.018, wastageRate: 0.02),
                .init(sku: invMilk.sku, unitsPerItem: 0.2, wastageRate: 0.05),
                .init(sku: invSugar.sku, unitsPerItem: 0.005),
            ],
            createdAt: now
        )
        let recipeCroissant = Recipe(
            id: ObjectId().hexString,
            menuItemId: croissantId,
            components: [
                .init(sku: invCroissant.sku, unitsPerItem: 1.0, wastageRate: 0.03),
            ],
            createdAt: now
        )
        let recipes = [recipeEspresso, recipeCappuccino, recipeCroissant]
        
        // Seating Areas and Tables
        let mainAreaId = ObjectId().hexString
        let patioAreaId = ObjectId().hexString
        let main = SeatingArea(id: mainAreaId, name: "Main Hall", defaultTurnMinutes: 60, active: true)
        let patio = SeatingArea(id: patioAreaId, name: "Patio", defaultTurnMinutes: 75, active: true)
        let areas = [main, patio]
        
        let t1 = Table(id: ObjectId().hexString, areaId: mainAreaId, name: "T1", capacity: 2, accessible: true, highTop: false, outside: false, active: true)
        let t2 = Table(id: ObjectId().hexString, areaId: mainAreaId, name: "T2", capacity: 4, accessible: false, highTop: false, outside: false, active: true)
        let t3 = Table(id: ObjectId().hexString, areaId: patioAreaId, name: "P1", capacity: 4, accessible: true, highTop: false, outside: true, active: true)
        let tables = [t1, t2, t3]
        
        // Reservations
        let res1Id = ObjectId().hexString
        var res1 = Reservation(
            id: res1Id,
            name: "Jane Doe",
            partySize: 2,
            startTime: now.addingTimeInterval(3600),
            phone: "+1-555-111-2222",
            notes: "Window seat"
        )
        res1.durationMinutes = 90
        res1.areaId = mainAreaId
        res1.tableId = t1.id
        res1.status = .active
        
        let res2Id = ObjectId().hexString
        var res2 = Reservation(
            id: res2Id,
            name: "John Smith",
            partySize: 4,
            startTime: now.addingTimeInterval(7200),
            phone: "+1-555-333-4444",
            notes: nil
        )
        res2.durationMinutes = 120
        res2.areaId = patioAreaId
        res2.tableId = t3.id
        res2.status = .active
        
        var reservations = [res1, res2]
        
        // Orders (reference menu items and optionally reservation)
        let order1 = Order(
            id: ObjectId().hexString,
            status: .pending,
            customerName: "Jane Doe",
            items: [
                .init(menuItemId: espressoId, quantity: 1, notes: "Ristretto"),
                .init(menuItemId: croissantId, quantity: 2, notes: nil),
            ],
            pickupTime: nil,
            createdAt: now.addingTimeInterval(-1800)
        )
        var order1Extended = order1
        order1Extended.channel = .dineIn
        order1Extended.serviceType = .barista
        order1Extended.tableId = t1.id
        order1Extended.guests = 2
        order1Extended.reservationId = res1Id
        
        var order2 = Order(
            id: ObjectId().hexString,
            status: .preparing,
            customerName: "Walk-in",
            items: [
                .init(menuItemId: cappuccinoId, quantity: 2, notes: "Oat milk if available"),
            ],
            pickupTime: now.addingTimeInterval(900),
            createdAt: now.addingTimeInterval(-600)
        )
        order2.channel = .takeaway
        order2.serviceType = .barista
        
        var orders = [order1Extended, order2]

        // Generate historical orders and reservations to power CSV datasets
        let calendar = Calendar(identifier: .gregorian)
        let daysBack: Int = {
            if let raw = Environment.get("DUMMY_DAYS_BACK"), let v = Int(raw), v > 0 { return v }
            return 180 // default ~6 months
        }()
        if let start = calendar.date(byAdding: .day, value: -daysBack, to: now) {
            let menuIds = [espressoId, cappuccinoId, croissantId]
            let tableIds = [t1.id, t2.id, t3.id]
            let areaIds = [mainAreaId, patioAreaId]
            for d in 0...daysBack {
                guard let dayDate = calendar.date(byAdding: .day, value: d, to: start) else { continue }
                let weekday = calendar.component(.weekday, from: dayDate)
                let baseDemand: Double = (weekday == 1 || weekday == 7) ? 1.2 : 1.0
                let baseMin: Int = Int(Environment.get("DUMMY_BASE_ORDERS_MIN") ?? "") ?? 4
                let baseMax: Int = Int(Environment.get("DUMMY_BASE_ORDERS_MAX") ?? "") ?? 10
                let maxItemsPerOrder: Int = max(1, Int(Environment.get("DUMMY_MAX_ITEMS_PER_ORDER") ?? "") ?? 3)
                for hour in 7...20 { // business hours 7am-8pm
                    let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayDate) ?? dayDate
                    let rush: Double = (
                        (7...9).contains(hour) ? 1.6 : (
                            (12...13).contains(hour) ? 1.5 : (
                                (17...19).contains(hour) ? 1.4 : 0.8
                            )
                        )
                    )
                    let baseRandom = max(baseMin, min(baseMax, Int.random(in: baseMin...max(baseMin, baseMax))))
                    let ordersThisHour = max(0, Int(Double(baseRandom) * baseDemand * rush))
                    for _ in 0..<ordersThisHour {
                        let oid = ObjectId().hexString
                        let status: OrderStatus = [.completed, .preparing, .ready].randomElement() ?? .completed
                        var itemsList: [OrderItem] = []
                        let itemCount = 1 + Int.random(in: 0...max(0, maxItemsPerOrder - 1))
                        for _ in 0..<itemCount {
                            let mid = menuIds.randomElement() ?? espressoId
                            let qty = 1 + Int.random(in: 0...2)
                            itemsList.append(OrderItem(menuItemId: mid, quantity: qty, notes: nil))
                        }
                        let createdAt = hourDate.addingTimeInterval(TimeInterval(Int.random(in: 0...3599)))
                        var ord = Order(
                            id: oid,
                            status: status,
                            customerName: ["Alice","Bob","Carol","Dave","Erin","Frank"].randomElement(),
                            items: itemsList,
                            pickupTime: nil,
                            createdAt: createdAt
                        )
                        ord.channel = [.dineIn, .takeaway, .pickup, .delivery].randomElement()
                        ord.serviceType = [.barista, .kitchen, .bakery].randomElement()
                        if ord.channel == .dineIn {
                            ord.tableId = tableIds.randomElement()
                            ord.guests = [1,2,3,4].randomElement()
                        }
                        orders.append(ord)
                    }
                    // Reservations during lunch/dinner windows
                    if (11...13).contains(hour) || (17...20).contains(hour) {
                        let resCount = Int.random(in: 0...5)
                        for _ in 0..<resCount {
                            let rid = ObjectId().hexString
                            let startTime = hourDate.addingTimeInterval(TimeInterval(Int.random(in: 0...1800)))
                            var res = Reservation(
                                id: rid,
                                name: ["Jane","John","Alex","Sam","Taylor","Riley"].randomElement() ?? "Guest",
                                partySize: 2 + Int.random(in: 0...4),
                                startTime: startTime,
                                phone: nil,
                                notes: nil
                            )
                            res.durationMinutes = [60,75,90,120].randomElement()
                            res.areaId = areaIds.randomElement()
                            res.tableId = tableIds.randomElement()
                            res.status = [.active, .completed].randomElement()
                            reservations.append(res)
                        }
                    }
                }
            }
        }
        
        // Business Config
        let hours: [BusinessHours] = [
            .init(weekday: 1, open: "07:00", close: "19:00"),
            .init(weekday: 2, open: "07:00", close: "19:00"),
            .init(weekday: 3, open: "07:00", close: "19:00"),
            .init(weekday: 4, open: "07:00", close: "19:00"),
            .init(weekday: 5, open: "07:00", close: "21:00"),
            .init(weekday: 6, open: "08:00", close: "21:00"),
            .init(weekday: 7, open: "08:00", close: "17:00"),
        ]
        let staffing = StaffingRules(ordersPerBaristaPerHour: 40, ordersPerBakerPerHour: 25, guestsPerHostPerHour: 60)
        let config = BusinessConfig(
            id: ObjectId().hexString,
            timezone: "America/Los_Angeles",
            hours: hours,
            seatingCapacity: 60,
            staffing: staffing
        )
        
        return SeedBundle(
            users: users,
            inventory: inventory,
            menu: menu,
            recipes: recipes,
            areas: areas,
            tables: tables,
            reservations: reservations,
            orders: orders,
            config: config
        )
    }
}
