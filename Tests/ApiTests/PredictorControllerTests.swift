import Testing
import Vapor
import Foundation
import BSON
@testable import cafe_smart_api

@Suite(.serialized)
actor PredictorControllerTests {
  private var app: Application!

  func setUp() async throws {
    app = try await Application.make(.testing)
    app.mongoStore = TestableMongoStore()
  }
  func tearDown() async throws {
    try await app.asyncShutdown()
  }

  private func req<T: Content>(_ body: T) -> Request {
    let r = Request(application: app, on: app.eventLoopGroup.next())
    r.headers.contentType = .json
    try! r.content.encode(body)
    return r
  }

  @Test
  func testGenerateClampsAndPersists() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    let controller = CafePredictorController()

    // horizonDays below 1 -> clamps to 1
    let r1 = req(PredictorRequest(horizonDays: 0))
    let resp1 = try await controller.generate(req: r1)
    #expect(resp1.points.count == 1)

    // horizonDays above 30 -> clamps to 30
    let r2 = req(PredictorRequest(horizonDays: 100))
    let resp2 = try await controller.generate(req: r2)
    #expect(resp2.points.count == 30)

    // latest returns a persisted in-memory record in testing env
    let latest = try await controller.latest(req: Request(application: app, on: app.eventLoopGroup.next()))
    #expect(latest.points.count == resp2.points.count)
  }

  @Test
  func testLatestGeneratesWhenEmpty() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    // Call latest with JSON content-type to avoid 415 in Testing harness
    let controller = CafePredictorController()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    req.headers.contentType = .json
    let latest = try await controller.latest(req: req)
    #expect(latest.points.count >= 1)
  }

  @Test
  func testExportCSVHeaders() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    let controller = CafePredictorController()

    func makeReq(dataset: String) -> Request {
      let r = Request(application: app, on: app.eventLoopGroup.next())
      try! r.query.encode(["dataset": dataset])
      return r
    }

    // Workload hourly response headers
    let w = try await controller.exportCSV(req: makeReq(dataset: "workloadhourly"))
    #expect(w.status == .ok)
    #expect(w.headers[.contentType].first == "text/csv; charset=utf-8")
    #expect(w.headers[.contentDisposition].first?.contains("workload_hourly.csv") == true)

    // Reservations hourly
    let r = try await controller.exportCSV(req: makeReq(dataset: "reservationshourly"))
    #expect(r.status == .ok)
    #expect(r.headers[.contentDisposition].first?.contains("reservations_hourly.csv") == true)

    // Demand hourly
    let d = try await controller.exportCSV(req: makeReq(dataset: "demandhourly"))
    #expect(d.status == .ok)
    #expect(d.headers[.contentDisposition].first?.contains("demand_hourly.csv") == true)

    // Reservation duration
    let rd = try await controller.exportCSV(req: makeReq(dataset: "reservationduration"))
    #expect(rd.status == .ok)
    #expect(rd.headers[.contentDisposition].first?.contains("reservation_duration.csv") == true)

  }

  @Test
  func testDecideRestockBySku() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    // Seed test data
    let store = app.mongoStore as! TestableMongoStore
    // Inventory
    let inv = InventoryItem(
      id: ObjectId().hexString,
      sku: "BEANS-TEST-1KG",
      name: "Test Beans",
      quantity: 10,
      reorderThreshold: 5,
      unit: "bag",
      supplier: nil
    )
    _ = try await store.create(inventoryItem: inv)

    let controller = CafePredictorController()
    // Testing mode returns ramp forecast (1..n). lead defaults to 3.
    struct DecideBody: Content { let sku: String; let daysAhead: Int }
    let reqBody = DecideBody(sku: "BEANS-TEST-1KG", daysAhead: 7)
    let req = Request(application: app, on: app.eventLoopGroup.next())
    req.headers.contentType = .json
    try req.content.encode(reqBody)

    let resp = try await controller.decideRestock(req: req)
    #expect(resp.sku == "BEANS-TEST-1KG")
    #expect(resp.leadTimeDays == 3) // default
    // Forecast ramp 1+2+3 for lead=3 => 6, safety = reorderThreshold=5 => ROP=11
    // onHand=10, so needRestock = true, reorderQty >= 1
    #expect(resp.reorderPoint == 11)
    #expect(resp.onHand == 10)
    #expect(resp.needRestock == true)
    #expect(resp.reorderQty >= 1)
  }

  @Test
  func testDecideRestockNoRestock() async throws {
    try await setUp()
    defer { Task { try? await app.asyncShutdown() } }
    // Seed test data with high on-hand to avoid restock
    let store = app.mongoStore as! TestableMongoStore
    let inv = InventoryItem(
      id: ObjectId().hexString,
      sku: "BEANS-ENOUGH-1KG",
      name: "Beans Plenty",
      quantity: 20, // onHand > ROP (11) given defaults
      reorderThreshold: 5,
      unit: "bag",
      supplier: nil
    )
    _ = try await store.create(inventoryItem: inv)

    let controller = CafePredictorController()
    struct DecideBody: Content { let sku: String; let daysAhead: Int }
    let reqBody = DecideBody(sku: "BEANS-ENOUGH-1KG", daysAhead: 7)
    let req = Request(application: app, on: app.eventLoopGroup.next())
    req.headers.contentType = .json
    try req.content.encode(reqBody)

    let resp = try await controller.decideRestock(req: req)
    // With testing ramp 1+2+3 and safety=reorderThreshold=5 -> ROP=11; onHand=20
    #expect(resp.needRestock == false)
    #expect(resp.reorderQty == 0)
  }
}


