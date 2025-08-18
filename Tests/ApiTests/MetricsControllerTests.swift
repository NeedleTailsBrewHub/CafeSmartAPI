//
//  MetricsControllerTests.swift
//  CafeSmartAPI
//
//  Mirrors the user's Testing-macros style to validate our Swift Metrics facade
//  and controllers emit expected cafe domain metrics.
//

import Testing
import Vapor
import Foundation
import Metrics
@testable import cafe_smart_api

// Test sink and factory to capture Swift Metrics emissions
private enum Captured: Sendable {
  case counter(label: String, dims: [(String, String)], value: Double)
  case recorder(label: String, dims: [(String, String)], value: Double)
  case timer(label: String, dims: [(String, String)], seconds: Double)
}

private actor Sink {
  private(set) var items: [Captured] = []
  func add(_ i: Captured) { items.append(i) }
  func reset() { items.removeAll() }
}

private final class CCounter: CounterHandler, @unchecked Sendable {
  let label: String; let dims: [(String, String)]; let sink: Sink
  init(label: String, dimensions: [(String, String)], sink: Sink) { self.label = label; self.dims = dimensions; self.sink = sink }
  func increment(by amount: Int64) { Task { await sink.add(.counter(label: label, dims: dims, value: Double(amount))) } }
  func reset() {}
}
private final class CFPCounter: FloatingPointCounterHandler, @unchecked Sendable {
  let label: String; let dims: [(String, String)]; let sink: Sink
  init(label: String, dimensions: [(String, String)], sink: Sink) { self.label = label; self.dims = dimensions; self.sink = sink }
  func increment(by amount: Double) { Task { await sink.add(.counter(label: label, dims: dims, value: amount)) } }
  func reset() {}
}
private final class CRecorder: RecorderHandler, @unchecked Sendable {
  let label: String; let dims: [(String, String)]; let sink: Sink
  init(label: String, dimensions: [(String, String)], sink: Sink) { self.label = label; self.dims = dimensions; self.sink = sink }
  func record(_ value: Int64) { Task { await sink.add(.recorder(label: label, dims: dims, value: Double(value))) } }
  func record(_ value: Double) { Task { await sink.add(.recorder(label: label, dims: dims, value: value)) } }
  func reset() {}
}
private final class CTimer: TimerHandler, @unchecked Sendable {
  let label: String; let dims: [(String, String)]; let sink: Sink
  init(label: String, dimensions: [(String, String)], sink: Sink) { self.label = label; self.dims = dimensions; self.sink = sink }
  func recordNanoseconds(_ duration: Int64) { Task { await sink.add(.timer(label: label, dims: dims, seconds: Double(duration) / 1_000_000_000.0)) } }
  func recordSeconds(_ duration: TimeInterval) { Task { await sink.add(.timer(label: label, dims: dims, seconds: duration)) } }
  func reset() {}
}

private final class CaptureFactory: MetricsFactory {
  let sink = Sink()
  func makeCounter(label: String, dimensions: [(String, String)]) -> any CounterHandler { CCounter(label: label, dimensions: dimensions, sink: sink) }
  func makeFloatingPointCounter(label: String, dimensions: [(String, String)]) -> any FloatingPointCounterHandler { CFPCounter(label: label, dimensions: dimensions, sink: sink) }
  func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> any RecorderHandler { CRecorder(label: label, dimensions: dimensions, sink: sink) }
  func makeTimer(label: String, dimensions: [(String, String)]) -> any TimerHandler { CTimer(label: label, dimensions: dimensions, sink: sink) }
  func destroyCounter(_ handler: any CounterHandler) {}
  func destroyFloatingPointCounter(_ handler: any FloatingPointCounterHandler) {}
  func destroyRecorder(_ handler: any RecorderHandler) {}
  func destroyTimer(_ handler: any TimerHandler) {}
}

// Global capture factory bootstrapped once per process to avoid duplicate bootstrap errors
fileprivate let captureFactorySingleton = CaptureFactory()
fileprivate actor _BootstrapFlag { private var v = false; func set() { v = true }; func get() -> Bool { v } }
fileprivate let _bootstrapFlag = _BootstrapFlag()

