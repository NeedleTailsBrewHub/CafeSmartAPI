//
//  CafePredictorController.swift
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

private struct DBPredictionPoint: Codable {
    let date: Date
    let expectedOrders: Int
}
private struct DBPrediction: Codable {
    var _id: ObjectId
    var generatedAt: Date
    var horizonDays: Int
    var points: [DBPredictionPoint]
}

struct PredictorRequest: Content {
    let horizonDays: Int
}

struct PredictorPoint: Content {
    let date: Date
    let expectedOrders: Int
}

struct PredictorResponse: Content, AsyncResponseEncodable {
    let points: [PredictorPoint]
    let generatedAt: Date
    
    public func encodeResponse(for request: Request) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/bson")
        let body = try BSONEncoder().encode(self)
        return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
    }
}

actor CafePredictorController {
    
    private let predictionsCollection = "forecasts"  // keep existing collection for compatibility
    private let ordersCollection = "orders"
    private let metricsCollectionEnv = "CAFE_METRICS_COLLECTION"
    
    private struct SweepScheduledKey: StorageKey {
        typealias Value = Bool
    }
    
    private func ensureDailySweepScheduled(app: Application) {
        guard app.environment != .testing else { return }
        let already = app.storage[SweepScheduledKey.self] ?? false
        if already { return }
        app.storage[SweepScheduledKey.self] = true
        app.eventLoopGroup.next().scheduleRepeatedTask(initialDelay: .hours(24), delay: .hours(24)) { _ in
            Task { [app] in
                let results = await self.computeRestockDecisions(app: app)
                for r in results where r.decision.needRestock {
                    await app.realtime.publish(.inventory(.runningLow(r.item)), to: .merchant)
                }
            }
        }
    }
    
    // In-memory backing for testing environment
    private struct MemoryKey: StorageKey {
        typealias Value = [DBPrediction]
    }
    
    private func loadMemory(_ app: Application) -> [DBPrediction] {
        app.storage[MemoryKey.self] ?? []
    }
    private func saveMemory(_ app: Application, _ values: [DBPrediction]) {
        app.storage[MemoryKey.self] = values
    }
    
    func generate(req: Request) async throws -> PredictorResponse {
        let requestedDays = (try? req.content.decode(PredictorRequest.self))?.horizonDays ?? 7
        let days = max(1, min(requestedDays, 30))
        let since = Date().addingTimeInterval(-14 * 24 * 3600)
        
        struct OrderCreatedAtOnly: Codable { var createdAt: Date? }
        var counts: [String: Int] = [:]
        if req.application.environment == .testing {
            counts = [:]
        } else {
            for try await doc in req.mongoDB[ordersCollection].find() {
                if let decoded = try? BSONDecoder().decode(OrderCreatedAtOnly.self, from: doc),
                   let ts = decoded.createdAt, ts >= since
                {
                    let key = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: ts))
                    counts[key, default: 0] += 1
                }
            }
        }
        let total = counts.values.reduce(0, +)
        let daysCount = max(counts.count, 1)
        let avg = Double(total) / Double(daysCount)
        
        var points: [PredictorPoint] = []
        for i in 0..<days {
            let date = Calendar.current.date(byAdding: .day, value: i + 1, to: Date()) ?? Date()
            let weekday = Calendar.current.component(.weekday, from: date)
            let multiplier = (weekday == 1 || weekday == 7) ? 1.2 : 1.0
            let expected = Int((avg * multiplier).rounded())
            points.append(PredictorPoint(date: date, expectedOrders: expected))
        }
        
        let db = DBPrediction(
            _id: ObjectId(), generatedAt: Date(), horizonDays: days,
            points: points.map {
                DBPredictionPoint(
                    date: $0.date,
                    expectedOrders: $0.expectedOrders)
            }
        )
        if req.application.environment == .testing {
            var memory = loadMemory(req.application)
            memory.append(db)
            saveMemory(req.application, memory)
        } else {
            try await req.mongoDB[predictionsCollection].insert(BSONEncoder().encode(db))
        }
        return PredictorResponse(points: points, generatedAt: Date())
    }
    
    func latest(req: Request) async throws -> PredictorResponse {
        if req.application.environment == .testing {
            let memory = loadMemory(req.application)
            if let latest = memory.max(by: { $0.generatedAt < $1.generatedAt }) {
                return PredictorResponse(
                    points: latest.points.map {
                        PredictorPoint(
                            date: $0.date,
                            expectedOrders: $0.expectedOrders)
                    }, generatedAt: latest.generatedAt)
            } else {
                return try await generate(req: req)
            }
        } else {
            var latest: DBPrediction?
            for try await doc in req.mongoDB[predictionsCollection].find() {
                if let decoded = try? BSONDecoder().decode(DBPrediction.self, from: doc) {
                    if let current = latest {
                        if decoded.generatedAt > current.generatedAt { latest = decoded }
                    } else {
                        latest = decoded
                    }
                }
            }
            if let latest {
                return PredictorResponse(
                    points: latest.points.map {
                        PredictorPoint(date: $0.date, expectedOrders: $0.expectedOrders)
                    },
                    generatedAt: latest.generatedAt)
            }
            return try await generate(req: req)
        }
    }
    
    // MARK: Export Cafe Events as CSV
    struct CafeEventDB: Codable {
        var type: String
        var ts: Date
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var weekday: Int
        var orderId: String?
        var channel: String?
        var serviceType: String?
        var secondsToComplete: Double?
        var menuItemId: String?
        var quantity: Double?
        var inventoryItemId: String?
        var sku: String?
        var level: Double?
        var threshold: Double?
        var reservationId: String?
        var partySize: Int?
        var areaId: String?
        var tableId: String?
        var priceCents: Int?
        var available: Bool?
    }
    
    var isTestMode: Bool {
        let useTestStoreEnv = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
        return useTestStoreEnv == "1" || useTestStoreEnv == "true" || useTestStoreEnv == "yes"
    }
    
    func exportCSV(req: Request) async throws -> Response {
        
        let colName = Environment.get(metricsCollectionEnv) ?? "cafe_metrics"
        let dataset = (try? req.query.get(String.self, at: "dataset"))?.lowercased() ?? "raw"
        
        func esc(_ s: String?) -> String {
            guard let s = s, !s.isEmpty else { return "" }
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        
        let df = ISO8601DateFormatter()
        
        // Prepare temp file
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(colName)_export_\(UUID().uuidString).csv")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: tmpURL.path) else {
            throw Abort(.internalServerError)
        }
        defer { try? fh.close() }
        
        // Write header by mode
        enum Mode {
            case raw, orderCompleted, orderItemDemand, demandHourly
            case workloadHourly, reservationsHourly, restockDaily, reservationDuration
            case ingredientDaily
        }
        let mode: Mode = {
            switch dataset {
            case "ordercompleted":
                return .orderCompleted
            case "orderitemdemand":
                return .orderItemDemand
            case "demandhourly":
                return .demandHourly
            case "workloadhourly", "busytimes":
                return .workloadHourly
            case "reservationshourly", "resvhourly", "bestreservations":
                return .reservationsHourly
            case "restockdaily", "inventorydaily":
                return .restockDaily
            case "ingredientdaily":
                return .ingredientDaily
            case "reservationduration", "resvduration":
                return .reservationDuration
            default: return .raw
            }
        }()
        
        func write(_ s: String) throws {
            try fh.write(contentsOf: Data(s.utf8))
        }
        
        switch mode {
        case .raw:
            try write(
                [
                    "type", "ts", "year", "month", "day", "hour", "weekday",
                    "orderId", "channel", "serviceType", "secondsToComplete",
                    "menuItemId", "quantity", "inventoryItemId", "sku", "level", "threshold",
                    "reservationId", "partySize", "areaId", "tableId", "priceCents", "available",
                ].joined(separator: ",") + "\n")
        case .orderCompleted:
            try write(
                [
                    "ts", "year", "month", "day", "hour", "weekday", "channel", "serviceType",
                    "secondsToComplete",
                ].joined(separator: ",") + "\n")
        case .orderItemDemand:
            try write(
                [
                    "ts", "year", "month", "day", "hour", "weekday", "orderId", "channel", "serviceType",
                    "menuItemId", "quantity",
                ].joined(separator: ",") + "\n")
        case .demandHourly:
            try write(
                ["menuItemId", "year", "month", "day", "hour", "weekday", "demand"].joined(separator: ",")
                + "\n")
        case .workloadHourly:
            try write(
                [
                    "datetime", "year", "month", "day", "weekday", "hour", "is_weekend",
                    "orders_total_lag_1h", "orders_total_lag_24h",
                    "rolling_orders_total_last_3h", "rolling_orders_total_same_hour_last_7d",
                    "items_total_lag_1h", "unique_orders_lag_1h", "avg_items_per_order_lag_1h",
                    "orders_channel_dineIn_lag_1h", "orders_channel_takeaway_lag_1h",
                    "orders_channel_pickup_lag_1h", "orders_channel_delivery_lag_1h",
                    "orders_serviceType_barista_lag_1h", "orders_serviceType_kitchen_lag_1h",
                    "orders_serviceType_bakery_lag_1h",
                    "target_orders_total",
                ].joined(separator: ",") + "\n")
        case .reservationsHourly:
            try write(
                [
                    "datetime", "year", "month", "day", "weekday", "hour", "is_weekend",
                    "reservations_total_lag_1h", "reservations_total_lag_24h",
                    "rolling_reservations_total_last_3h", "rolling_reservations_total_same_hour_last_7d",
                    "target_reservations_total",
                ].joined(separator: ",") + "\n")
        case .restockDaily:
            // header written after determining menu item id
            break
        case .ingredientDaily:
            // header written after determining SKU
            break
        case .reservationDuration:
            try write(
                [
                    "reservation_id", "datetime", "year", "month", "day", "weekday", "hour", "is_weekend",
                    "party_size", "area_id", "table_id",
                    "target_duration_minutes",
                ].joined(separator: ",") + "\n")
        }
        
        // Aggregate if needed
        struct Key: Hashable {
            let menuItemId: String
            let year: Int
            let month: Int
            let day: Int
            let hour: Int
            let weekday: Int
        }
        var demand: [Key: Double] = [:]
        
        // Helpers for time buckets
        let calendar = Calendar(identifier: .gregorian)
        func startOfHour(_ date: Date) -> Date {
            calendar.date(
                bySetting: .minute, value: 0, of: calendar.date(bySetting: .second, value: 0, of: date)!)!
        }
        func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        
        // Workload/reservations aggregation maps
        struct HourBucket: Hashable { let date: Date }
        struct DayBucket: Hashable { let date: Date }
        struct HourStats {
            var ordersTotal: Int = 0
            var itemsTotal: Double = 0
            var uniqueOrders: Set<String> = []
            var channelCounts: [String: Int] = [:]
            var serviceTypeCounts: [String: Int] = [:]
        }
        var hourToStats: [HourBucket: HourStats] = [:]
        var allHourBuckets: Set<HourBucket> = []
        var hourToReservations: [HourBucket: Int] = [:]
        
        // Restock daily aggregation
        var dayToItemQty: [String: [DayBucket: Double]] = [:]
        var dayToOrdersTotal: [DayBucket: Int] = [:]
        var dayToItemsTotal: [DayBucket: Double] = [:]
        // Ingredient daily aggregation (by SKU)
        var dayToIngredientQty: [String: [DayBucket: Double]] = [:]
        // Preload recipes to map menu item → components (for ingredient usage)
        var recipeMap: [String: [RecipeComponent]] = [:]
        if mode == .ingredientDaily {
            if req.application.environment != .testing && !isTestMode {
                for try await doc in req.mongoDB["recipes"].find() {
                    if let r = try? BSONDecoder().decode(Recipe.self, from: doc) {
                        recipeMap[r.menuItemId] = r.components
                    }
                }
            } else {
                let recipes = try await req.store.listRecipes()
                for r in recipes { recipeMap[r.menuItemId] = r.components }
            }
        }
        
        if req.application.environment != .testing && !isTestMode {
            for try await doc in req.mongoDB[colName].find() {
                guard let ev = try? BSONDecoder().decode(CafeEventDB.self, from: doc) else { continue }
                switch mode {
                case .raw:
                    let row: [String] = [
                        ev.type,
                        df.string(from: ev.ts),
                        String(ev.year), String(ev.month), String(ev.day), String(ev.hour), String(ev.weekday),
                        esc(ev.orderId), esc(ev.channel), esc(ev.serviceType),
                        ev.secondsToComplete.map { String($0) } ?? "",
                        esc(ev.menuItemId), ev.quantity.map { String($0) } ?? "",
                        esc(ev.inventoryItemId), esc(ev.sku), ev.level.map { String($0) } ?? "",
                        ev.threshold.map { String($0) } ?? "",
                        esc(ev.reservationId), ev.partySize.map { String($0) } ?? "", esc(ev.areaId),
                        esc(ev.tableId), ev.priceCents.map { String($0) } ?? "",
                        ev.available.map { $0 ? "true" : "false" } ?? "",
                    ]
                    try write(row.joined(separator: ",") + "\n")
                case .orderCompleted:
                    guard ev.type == "orderCompleted", let sec = ev.secondsToComplete else { continue }
                    let row: [String] = [
                        df.string(from: ev.ts), String(ev.year), String(ev.month), String(ev.day),
                        String(ev.hour), String(ev.weekday),
                        esc(ev.channel), esc(ev.serviceType), String(sec),
                    ]
                    try write(row.joined(separator: ",") + "\n")
                case .orderItemDemand:
                    guard ev.type == "orderItemDemand", let q = ev.quantity else { continue }
                    let row: [String] = [
                        df.string(from: ev.ts), String(ev.year), String(ev.month), String(ev.day),
                        String(ev.hour), String(ev.weekday),
                        esc(ev.orderId), esc(ev.channel), esc(ev.serviceType), esc(ev.menuItemId), String(q),
                    ]
                    try write(row.joined(separator: ",") + "\n")
                case .demandHourly:
                    guard ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId else {
                        continue
                    }
                    let key = Key(
                        menuItemId: mid, year: ev.year, month: ev.month, day: ev.day, hour: ev.hour,
                        weekday: ev.weekday)
                    demand[key, default: 0.0] += q
                case .workloadHourly:
                    let hb = HourBucket(date: startOfHour(ev.ts))
                    allHourBuckets.insert(hb)
                    if ev.type == "orderCreated" {
                        var s = hourToStats[hb] ?? HourStats()
                        s.ordersTotal += 1
                        if let oid = ev.orderId { s.uniqueOrders.insert(oid) }
                        if let ch = ev.channel { s.channelCounts[ch, default: 0] += 1 }
                        if let st = ev.serviceType { s.serviceTypeCounts[st, default: 0] += 1 }
                        hourToStats[hb] = s
                    } else if ev.type == "orderItemDemand", let q = ev.quantity {
                        var s = hourToStats[hb] ?? HourStats()
                        s.itemsTotal += q
                        hourToStats[hb] = s
                    }
                case .reservationsHourly:
                    if ev.type == "reservationCreated" {
                        let hb = HourBucket(date: startOfHour(ev.ts))
                        allHourBuckets.insert(hb)
                        hourToReservations[hb, default: 0] += 1
                    }
                case .restockDaily:
                    if ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        var m = dayToItemQty[mid] ?? [:]
                        m[db, default: 0.0] += q
                        dayToItemQty[mid] = m
                        dayToItemsTotal[db, default: 0.0] += q
                    }
                    if ev.type == "orderCreated" {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        dayToOrdersTotal[db, default: 0] += 1
                    }
                case .ingredientDaily:
                    if ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        // Track overall items total as context, like restockDaily
                        dayToItemsTotal[db, default: 0.0] += q
                        if let comps = recipeMap[mid] {
                            for c in comps {
                                let factor = c.unitsPerItem * (1.0 + (c.wastageRate ?? 0.0))
                                let used = q * factor
                                var m = dayToIngredientQty[c.sku] ?? [:]
                                m[db, default: 0.0] += used
                                dayToIngredientQty[c.sku] = m
                            }
                        }
                    }
                    if ev.type == "orderCreated" {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        dayToOrdersTotal[db, default: 0] += 1
                    }
                case .reservationDuration:
                    // handled post-loop by querying reservations
                    break
                }
            }
        } else {
            // Testing: synthesize events from the in-memory store to generate a representative CSV
            func makeEvent(type: String, ts: Date) -> CafeEventDB {
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: ts)
                return CafeEventDB(
                    type: type,
                    ts: ts,
                    year: comps.year ?? 0,
                    month: comps.month ?? 0,
                    day: comps.day ?? 0,
                    hour: comps.hour ?? 0,
                    weekday: comps.weekday ?? 0,
                    orderId: nil,
                    channel: nil,
                    serviceType: nil,
                    secondsToComplete: nil,
                    menuItemId: nil,
                    quantity: nil,
                    inventoryItemId: nil,
                    sku: nil,
                    level: nil,
                    threshold: nil,
                    reservationId: nil,
                    partySize: nil,
                    areaId: nil,
                    tableId: nil,
                    priceCents: nil,
                    available: nil
                )
            }
            var events: [CafeEventDB] = []
            // Orders -> orderCreated, orderItemDemand, orderCompleted (synthetic)
            let orders = try await req.store.listOrders()
            for o in orders {
                var created = makeEvent(type: "orderCreated", ts: o.createdAt)
                created.orderId = o.id
                created.channel = o.channel?.rawValue
                created.serviceType = o.serviceType?.rawValue
                events.append(created)
                for it in o.items {
                    var dem = makeEvent(type: "orderItemDemand", ts: o.createdAt)
                    dem.orderId = o.id
                    dem.menuItemId = it.menuItemId
                    dem.quantity = Double(it.quantity)
                    dem.channel = o.channel?.rawValue
                    dem.serviceType = o.serviceType?.rawValue
                    events.append(dem)
                }
                if o.status == .completed {
                    var comp = makeEvent(type: "orderCompleted", ts: o.createdAt.addingTimeInterval(120))
                    comp.orderId = o.id
                    comp.channel = o.channel?.rawValue
                    comp.serviceType = o.serviceType?.rawValue
                    comp.secondsToComplete = max(10.0, Date().timeIntervalSince(o.createdAt))
                    events.append(comp)
                }
            }
            // Reservations -> reservationCreated at startTime
            let reservations = try await req.store.listReservations()
            for r in reservations {
                var ev = makeEvent(type: "reservationCreated", ts: r.startTime)
                ev.reservationId = r.id
                ev.partySize = r.partySize
                ev.areaId = r.areaId
                ev.tableId = r.tableId
                events.append(ev)
            }
            // Process synthesized events using the same aggregation logic
            for ev in events {
                switch mode {
                case .raw:
                    let row: [String] = [
                        ev.type,
                        df.string(from: ev.ts),
                        String(ev.year), String(ev.month), String(ev.day), String(ev.hour), String(ev.weekday),
                        esc(ev.orderId), esc(ev.channel), esc(ev.serviceType),
                        ev.secondsToComplete.map { String($0) } ?? "",
                        esc(ev.menuItemId), ev.quantity.map { String($0) } ?? "",
                        esc(ev.inventoryItemId), esc(ev.sku), ev.level.map { String($0) } ?? "",
                        ev.threshold.map { String($0) } ?? "",
                        esc(ev.reservationId), ev.partySize.map { String($0) } ?? "", esc(ev.areaId),
                        esc(ev.tableId), ev.priceCents.map { String($0) } ?? "",
                        ev.available.map { $0 ? "true" : "false" } ?? "",
                    ]
                    try write(row.joined(separator: ",") + "\n")
                case .orderCompleted:
                    guard ev.type == "orderCompleted", let sec = ev.secondsToComplete else { continue }
                    let row: [String] = [
                        df.string(from: ev.ts), String(ev.year), String(ev.month), String(ev.day),
                        String(ev.hour), String(ev.weekday),
                        esc(ev.channel), esc(ev.serviceType), String(sec),
                    ]
                    try write(row.joined(separator: ",") + "\n")
                case .orderItemDemand:
                    guard ev.type == "orderItemDemand", let q = ev.quantity else { continue }
                    let row: [String] = [
                        df.string(from: ev.ts), String(ev.year), String(ev.month), String(ev.day),
                        String(ev.hour), String(ev.weekday),
                        esc(ev.orderId), esc(ev.channel), esc(ev.serviceType), esc(ev.menuItemId), String(q),
                    ]
                    try write(row.joined(separator: ",") + "\n")
                case .demandHourly:
                    guard ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId else { continue }
                    let key = Key(menuItemId: mid, year: ev.year, month: ev.month, day: ev.day, hour: ev.hour, weekday: ev.weekday)
                    demand[key, default: 0.0] += q
                case .workloadHourly:
                    let hb = HourBucket(date: startOfHour(ev.ts))
                    allHourBuckets.insert(hb)
                    if ev.type == "orderCreated" {
                        var s = hourToStats[hb] ?? HourStats()
                        s.ordersTotal += 1
                        if let oid = ev.orderId { s.uniqueOrders.insert(oid) }
                        if let ch = ev.channel { s.channelCounts[ch, default: 0] += 1 }
                        if let st = ev.serviceType { s.serviceTypeCounts[st, default: 0] += 1 }
                        hourToStats[hb] = s
                    } else if ev.type == "orderItemDemand", let q = ev.quantity {
                        var s = hourToStats[hb] ?? HourStats()
                        s.itemsTotal += q
                        hourToStats[hb] = s
                    }
                case .reservationsHourly:
                    if ev.type == "reservationCreated" {
                        let hb = HourBucket(date: startOfHour(ev.ts))
                        allHourBuckets.insert(hb)
                        hourToReservations[hb, default: 0] += 1
                    }
                case .restockDaily:
                    if ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        var m = dayToItemQty[mid] ?? [:]
                        m[db, default: 0.0] += q
                        dayToItemQty[mid] = m
                        dayToItemsTotal[db, default: 0.0] += q
                    }
                    if ev.type == "orderCreated" {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        dayToOrdersTotal[db, default: 0] += 1
                    }
                case .ingredientDaily:
                    if ev.type == "orderItemDemand", let q = ev.quantity, let mid = ev.menuItemId {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        dayToItemsTotal[db, default: 0.0] += q
                        if let comps = recipeMap[mid] {
                            for c in comps {
                                let factor = c.unitsPerItem * (1.0 + (c.wastageRate ?? 0.0))
                                let used = q * factor
                                var m = dayToIngredientQty[c.sku] ?? [:]
                                m[db, default: 0.0] += used
                                dayToIngredientQty[c.sku] = m
                            }
                        }
                    }
                    if ev.type == "orderCreated" {
                        let db = DayBucket(date: startOfDay(ev.ts))
                        dayToOrdersTotal[db, default: 0] += 1
                    }
                case .reservationDuration:
                    // handled post-loop by querying reservations
                    break
                }
            }
        }
        
        if mode == .demandHourly {
            for (k, val) in demand {
                let row =
                [
                    k.menuItemId, String(k.year), String(k.month), String(k.day), String(k.hour),
                    String(k.weekday), String(val),
                ].joined(separator: ",") + "\n"
                try write(row)
            }
        }
        
        if mode == .workloadHourly {
            let sorted = allHourBuckets.map { $0 }.sorted { $0.date < $1.date }
            func stats(at d: Date) -> HourStats { hourToStats[HourBucket(date: d)] ?? HourStats() }
            for hb in sorted {
                let d = hb.date
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: d)
                let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                let lag1 = calendar.date(byAdding: .hour, value: -1, to: d)!
                let lag24 = calendar.date(byAdding: .hour, value: -24, to: d)!
                let sLag1 = stats(at: lag1)
                let sLag24 = stats(at: lag24)
                var sum3 = 0
                var cnt3 = 0
                for h in 1...3 {
                    let t = calendar.date(byAdding: .hour, value: -h, to: d)!
                    sum3 += stats(at: t).ordersTotal
                    cnt3 += 1
                }
                let avg3 = cnt3 > 0 ? Double(sum3) / Double(cnt3) : 0.0
                var sum7 = 0
                var cnt7 = 0
                for k in stride(from: 24, through: 24 * 7, by: 24) {
                    let t = calendar.date(byAdding: .hour, value: -k, to: d)!
                    sum7 += stats(at: t).ordersTotal
                    cnt7 += 1
                }
                let avg7 = cnt7 > 0 ? Double(sum7) / Double(cnt7) : 0.0
                let uniqueOrdersLag1 = sLag1.uniqueOrders.count
                let avgItemsPerOrderLag1 =
                sLag1.ordersTotal > 0 ? (sLag1.itemsTotal / Double(sLag1.ordersTotal)) : 0.0
                func cc(_ key: String) -> Int { sLag1.channelCounts[key] ?? 0 }
                func sc(_ key: String) -> Int { sLag1.serviceTypeCounts[key] ?? 0 }
                let row: [String] = [
                    df.string(from: d),
                    String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                    String(comps.weekday ?? 0), String(comps.hour ?? 0), isWeekend ? "true" : "false",
                    String(sLag1.ordersTotal), String(sLag24.ordersTotal),
                    String(format: "%.4f", avg3), String(format: "%.4f", avg7),
                    String(format: "%.4f", sLag1.itemsTotal), String(uniqueOrdersLag1),
                    String(format: "%.4f", avgItemsPerOrderLag1),
                    String(cc("dineIn")), String(cc("takeaway")), String(cc("pickup")),
                    String(cc("delivery")),
                    String(sc("barista")), String(sc("kitchen")), String(sc("bakery")),
                    String(stats(at: d).ordersTotal),
                ]
                try write(row.joined(separator: ",") + "\n")
            }
        }
        
        if mode == .reservationsHourly {
            let sorted = allHourBuckets.map { $0 }.sorted { $0.date < $1.date }
            func res(at d: Date) -> Int { hourToReservations[HourBucket(date: d)] ?? 0 }
            for hb in sorted {
                let d = hb.date
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: d)
                let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                let lag1 = calendar.date(byAdding: .hour, value: -1, to: d)!
                let lag24 = calendar.date(byAdding: .hour, value: -24, to: d)!
                var sum3 = 0
                var cnt3 = 0
                for h in 1...3 {
                    let t = calendar.date(byAdding: .hour, value: -h, to: d)!
                    sum3 += res(at: t)
                    cnt3 += 1
                }
                let avg3 = cnt3 > 0 ? Double(sum3) / Double(cnt3) : 0.0
                var sum7 = 0
                var cnt7 = 0
                for k in stride(from: 24, through: 24 * 7, by: 24) {
                    let t = calendar.date(byAdding: .hour, value: -k, to: d)!
                    sum7 += res(at: t)
                    cnt7 += 1
                }
                let avg7 = cnt7 > 0 ? Double(sum7) / Double(cnt7) : 0.0
                let row: [String] = [
                    df.string(from: d),
                    String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                    String(comps.weekday ?? 0), String(comps.hour ?? 0), isWeekend ? "true" : "false",
                    String(res(at: lag1)), String(res(at: lag24)),
                    String(format: "%.4f", avg3), String(format: "%.4f", avg7),
                    String(res(at: d)),
                ]
                try write(row.joined(separator: ",") + "\n")
            }
        }
        
        if mode == .restockDaily {
            let menuItemId: String? = try? req.query.get(String.self, at: "menuItemId")
            var allDays: Set<DayBucket> = []
            for m in dayToItemQty.values { for k in m.keys { allDays.insert(k) } }
            let sortedDays = allDays.map { $0 }.sorted { $0.date < $1.date }
            func qty(_ mid: String, _ d: DayBucket) -> Double { dayToItemQty[mid]?[d] ?? 0.0 }
            func orders(_ d: DayBucket) -> Int { dayToOrdersTotal[d] ?? 0 }
            func items(_ d: DayBucket) -> Double { dayToItemsTotal[d] ?? 0.0 }
            func writeHeader(for mid: String) throws {
                let header =
                [
                    "date", "year", "month", "day", "weekday", "is_weekend",
                    "orders_total_lag_1d", "items_total_lag_1d",
                    "qty_\(mid)_lag_1d", "qty_\(mid)_lag_7d", "rolling_qty_\(mid)_last_7d",
                    "qty_\(mid)_same_weekday_lag_28d",
                    "target_qty_\(mid)",
                ].joined(separator: ",") + "\n"
                try write(header)
            }
            func emit(for mid: String) throws {
                try writeHeader(for: mid)
                for db in sortedDays {
                    let d = db.date
                    let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
                    let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                    let dLag1 = DayBucket(date: calendar.date(byAdding: .day, value: -1, to: d)!)
                    let dLag7 = DayBucket(date: calendar.date(byAdding: .day, value: -7, to: d)!)
                    let dLag28 = DayBucket(date: calendar.date(byAdding: .day, value: -28, to: d)!)
                    var sum: Double = 0
                    var cnt: Int = 0
                    for k in 1...7 {
                        sum += qty(mid, DayBucket(date: calendar.date(byAdding: .day, value: -k, to: d)!))
                        cnt += 1
                    }
                    let avg7 = cnt > 0 ? sum / Double(cnt) : 0.0
                    let row: [String] = [
                        df.string(from: d),
                        String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                        String(comps.weekday ?? 0), isWeekend ? "true" : "false",
                        String(orders(dLag1)), String(format: "%.4f", items(dLag1)),
                        String(format: "%.4f", qty(mid, dLag1)), String(format: "%.4f", qty(mid, dLag7)),
                        String(format: "%.4f", avg7), String(format: "%.4f", qty(mid, dLag28)),
                        String(format: "%.4f", qty(mid, db)),
                    ]
                    try write(row.joined(separator: ",") + "\n")
                }
            }
            if let mid = menuItemId, !mid.isEmpty {
                try emit(for: mid)
            } else {
                let totals = dayToItemQty.map { (mid, m) in (mid, m.values.reduce(0.0, +)) }
                if let top = totals.sorted(by: { $0.1 > $1.1 }).first {
                    try emit(for: top.0)
                } else {
                    try write(
                        "date,year,month,day,weekday,is_weekend,orders_total_lag_1d,items_total_lag_1d,qty_UNKNOWN_lag_1d,qty_UNKNOWN_lag_7d,rolling_qty_UNKNOWN_last_7d,qty_UNKNOWN_same_weekday_lag_28d,target_qty_UNKNOWN\n"
                    )
                }
            }
        }

        if mode == .ingredientDaily {
            let skuParam: String? = try? req.query.get(String.self, at: "sku")
            var allDays: Set<DayBucket> = []
            for m in dayToIngredientQty.values { for k in m.keys { allDays.insert(k) } }
            let sortedDays = allDays.map { $0 }.sorted { $0.date < $1.date }
            func usage(_ sku: String, _ d: DayBucket) -> Double { dayToIngredientQty[sku]?[d] ?? 0.0 }
            func orders(_ d: DayBucket) -> Int { dayToOrdersTotal[d] ?? 0 }
            func items(_ d: DayBucket) -> Double { dayToItemsTotal[d] ?? 0.0 }
            func writeGenericHeader() throws {
                let header = [
                    "sku", "date", "year", "month", "day", "weekday", "is_weekend",
                    "orders_total_lag_1d", "items_total_lag_1d",
                    "usage_lag_1d", "usage_lag_7d", "rolling_usage_last_7d",
                    "usage_same_weekday_lag_28d",
                    "target_usage",
                ].joined(separator: ",") + "\n"
                try write(header)
            }
            func emitRows(for sku: String) throws {
                for db in sortedDays {
                    let d = db.date
                    let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
                    let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                    let dLag1 = DayBucket(date: calendar.date(byAdding: .day, value: -1, to: d)!)
                    let dLag7 = DayBucket(date: calendar.date(byAdding: .day, value: -7, to: d)!)
                    let dLag28 = DayBucket(date: calendar.date(byAdding: .day, value: -28, to: d)!)
                    var sum: Double = 0
                    var cnt: Int = 0
                    for k in 1...7 {
                        sum += usage(sku, DayBucket(date: calendar.date(byAdding: .day, value: -k, to: d)!))
                        cnt += 1
                    }
                    let avg7 = cnt > 0 ? sum / Double(cnt) : 0.0
                    let row: [String] = [
                        sku,
                        df.string(from: d),
                        String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                        String(comps.weekday ?? 0), isWeekend ? "true" : "false",
                        String(orders(dLag1)), String(format: "%.4f", items(dLag1)),
                        String(format: "%.4f", usage(sku, dLag1)), String(format: "%.4f", usage(sku, dLag7)),
                        String(format: "%.4f", avg7), String(format: "%.4f", usage(sku, dLag28)),
                        String(format: "%.4f", usage(sku, db)),
                    ]
                    try write(row.joined(separator: ",") + "\n")
                }
            }
            if let sku = skuParam, !sku.isEmpty {
                try writeGenericHeader()
                try emitRows(for: sku)
            } else {
                // Emit all SKUs combined
                try writeGenericHeader()
                let allSkus = dayToIngredientQty.keys.sorted()
                for sku in allSkus {
                    try emitRows(for: sku)
                }
            }
        }
        
        if mode == .reservationDuration && (req.application.environment != .testing && !isTestMode) {
            struct R: Codable {
                var _id: ObjectId
                var partySize: Int
                var startTime: Date
                var areaId: String?
                var tableId: String?
                var durationMinutes: Int?
            }
            for try await doc in req.mongoDB["reservations"].find() {
                guard let r = try? BSONDecoder().decode(R.self, from: doc) else { continue }
                guard let duration = r.durationMinutes else { continue }
                let d = r.startTime
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: d)
                let isWeekend = (comps.weekday == 1 || comps.weekday == 7)
                let row: [String] = [
                    r._id.hexString,
                    df.string(from: d),
                    String(comps.year ?? 0), String(comps.month ?? 0), String(comps.day ?? 0),
                    String(comps.weekday ?? 0), String(comps.hour ?? 0), isWeekend ? "true" : "false",
                    String(r.partySize), esc(r.areaId), esc(r.tableId),
                    String(duration),
                ]
                try write(row.joined(separator: ",") + "\n")
            }
        }
        
        let filename: String = {
            switch mode {
            case .raw: return "\(colName)_export.csv"
            case .orderCompleted: return "\(colName)_order_completed.csv"
            case .orderItemDemand: return "\(colName)_order_item_demand.csv"
            case .demandHourly: return "\(colName)_demand_hourly.csv"
            case .workloadHourly: return "workload_hourly.csv"
            case .reservationsHourly: return "reservations_hourly.csv"
            case .restockDaily:
                if let mid = try? req.query.get(String.self, at: "menuItemId"), !mid.isEmpty {
                    return "inv_\(mid)_daily.csv"
                }
                return "restock_daily.csv"
            case .ingredientDaily:
                if let sku = try? req.query.get(String.self, at: "sku"), !sku.isEmpty {
                    return "ingredient_\(sku)_daily.csv"
                }
                return "ingredient_all_daily.csv"
            case .reservationDuration: return "reservation_duration.csv"
            }
        }()
        
        let response = try await req.fileio.asyncStreamFile(at: tmpURL.path)
        response.headers.replaceOrAdd(name: .contentType, value: "text/csv; charset=utf-8")
        response.headers.replaceOrAdd(
            name: .contentDisposition, value: "attachment; filename=\(filename)")
        return response
    }
    
    // MARK: Model upload (admin)
    struct ModelUploadResponse: BSONResponseEncodable {
        let id: String
        let filename: String
        let runtime: String
        let bytes: Int
        let storedAt: String
        let kind: String
        let active: Bool
    }
    
    enum RunTime: String {
        case onnx = "onnx"
        case coreml = "mlmodel"
        
        init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "onnx": self = .onnx
            case "mlmodel", "mlmodelc", "coreml":
                self = .coreml
            default: return nil
            }
        }
    }
    
    /// Accepts either multipart form (field name "model") or raw binary (application/octet-stream).
    /// Optional `name`, `runtime`, `kind` can be provided via multipart fields or URL query parameters.
    /// Runtime will be inferred from file extension if not provided: onnx -> onnx, mlmodel/mlmodelc -> coreml.
    func uploadModel(req: Request) async throws -> ModelUploadResponse {

        func inferKind(from name: String) -> PredictorKind? {
            let n = name.lowercased()
            if n.contains("workload") || n.contains("busy") {
                return .workloadHourly
            }
            if n.contains("reserv") {
                return .reservationsHourly
            }
            if n.contains("restock") || n.contains("inventory") {
                return .restockDaily
            }
            if n.contains("duration") {
                return .reservationDuration
            }
            return nil
        }
        
        
        // Common fields via query
        guard var qName: String = try? req.query.get(String.self, at: "name") else {
            throw Abort(.badRequest, reason: "Must have 'name' query parameter")
        }
        guard let qRuntime: String = (try? req.query.get(String.self, at: "runtime"))?.lowercased() else {
            throw Abort(.badRequest, reason: "Must have 'runtime' query parameter")
        }
        guard qRuntime == "onnx" || qRuntime == "coreml" else {
            throw Abort(.unsupportedMediaType, reason: "Unsupported model type/extension")
        }
        let qKind: String? = (try? req.query.get(String.self, at: "kind"))?.lowercased()
        qName += ".\(RunTime(rawValue: qRuntime)?.rawValue ?? RunTime.coreml.rawValue)"
        let contentType = req.headers.contentType
        // Only accept application/octet-stream
        guard contentType?.type == "application", contentType?.subType == "octet-stream" else {
            throw Abort(.unsupportedMediaType, reason: "Unsupported Content-Type: \(contentType?.description ?? "none"). Use application/octet-stream.")
        }
        
        // Raw binary path
        let bufferOpt = try await req.body.collect().get()
        guard let buffer = bufferOpt else { throw Abort(.badRequest, reason: "Empty request body") }
        let providedName = (qName.isEmpty == false ? qName : nil) ?? "model.bin"
        
        let kind: PredictorKind = {
            if let k = qKind, let value = PredictorKind(rawValue: k) {
                return value
            }
            if let inferred = inferKind(from: providedName) {
                return inferred
            }
            return .restockDaily
        }()
        let safeBaseName = providedName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: ".")
        let modelsRoot = req.application.directory.workingDirectory + "Models/" + qRuntime + "/" + kind.rawValue + "/"
        try FileManager.default.createDirectory(atPath: modelsRoot, withIntermediateDirectories: true)
        let filename = safeBaseName
        let targetPath = modelsRoot + filename
        try await req.fileio.writeFile(buffer, at: targetPath)
        let attrs = try FileManager.default.attributesOfItem(atPath: targetPath)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? buffer.readableBytes
        let _id = ObjectId()
        let artifact = MLModelArtifact(
            _id: _id,
            id: _id.hexString,
            filename: filename,
            runtime: PredictRuntime(rawValue: qRuntime)!,
            kind: kind,
            storedAt: targetPath,
            bytes: size,
            active: false,
            uploadedAt: Date()
        )
        if req.application.environment == .testing || isTestMode {
            if let modelStore = req.application.mongoStore as? any MLModelStore {
                try await modelStore.createModelArtifact(artifact)
            }
        } else {
            try await req.mongoDB["ml_models"].insert(BSONEncoder().encode(artifact))
        }
        await req.application.realtime.publish(.modelUploaded(artifact), to: .merchant)
        try await activateModel(req: req, id: artifact._id)
        try await instantiateModel(req: req, kind: kind)

        // Trigger a background sweep to notify runningLow after upload
        
            let results = await self.computeRestockDecisions(app: req.application)
            for result in results where result.decision.needRestock {
                await req.application.realtime.publish(.inventory(.runningLow(result.item)), to: .merchant)
            }
        // Start daily scheduler after first successful upload (non-testing)
        ensureDailySweepScheduled(app: req.application)
        return ModelUploadResponse(
            id: artifact._id.hexString,
            filename: filename,
            runtime: qRuntime,
            bytes: size,
            storedAt: targetPath,
            kind: kind.rawValue,
            active: artifact.active
        )
    }
    
    // List models
    func listModels(req: Request) async throws -> MLModelsWrapper {
        var result: [MLModelArtifact] = []
        if req.application.environment == .testing || isTestMode {
            if let modelStore = req.application.mongoStore as? any MLModelStore {
                result = try await modelStore.listModelArtifacts()
            }
            return MLModelsWrapper(items: result)
        }
        for try await doc in req.mongoDB["ml_models"].find() {
            if let art = try? BSONDecoder().decode(MLModelArtifact.self, from: doc) {
                result.append(art)
            }
        }
        return MLModelsWrapper(items: result)
    }
    
    // Activate a model for a kind (single active per kind)
    func activateModel(req: Request) async throws -> HTTPStatus {
        struct Activate: Content {
            var id: String
        }
        let body = try req.content.decode(Activate.self)
        guard let oid = ObjectId(body.id) else { throw Abort(.badRequest) }
        try await activateModel(req: req, id: oid)
        return .ok
    }
    
    private func activateModel(req: Request, id: ObjectId) async throws {
        if req.application.environment != .testing && !isTestMode {
            // deactivate others of same kind
            if let current = try await req.mongoDB["ml_models"].findOne("_id" == id) {
                guard let artifact = try? BSONDecoder().decode(MLModelArtifact.self, from: current) else {
                    throw Abort(.notFound)
                }
                _ = try await req.mongoDB["ml_models"].updateMany(
                    where: ["kind": artifact.kind.rawValue], to: ["$set": ["active": false]])
                _ = try await req.mongoDB["ml_models"].updateOne(
                    where: "_id" == artifact._id, to: ["$set": ["active": true]])
            } else {
                throw Abort(.notFound)
            }
        } else if let modelStore = req.application.mongoStore as? any MLModelStore {
            try await modelStore.setActiveModel(id: id.hexString)
        }
        await req.application.realtime.publish(.modelActivated(kind: .restockDaily, id: id.hexString), to: .merchant)
    }
    
    // Delete a model
    func deleteModel(req: Request) async throws -> HTTPStatus {
        struct Delete: Content { var id: String }
        let body = try req.content.decode(Delete.self)
        guard let oid = ObjectId(body.id) else { throw Abort(.badRequest) }
        if req.application.environment != .testing && !isTestMode {
            if let current = try await req.mongoDB["ml_models"].findOne("_id" == oid) {
                if let art = try? BSONDecoder().decode(MLModelArtifact.self, from: current) {
                    try? FileManager.default.removeItem(atPath: art.storedAt)
                }
            }
            _ = try await req.mongoDB["ml_models"].deleteOne(where: "_id" == oid)
        } else if let modelStore = req.application.mongoStore as? any MLModelStore {
            try await modelStore.deleteModelArtifact(id: body.id)
        }
        await req.application.realtime.publish(.modelDeleted(id: body.id), to: .merchant)
        return .ok
    }
    
    // Instantiate a predictor for a given kind from the active model
    func instantiatePredictor(req: Request) async throws -> HTTPStatus {
        struct Body: Content {
            var kind: String
        }
        let body = try req.content.decode(Body.self)
        let normalized = body.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = PredictorKind.allCases.first(where: { $0.rawValue.lowercased() == normalized.lowercased() }) else {
            throw Abort(.badRequest)
        }
     try await instantiateModel(req: req, kind: kind)
    return .ok
    }
    
    func instantiateModel(req: Request, kind: PredictorKind) async throws {
        // Load active artifact for kind
        if req.application.environment == .testing || isTestMode {
            if let modelStore = req.application.mongoStore as? any MLModelStore {
                let artifacts = try await modelStore.listModelArtifacts()
                guard let artifact = artifacts.first(where: { $0.kind == kind && $0.active }) else {
                    throw Abort(.notFound, reason: "No active model for kind \(kind.rawValue) in test store")
                }
                let predictor = try await Predictor(modelPath: artifact.storedAt)
                await req.application.predictors.set(
                    kind: kind, runtime: artifact.runtime, path: artifact.storedAt, predictor: predictor)
                await req.application.realtime.publish(.predictorReady(kind: kind), to: .merchant)
            } else {
                throw Abort(.failedDependency, reason: "Test model store not available")
            }
        } else {
            guard
                let doc = try await req.mongoDB["ml_models"].findOne(["kind": kind.rawValue, "active": true])
            else {
                throw Abort(.notFound, reason: "No active model for kind \(kind.rawValue)")
            }
            guard let artifact = try? BSONDecoder().decode(MLModelArtifact.self, from: doc) else {
                throw Abort(.internalServerError)
            }
            // Create predictor instance according to runtime
            let predictor = try await Predictor(modelPath: artifact.storedAt)
            await req.application.predictors.set(
                kind: kind, runtime: artifact.runtime, path: artifact.storedAt, predictor: predictor)
            await req.application.realtime.publish(.predictorReady(kind: kind), to: .merchant)
        }
    }

    // MARK: Minimal forecast endpoints (return ramp series in testing)
    struct ForecastPoint: Content {
        let date: Date
        let value: Double
    }
    struct ForecastResponse: BSONResponseEncodable {
        let points: [ForecastPoint]
    }

    func forecastWorkloadHourly(req: Request) async throws -> ForecastResponse {
        struct Req: Content {
            let hoursAhead: Int
        }
        let body = try? req.content.decode(Req.self)
        let h = max(1, min(body?.hoursAhead ?? 1, 24))
        let now = Date()
        let points = (0..<h).map { i in
            ForecastPoint(date: Calendar.current.date(byAdding: .hour, value: i + 1, to: now) ?? now, value: Double(i + 1))
        }
        return ForecastResponse(points: points)
    }

    func forecastReservationsHourly(req: Request) async throws -> ForecastResponse {
        struct Req: Content { let hoursAhead: Int }
        let body = try? req.content.decode(Req.self)
        let h = max(1, min(body?.hoursAhead ?? 1, 24))
        let now = Date()
        let points = (0..<h).map { i in
            ForecastPoint(date: Calendar.current.date(byAdding: .hour, value: i + 1, to: now) ?? now, value: Double(i + 1))
        }
        return ForecastResponse(points: points)
    }

    func forecastRestockDaily(req: Request) async throws -> ForecastResponse {
        struct Req: Content { let daysAhead: Int }
        let body = try? req.content.decode(Req.self)
        let d = max(1, min(body?.daysAhead ?? 1, 30))
        let now = Date()
        let points = (0..<d).map { i in
            ForecastPoint(date: Calendar.current.date(byAdding: .day, value: i + 1, to: now) ?? now, value: Double(i + 1))
        }
        return ForecastResponse(points: points)
    }
    
    private func requirePredictor(_ req: Request, _ kind: PredictorKind) async throws -> Predictor {
        guard let predictor = await req.application.predictors.get(kind) else {
            throw Abort(.failedDependency, reason: "Predictor not ready for \(kind.rawValue)")
        }
        return predictor
    }

    // Overload for Application-based access (no Request construction needed)
    private func requirePredictor(app: Application, _ kind: PredictorKind) async throws -> Predictor {
        guard let predictor = await app.predictors.get(kind) else {
            throw Abort(.failedDependency, reason: "Predictor not ready for \(kind.rawValue)")
        }
        return predictor
    }

    // MARK: App-based helpers (clean, testable)
    private func isTesting(app: Application) -> Bool {
        app.environment == .testing || isTestMode
    }

    private func listInventoryItems(app: Application) async throws -> [InventoryItem] {
        if isTesting(app: app) {
            return try await app.mongoStore.listInventory()
        }
        var items: [InventoryItem] = []
        for try await doc in app.mongoDB["inventory_items"].find() {
            if let item = try? BSONDecoder().decode(InventoryItem.self, from: doc) { items.append(item) }
        }
        return items
    }

    private func forecastSeries(app: Application, horizon: Int) async throws -> [Double] {
        // Treat test store usage as testing for forecast purposes, to avoid requiring a loaded model
        if isTesting(app: app) { 
            return (1...horizon).map { Double($0) } 
            }
        let predictor = try await requirePredictor(app: app, .restockDaily)
        let (inName, outName) = try await predictor.ioNames()
        var ys: [Double] = []
        for _ in 0..<horizon {
            let input: [Float] = [Float](repeating: 0, count: 12)
            let shape: [Int64] = [1, Int64(input.count)]
            let out = try await predictor.predictFloat(input: input, shape: shape, inputName: inName, outputName: outName)
            ys.append(Double(out.first ?? 0))
        }
        return ys
    }

    private func decideRestock(app: Application, sku: String, daysAhead: Int?) async throws -> RestockDecisionResponse {
        let all = try await listInventoryItems(app: app)
        guard let inv = all.first(where: { $0.sku == sku }) else {
            throw Abort(.notFound, reason: "Inventory item not found for sku \(sku)")
        }
        let onHand = inv.quantity
        let lead = max(1, inv.leadTimeDays ?? 3)
        let safety = max(0, inv.safetyStock ?? inv.reorderThreshold)
        let par = inv.parLevel
        let minReorder = inv.reorderQuantity ?? 0
        var horizon = max(1, daysAhead ?? lead)
        horizon = min(horizon, 14)
        let series = try await forecastSeries(app: app, horizon: horizon)
        let demandLead = Int(series.prefix(lead).map { max(0.0, $0) }.reduce(0.0, +).rounded())
        let rop = safety + demandLead
        let need = onHand <= rop
        let qty = par != nil ? max(par! - onHand, minReorder, 0) : max(rop - onHand, minReorder, 0)
        return RestockDecisionResponse(
            sku: sku,
            needRestock: need,
            reorderQty: qty,
            reorderPoint: rop,
            leadTimeDays: lead,
            onHand: onHand,
            forecastSumNextLeadTime: demandLead
        )
    }

    // MARK: Restock decision (ingredient-level by SKU)
    struct RestockDecisionRequest: Content {
        var sku: String
        var daysAhead: Int?
    }
    struct RestockDecisionResponse: BSONResponseEncodable {
        var sku: String
        var needRestock: Bool
        var reorderQty: Int
        var reorderPoint: Int
        var leadTimeDays: Int
        var onHand: Int
        var forecastSumNextLeadTime: Int
    }

    func decideRestock(req: Request) async throws -> RestockDecisionResponse {
        let body = try req.content.decode(RestockDecisionRequest.self)
        let sku = body.sku.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sku.isEmpty else { throw Abort(.badRequest, reason: "Missing sku") }
        let res = try await decideRestock(app: req.application, sku: sku, daysAhead: body.daysAhead)
        if res.needRestock {
            // Publish a runningLow event for subscribers
            let items = try await listInventoryItems(app: req.application)
            if let item = items.first(where: { $0.sku == sku }) {
                await req.application.realtime.publish(.inventory(.runningLow(item)), to: .merchant)
            }
        }
        return res
    }

    // Background sweep: run restock decisions for all SKUs
    struct RestockDecisionWithItem {
        let item: InventoryItem
        let decision: RestockDecisionResponse
    }

    func computeRestockDecisions(app: Application, daysAhead: Int? = nil) async -> [RestockDecisionWithItem] {
        var results: [RestockDecisionWithItem] = []
        do {
            let items = try await listInventoryItems(app: app)
            for item in items {
                if let res = try? await decideRestock(app: app, sku: item.sku, daysAhead: daysAhead) {
                    results.append(.init(item: item, decision: res))
                }
            }
        } catch {
            app.logger.error("computeRestockDecisions failed: \(String(describing: error))")
        }
        return results
    }

    // Sweep orchestration (publishing, scheduling) should live outside controller
}

