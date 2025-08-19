//
//  CafeDomainMetrics.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 2025-08-19.
//

import Foundation
import Metrics
import Vapor
import MongoKitten
import NIOConcurrencyHelpers

struct CafeDomainMetrics: @unchecked Sendable {
    
    public static func initialize(app: Application) async {
        
        let useTestStoreEnv = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
        let useTestStore = app.environment == .testing
        || useTestStoreEnv == "1" || useTestStoreEnv == "true" || useTestStoreEnv == "yes"
        if useTestStore {
            
            let testWriter = CafeEventTestWriter()
            let factory = CafeSwiftMetricsFactory(writer: testWriter)
            MetricsSystem.bootstrap(factory)
            
        } else {
            
            let collection = Environment.get("CAFE_METRICS_COLLECTION") ?? "cafe_metrics"
            // Default periodic flush every 12 hours to minimize write costs
            let flushInterval = TimeInterval(Double(Environment.get("CAFE_METRICS_FLUSH_SECONDS") ?? "43200") ?? 43200)
            let batchSize = Int(Environment.get("CAFE_METRICS_MAX_BATCH") ?? "512") ?? 512
            
            let buffer = CafeMetricsBuffer(database: app.mongoDB, collectionName: collection, flushIntervalSeconds: flushInterval, maxBatchSize: batchSize)
            let factory = CafeSwiftMetricsFactory(writer: buffer)
            MetricsSystem.bootstrap(factory)
            app.logger.info("CafeSwiftMetricsFactory bootstrapped: collection=\(collection), flush=\(flushInterval)s, batch=\(batchSize)")
            app.lifecycle.use(CafeSwiftMetricsFactory.Lifecycle(buffer: buffer, interval: flushInterval))
        }
    }
    
    private enum Label {
        static let ordersCreated = "cafe.orders.created"
        static let ordersCompleted = "cafe.orders.completed"
        static let ordersCanceled = "cafe.orders.canceled"
        static let ordersItemDemand = "cafe.orders.item_demand"
        static let ordersCycleSeconds = "cafe.orders.cycle_seconds"
        static let inventoryLevel = "cafe.inventory.level"
        static let inventoryLow = "cafe.inventory.low"
        static let menuPriceCents = "cafe.menu.price_cents"
        static let menuAvailable = "cafe.menu.available"
        static let reservationsCreated = "cafe.reservations.created"
    }
    
    private static func dims(_ pairs: [(String, String?)]) -> [(String, String)] {
        pairs.map { ($0.0, $0.1 ?? "") }
    }
    
    // MARK: Orders
    static func recordOrderCreated(orderId: String, channel: String?, serviceType: String?) {
        Counter(label: Label.ordersCreated, dimensions: dims([
            ("orderId", orderId), ("channel", channel), ("serviceType", serviceType)
        ])).increment(by: 1)
    }
    
    static func recordOrderItemDemand(orderId: String, menuItemId: String, channel: String?, serviceType: String?, quantity: Double) {
        FloatingPointCounter(label: Label.ordersItemDemand, dimensions: dims([
            ("orderId", orderId), ("menuItemId", menuItemId), ("channel", channel), ("serviceType", serviceType)
        ])).increment(by: quantity)
    }
    
    static func recordOrderCompleted(orderId: String, channel: String?, serviceType: String?, seconds: Double) {
        Counter(label: Label.ordersCompleted, dimensions: dims([
            ("orderId", orderId), ("channel", channel), ("serviceType", serviceType)
        ])).increment(by: 1)
        Timer(label: Label.ordersCycleSeconds, dimensions: dims([
            ("orderId", orderId), ("channel", channel), ("serviceType", serviceType)
        ])).recordSeconds(seconds)
    }
    
    static func recordOrderCanceled(orderId: String, channel: String?, serviceType: String?) {
        Counter(label: Label.ordersCanceled, dimensions: dims([
            ("orderId", orderId), ("channel", channel), ("serviceType", serviceType)
        ])).increment(by: 1)
    }
    
    // MARK: Inventory
    static func recordInventoryLevel(itemId: String, sku: String, level: Int, threshold: Int) {
        Recorder(label: Label.inventoryLevel, dimensions: [
            ("inventoryItemId", itemId), ("sku", sku), ("threshold", String(threshold))
        ]).record(Double(level))
    }
    
    static func recordInventoryLow(itemId: String, sku: String, level: Int, threshold: Int) {
        Counter(label: Label.inventoryLow, dimensions: [
            ("inventoryItemId", itemId), ("sku", sku), ("level", String(level)), ("threshold", String(threshold))
        ]).increment(by: 1)
    }
    
    // MARK: Menu
    static func recordMenuPriceCents(menuItemId: String, priceCents: Int) {
        Recorder(label: Label.menuPriceCents, dimensions: [("menuItemId", menuItemId)])
            .record(Double(priceCents))
    }
    
    static func recordMenuAvailability(menuItemId: String, isAvailable: Bool) {
        Recorder(label: Label.menuAvailable, dimensions: [("menuItemId", menuItemId)])
            .record(isAvailable ? 1 : 0)
    }
    
    // MARK: Reservations
    static func recordReservationCreated(reservationId: String, partySize: Int, areaId: String?, tableId: String?) {
        Counter(label: Label.reservationsCreated, dimensions: dims([
            ("reservationId", reservationId), ("partySize", String(partySize)), ("areaId", areaId), ("tableId", tableId)
        ])).increment(by: 1)
    }
}
