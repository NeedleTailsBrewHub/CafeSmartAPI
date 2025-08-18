@preconcurrency import BSON
import Foundation
import Metrics
import MongoKitten
import Vapor

final class CafeSwiftMetricsFactory: MetricsFactory, @unchecked Sendable {
    
    actor FlushController: Sendable {
        
        let buffer: CafeMetricsBuffer
        let interval: TimeInterval
        private var isRunning = false
        private var task: Task<Void, Never>? = nil
        
        init(
            buffer: CafeMetricsBuffer,
            interval: TimeInterval
        ) {
            self.buffer = buffer
            self.interval = interval
        }
        
        func start() {
            guard !isRunning else { return }
            isRunning = true
            task = Task { [interval, buffer] in
                while !Task.isCancelled {
                    let ns = UInt64(max(interval, 0.25) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                    await buffer.flush()
                }
            }
        }
        
        func stop() async {
            task?.cancel()
            task = nil
            isRunning = false
            await buffer.flush()
        }
        
    }
    
    final class Lifecycle: LifecycleHandler, @unchecked Sendable {
        
        let controller: FlushController
        
        init(
            buffer: CafeMetricsBuffer,
            interval: TimeInterval
        ) {
            self.controller = FlushController(buffer: buffer, interval: interval)
        }
        
        func didBoot(_ application: Application) throws {
            Task { [weak self] in
                guard let self else { return }
                await self.controller.start()
            }
        }
        
        func shutdown(_ application: Application) {
            Task { [weak self] in
                guard let self else { return }
                await self.controller.stop()
            }
        }
    }
    
    
    private let writer: any CafeEventWriter
    
    init(writer: any CafeEventWriter) {
        self.writer = writer
    }
    
    func makeCounter(
        label: String,
        dimensions: [(String, String)]
    ) -> any CounterHandler {
        CounterImpl(
            label: label,
            dimensions: dimensions,
            writer: writer)
    }
    
    func makeFloatingPointCounter(
        label: String,
        dimensions: [(String, String)]
    ) -> any FloatingPointCounterHandler {
        FPCounterImpl(
            label: label,
            dimensions: dimensions,
            writer: writer)
    }
    
    func makeRecorder(
        label: String,
        dimensions: [(String, String)],
        aggregate: Bool
    ) -> any RecorderHandler {
        RecorderImpl(
            label: label,
            dimensions: dimensions,
            writer: writer)
    }
    
    func makeTimer(
        label: String,
        dimensions: [(String, String)]
    ) -> any TimerHandler {
        TimerImpl(
            label: label,
            dimensions: dimensions,
            writer: writer)
    }
    
    func destroyCounter(_ handler: any CounterHandler) {}
    func destroyFloatingPointCounter(_ handler: any FloatingPointCounterHandler) {}
    func destroyRecorder(_ handler: any RecorderHandler) {}
    func destroyTimer(_ handler: any TimerHandler) {}
}

private func dimsDict(_ dims: [(String, String)]) -> [String: String] {
    var dictionary: [String: String] = [:]
    for (key, value) in dims {
        dictionary[key] = value
    }
    return dictionary
}

private func parseDouble(_ s: String?) -> Double? {
    s.flatMap(Double.init)
}
private func parseInt(_ s: String?) -> Int? {
    s.flatMap(Int.init)
}

// MARK: - Handlers

private final class CounterImpl: CounterHandler, @unchecked Sendable {
    
    let label: String
    let dimensions: [(String, String)]
    let writer: any CafeEventWriter
    
    init(
        label: String,
        dimensions: [(String, String)],
        writer: any CafeEventWriter
    ) {
        self.label = label
        self.dimensions = dimensions
        self.writer = writer
    }
    