@Suite(.serialized)
actor MetricsControllerTests {
  private var app: Application!

  // Setup/Teardown
  func setUp() async throws {
    if await _bootstrapFlag.get() == false {
      MetricsSystem.bootstrap(captureFactorySingleton)
      await _bootstrapFlag.set()
    }
    app = try await Application.make(.testing)
    await captureFactorySingleton.sink.reset()
    app.mongoStore = TestableMongoStore()
  }
    func tearDown() async throws {
        try await app.asyncShutdown()
        try await Task.sleep(until: .now + .seconds(1))
    }

  // Helpers
  private func req<T: Content>(_ body: T) -> Request {
    let r = Request(application: app, on: app.eventLoopGroup.next())
    r.headers.contentType = .json
    try! r.content.encode(body)
    return r
  }

  private func containsCounter(label: String, whereDims predicate: @escaping ([(String, String)]) -> Bool) async -> Bool {
    let items = await captureFactorySingleton.sink.items
    for item in items {
      if case let .counter(l, dims, _) = item, l == label, predicate(dims) { return true }
    }
    return false
  }
  private func containsRecorder(label: String, valueEquals: Double? = nil, whereDims predicate: @escaping ([(String, String)]) -> Bool) async -> Bool {
    let items = await captureFactorySingleton.sink.items
    for item in items {
      if case let .recorder(l, dims, v) = item, l == label, predicate(dims) {
        if let ve = valueEquals { if v == ve { return true } else { continue } }
        return true
      }
    }
    return false
  }

  // Orders flow
  @Test
  func testOrderMetrics() async throws {
    try await setUp()
    let controller = OrderController()
    let create = req(OrderCreateRequest(customerName: "Jane", items: [OrderItem(menuItemId: "m1", quantity: 2, notes: nil)], pickupTime: nil))
    _ = try await controller.create(req: create)

    try await waitUntil(0.5) {
      let items1 = await captureFactorySingleton.sink.items
      return items1.contains { if case let .counter(label, _, _) = $0 { return label == "cafe.orders.created" } else { return false } }
    }
    try await waitUntil(0.5) {
      let items1 = await captureFactorySingleton.sink.items
      return items1.contains { if case let .counter(label, _, value) = $0 { return label == "cafe.orders.item_demand" && value == 2 } else { return false } }
    }

    // Complete order
    let orders = try await app.mongoStore.listOrders()
    guard let ord = orders.first else { return #expect(Bool(false), "order missing") }
    let upd = req(OrderStatusUpdateRequest(status: .completed))
    upd.parameters.set("id", to: ord.id)
    _ = try await controller.updateStatus(req: upd)

    try await waitUntil(0.5) {
      let items2 = await captureFactorySingleton.sink.items
      return items2.contains { if case let .counter(label, _, _) = $0 { return label == "cafe.orders.completed" } else { return false } }
    }
    try await waitUntil(0.5) {
      let items2 = await captureFactorySingleton.sink.items
      return items2.contains { if case let .timer(label, _, _) = $0 { return label == "cafe.orders.cycle_seconds" } else { return false } }
    }
    try await tearDown()
  }

  // Inventory
  @Test
  func testInventoryMetrics() async throws {
    try await setUp()
    let controller = InventoryController()
    let r = req(InventoryController.InventoryItemCreate(sku: "sku1", name: "Milk", quantity: 3, reorderThreshold: 5, unit: "gal", supplier: nil))
    _ = try await controller.create(req: r)

    try await waitUntil(0.5) {
      let items = await captureFactorySingleton.sink.items
      return items.contains { if case let .recorder(label, _, v) = $0 { return label == "cafe.inventory.level" && v == 3 } else { return false } }
    }
    try await waitUntil(0.5) {
      let items = await captureFactorySingleton.sink.items
      return items.contains { if case let .counter(label, _, _) = $0 { return label == "cafe.inventory.low" } else { return false } }
    }
    try await tearDown()
  }

  // Menu and Reservation
  @Test
  func testMenuAndReservationMetrics() async throws {
    try await setUp()

    let menu = MenuController()
    let rm = req(MenuController.MenuItemCreate(name: "Latte", description: nil, priceCents: 450, isAvailable: true, category: "drinks"))
    _ = try await menu.create(req: rm)

    let res = ReservationController()
    let rr = req(ReservationController.ReservationCreate(name: "Jane", partySize: 2, startTime: Date(), phone: nil, notes: nil))
    _ = try await res.create(req: rr)

    try await waitUntil(0.5) {
      let items = await captureFactorySingleton.sink.items
      return items.contains { if case let .recorder(label, _, v) = $0 { return label == "cafe.menu.price_cents" && v == 450 } else { return false } }
    }
    try await waitUntil(0.5) {
      let items = await captureFactorySingleton.sink.items
      return items.contains { if case let .recorder(label, _, v) = $0 { return label == "cafe.menu.available" && v == 1 } else { return false } }
    }
    try await waitUntil(0.5) {
      let items = await captureFactorySingleton.sink.items
      return items.contains { if case let .counter(label, _, _) = $0 { return label == "cafe.reservations.created" } else { return false } }
    }
    try await tearDown()
  }

  // Order canceled path and dimension assertions
  @Test
  func testOrderCanceledMetricsAndDims() async throws {
    try await setUp()
    let controller = OrderController()
    // Create order
    let create = req(OrderCreateRequest(customerName: "Jane", items: [OrderItem(menuItemId: "m1", quantity: 1, notes: nil)], pickupTime: nil))
    _ = try await controller.create(req: create)
    // Fetch created order id
    let orders = try await app.mongoStore.listOrders()
    guard let ord = orders.first else { return #expect(Bool(false), "order missing") }

    // Cancel it
    let upd = req(OrderStatusUpdateRequest(status: .canceled))
    upd.parameters.set("id", to: ord.id)
    _ = try await controller.updateStatus(req: upd)

    try await waitUntil(0.5) {
      await self.containsCounter(label: "cafe.orders.canceled") { dims in dims.contains { $0.0 == "orderId" && $0.1 == ord.id } }
    }
    try await tearDown()
  }

  // Menu updates emit price and availability metrics with expected values
  @Test
  func testMenuUpdateEmitsMetrics() async throws {
    try await setUp()
    let controller = MenuController()
    // Create item
    let create = req(MenuController.MenuItemCreate(name: "Mocha", description: nil, priceCents: 500, isAvailable: true, category: "drinks"))
    let created = try await controller.create(req: create)
    await captureFactorySingleton.sink.reset() // focus on update metrics only
    // Update price and availability
    let updReq = req(MenuController.MenuItemUpdate(name: nil, description: nil, priceCents: 525, isAvailable: false, category: nil))
    updReq.parameters.set("id", to: created.id)
    _ = try await controller.update(req: updReq)

    try await waitUntil(0.5) {
      await self.containsRecorder(label: "cafe.menu.price_cents", valueEquals: 525) { dims in dims.contains { $0.0 == "menuItemId" && $0.1 == created.id } }
    }
    try await waitUntil(0.5) {
      await self.containsRecorder(label: "cafe.menu.available", valueEquals: 0) { dims in dims.contains { $0.0 == "menuItemId" && $0.1 == created.id } }
    }
    try await tearDown()
  }

  // Inventory update crossing threshold triggers low metric and level recorder with correct dims
  @Test
  func testInventoryUpdateLowTriggered() async throws {
    try await setUp()
    let controller = InventoryController()
    // Create item above threshold (no low event expected on create)
    let create = req(InventoryController.InventoryItemCreate(sku: "sku2", name: "Beans", quantity: 10, reorderThreshold: 5, unit: "bag", supplier: nil))
    let created = try await controller.create(req: create)
    await captureFactorySingleton.sink.reset()

    // Drop quantity below threshold
    let upd = req(InventoryController.InventoryItemUpdate(name: nil, quantity: 4, reorderThreshold: nil, unit: nil, supplier: nil))
    upd.parameters.set("id", to: created.id)
    _ = try await controller.update(req: upd)

    try await waitUntil(0.5) {
      await self.containsRecorder(label: "cafe.inventory.level", valueEquals: 4) { dims in
        dims.contains { $0.0 == "inventoryItemId" && $0.1 == created.id } && dims.contains { $0.0 == "sku" && $0.1 == created.sku }
      }
    }
    try await waitUntil(0.5) {
      await self.containsCounter(label: "cafe.inventory.low") { dims in dims.contains { $0.0 == "inventoryItemId" && $0.1 == created.id } }
    }
    try await tearDown()
  }
}

// Wait helper
private func waitUntil(_ timeout: TimeInterval, condition: @escaping @Sendable () async -> Bool) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await condition() { return }
    try await Task.sleep(nanoseconds: 25_000_000)
  }
  #expect(Bool(false), "Condition not met within timeout")
}