    func increment(by amount: Int64) {
        let dictionary = dimsDict(dimensions)
        var event: CafeEvent?
        switch label {
        case "cafe.orders.created":
            event = CafeEvent(type: .orderCreated)
            event?.orderId = dictionary["orderId"]
            event?.channel = dictionary["channel"]
            event?.serviceType = dictionary["serviceType"]
        case "cafe.orders.completed":
            event = CafeEvent(type: .orderCompleted)
            event?.orderId = dictionary["orderId"]
            event?.channel = dictionary["channel"]
            event?.serviceType = dictionary["serviceType"]
        case "cafe.orders.canceled":
            event = CafeEvent(type: .orderCanceled)
            event?.orderId = dictionary["orderId"]
            event?.channel = dictionary["channel"]
            event?.serviceType = dictionary["serviceType"]
        case "cafe.orders.item_demand":
            event = CafeEvent(type: .orderItemDemand)
            event?.orderId = dictionary["orderId"]
            event?.menuItemId = dictionary["menuItemId"]
            event?.channel = dictionary["channel"]
            event?.serviceType = dictionary["serviceType"]
            event?.quantity = Double(amount)
        case "cafe.inventory.low":
            event = CafeEvent(type: .inventoryLow)
            event?.inventoryItemId = dictionary["inventoryItemId"]
            event?.sku = dictionary["sku"]
            event?.level = parseDouble(dictionary["level"]) ?? Double(amount)
            event?.threshold = parseDouble(dictionary["threshold"]) ?? nil
        case "cafe.reservations.created":
            event = CafeEvent(type: .reservationCreated)
            event?.reservationId = dictionary["reservationId"]
            event?.partySize = parseInt(dictionary["partySize"]) ?? nil
            event?.areaId = dictionary["areaId"]
            event?.tableId = dictionary["tableId"]
        default: break
        }
        if let event {
            Task { [weak self] in
                guard let self else { return }
                await self.writer.append(event)
            }
        }
    }
    func reset() {}
}

private final class FPCounterImpl: FloatingPointCounterHandler, @unchecked Sendable {
    let label: String; let dimensions: [(String, String)]; let writer: any CafeEventWriter
    init(label: String, dimensions: [(String, String)], writer: any CafeEventWriter) { self.label = label; self.dimensions = dimensions; self.writer = writer }
    func increment(by amount: Double) {
        let dictionary = dimsDict(dimensions)
        var event: CafeEvent?
        switch label {
        case "cafe.orders.item_demand":
            event = CafeEvent(type: .orderItemDemand)
            event?.orderId = dictionary["orderId"]
            event?.menuItemId = dictionary["menuItemId"]
            event?.channel = dictionary["channel"]
            event?.serviceType = dictionary["serviceType"]
            event?.quantity = amount
        default: break
        }
        if let event {
            Task { [weak self] in
                guard let self else { return }
                await self.writer.append(event)
            }
        }
    }
    func reset() {}
}

private final class RecorderImpl: RecorderHandler, @unchecked Sendable {
    
    let label: String
    let dimensions: [(String, String)]
    let writer: any CafeEventWriter
    
    init(
        label: String,
        dimensions: [(String, String)],
        writer: any CafeEventWriter
    ) {
        self.label = label
        self.dimensions = dimensions
        self.writer = writer
    }
    
    func record(_ value: Int64) {
        record(Double(value))
    }
    
    func record(_ value: Double) {
        let dictionary = dimsDict(dimensions)
        var event: CafeEvent?
        switch label {
        case "cafe.menu.price_cents":
            event = CafeEvent(type: .menuItemUpdated)
            event?.menuItemId = dictionary["menuItemId"]
            event?.priceCents = Int(value)
        case "cafe.inventory.level":
            event = CafeEvent(type: .inventoryLevel)
            event?.inventoryItemId = dictionary["inventoryItemId"]
            event?.sku = dictionary["sku"]
            event?.threshold = parseDouble(dictionary["threshold"]) ?? nil
            event?.level = value
        case "cafe.menu.available":
            event = CafeEvent(type: .menuItemAvailability)
            event?.menuItemId = dictionary["menuItemId"]
            event?.available = value >= 0.5
        default: break
        }
        if let event {
            Task { [weak self] in
                guard let self else { return }
                await self.writer.append(event)
            }
        }
    }
    func reset() {}
}

private final class TimerImpl: TimerHandler, @unchecked Sendable {
    
    let label: String; let dimensions: [(String, String)]
    let writer: any CafeEventWriter
    
    init(
        label: String,
        dimensions: [(String, String)],
        writer: any CafeEventWriter
    ) {
        self.label = label
        self.dimensions = dimensions
        self.writer = writer
    }
    
    func recordNanoseconds(_ duration: Int64) {
        let dictionary = dimsDict(dimensions)
        var event: CafeEvent?
        switch label {
        case "cafe.orders.cycle_seconds":
            event = CafeEvent(type: .orderCompleted)
            event?.orderId = dictionary["orderId"]
            event?.channel = dictionary["channel"]
            event?.serviceType = dictionary["serviceType"]
            event?.secondsToComplete = Double(duration) / 1_000_000_000.0
        default: break
        }
        if let event {
            Task { [weak self] in
                guard let self else { return }
                await self.writer.append(event)
            }
        }
    }
}

// MARK: - Writer Protocol & Implementations

protocol CafeEventWriter: Sendable {
    func append(_ event: CafeEvent) async
    func flush() async
    func shutdown() async
}

actor CafeMetricsBuffer: CafeEventWriter {
    private let db: MongoDatabase
    private let collectionName: String
    private let flushIntervalSeconds: TimeInterval
    private let maxBatchSize: Int
    
    private var buffer: [Document] = []
    private var lastFlush: Date = Date()
    private var isFlushing: Bool = false
    private var isShutdown: Bool = false
    
    init(database: MongoDatabase, collectionName: String, flushIntervalSeconds: TimeInterval, maxBatchSize: Int) {
        self.db = database
        self.collectionName = collectionName
        self.flushIntervalSeconds = flushIntervalSeconds
        self.maxBatchSize = maxBatchSize
    }
    
    func append(_ event: CafeEvent) async {
        guard !isShutdown else { return }
        buffer.append(event.toDocument())
        let now = Date()
        if buffer.count >= maxBatchSize || now.timeIntervalSince(lastFlush) >= flushIntervalSeconds {
            await flush()
        }
    }
    
    func flush() async {
        guard !isFlushing, !buffer.isEmpty else { return }
        isFlushing = true
        let docs = buffer
        buffer.removeAll(keepingCapacity: true)
        do {
            if !docs.isEmpty {
                // Respect Mongo's ~10MB per write limit by chunking inserts by size and count
                let maxBytes = Int(Environment.get("CAFE_METRICS_MAX_WRITE_BYTES") ?? "10000000") ?? 10_000_000
                let maxCount = max(1, Int(Environment.get("CAFE_METRICS_MAX_WRITE_COUNT") ?? "1000") ?? 1000)
                var current: [Document] = []
                var currentBytes = 0
                var chunks: [[Document]] = []
                func pushCurrent() {
                    if !current.isEmpty { chunks.append(current); current = []; currentBytes = 0 }
                }
                for doc in docs {
                    let size = doc.makeData().count
                    if !current.isEmpty && (currentBytes + size > maxBytes || current.count >= maxCount) {
                        pushCurrent()
                    }
                    current.append(doc)
                    currentBytes += size
                }
                pushCurrent()
                for batch in chunks {
                    if !batch.isEmpty { _ = try await db[collectionName].insertMany(batch) }
                }
            }
            lastFlush = Date()
        } catch {
            buffer.insert(contentsOf: docs, at: 0)
        }
        isFlushing = false
    }
    
    func shutdown() async { isShutdown = true; await flush() }
}

// MARK: - Swift Metrics Factory

// In-memory writer for testing environment
actor CafeEventTestWriter: CafeEventWriter {
    private(set) var events: [CafeEvent] = []
    func append(_ event: CafeEvent) async { events.append(event) }
    func flush() async {}
    func shutdown() async { events.removeAll() }
    func snapshot() -> [CafeEvent] { events }
}

// MARK: - Event Schema

enum CafeEventType: String, Codable, Sendable {
    case orderCreated
    case orderCompleted
    case orderCanceled
    case orderItemDemand
    case inventoryLevel
    case inventoryLow
    case reservationCreated
    case menuItemUpdated
    case menuItemAvailability
}

struct CafeEvent: Codable, Sendable {
    var id: String = ObjectId().hexString
    let type: CafeEventType
    let ts: Date
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let weekday: Int
    
    // Optional domain fields
    var orderId: String? = nil
    var channel: String? = nil
    var serviceType: String? = nil
    var secondsToComplete: Double? = nil
    
    var menuItemId: String? = nil
    var quantity: Double? = nil
    
    var inventoryItemId: String? = nil
    var sku: String? = nil
    var level: Double? = nil
    var threshold: Double? = nil
    
    var reservationId: String? = nil
    var partySize: Int? = nil
    var areaId: String? = nil
    var tableId: String? = nil
    
    var priceCents: Int? = nil
    var available: Bool? = nil
    
    init(type: CafeEventType, ts: Date = Date()) {
        self.type = type
        self.ts = ts
        let cal = Calendar(identifier: .gregorian)
        self.year = cal.component(.year, from: ts)
        self.month = cal.component(.month, from: ts)
        self.day = cal.component(.day, from: ts)
        self.hour = cal.component(.hour, from: ts)
        self.weekday = cal.component(.weekday, from: ts)
    }
    
    private struct DB: Codable {
        var _id: ObjectId
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
    
    func toDocument(using existingId: ObjectId? = nil) -> Document {
        let oid: ObjectId
        if let existingId { oid = existingId }
        else if let parsed = ObjectId(self.id) { oid = parsed }
        else { oid = ObjectId() }
        let db = DB(
            _id: oid,
            type: type.rawValue,
            ts: ts,
            year: year,
            month: month,
            day: day,
            hour: hour,
            weekday: weekday,
            orderId: orderId,
            channel: channel,
            serviceType: serviceType,
            secondsToComplete: secondsToComplete,
            menuItemId: menuItemId,
            quantity: quantity,
            inventoryItemId: inventoryItemId,
            sku: sku,
            level: level,
            threshold: threshold,
            reservationId: reservationId,
            partySize: partySize,
            areaId: areaId,
            tableId: tableId,
            priceCents: priceCents,
            available: available
        )
        return (try? BSONEncoder().encode(db)) ?? [:]
    }
}
