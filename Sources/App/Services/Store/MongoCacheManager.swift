//
//  MongoCacheManager.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 2025-08-19.
//

@preconcurrency import BSON
import Crypto
import Foundation
import MongoKitten
import Vapor

public actor MongoCacheManager: MongoStore {
  public enum Errors: Error { case notFound }

  private let db: MongoDatabase
  private let orders = "orders"
  private let inventory = "inventory_items"
  private let menu = "menu_items"
  private let reservations = "reservations"
  private let users = "users"
  private let refresh = "refresh_tokens"
  private let recipesCol = "recipes"
  private let seatingAreasCol = "seating_areas"
  private let tablesCol = "tables"
  private let businessConfigCol = "business_config"

  public init(database: MongoDatabase) {
    self.db = database
  }

  // MARK: Orders
  public func create(order: Order) async throws -> Order {
    try await db[orders].insert(order.toDocument())
    return order
  }

  public func listOrders() async throws -> [Order] {
    var result: [Order] = []
    for try await doc in db[orders].find() { result.append(try Order.fromDocument(doc)) }
    return result
  }

  public func findOrder(by id: String) async throws -> Order? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[orders].findOne("_id" == oid) { return try Order.fromDocument(doc) }
    return nil
  }

  public func update(order: Order) async throws -> Order {
    guard let oid = ObjectId(order.id) else { throw Errors.notFound }
    _ = try await db[orders].updateOne(where: "_id" == oid, to: order.toDocument(using: oid))
    return order
  }

  public func deleteOrder(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[orders].deleteOne(where: "_id" == oid)
  }

  // MARK: Inventory
  public func create(inventoryItem: InventoryItem) async throws -> InventoryItem {
    try await db[inventory].insert(inventoryItem.toDocument())
    return inventoryItem
  }

  public func listInventory() async throws -> [InventoryItem] {
    var result: [InventoryItem] = []
    for try await doc in db[inventory].find() { result.append(try InventoryItem.fromDocument(doc)) }
    return result
  }

  public func findInventory(by id: String) async throws -> InventoryItem? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[inventory].findOne("_id" == oid) {
      return try InventoryItem.fromDocument(doc)
    }
    return nil
  }

  public func update(inventoryItem: InventoryItem) async throws -> InventoryItem {
    guard let oid = ObjectId(inventoryItem.id) else { throw Errors.notFound }
    _ = try await db[inventory].updateOne(
      where: "_id" == oid, to: inventoryItem.toDocument(using: oid))
    return inventoryItem
  }

  public func deleteInventory(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[inventory].deleteOne(where: "_id" == oid)
  }

  // MARK: Menu
  public func create(menuItem: MenuItem) async throws -> MenuItem {
    try await db[menu].insert(menuItem.toDocument())
    return menuItem
  }

  public func listMenu() async throws -> [MenuItem] {
    var result: [MenuItem] = []
    for try await doc in db[menu].find() { result.append(try MenuItem.fromDocument(doc)) }
    return result
  }

  public func findMenuItem(by id: String) async throws -> MenuItem? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[menu].findOne("_id" == oid) { return try MenuItem.fromDocument(doc) }
    return nil
  }

  public func update(menuItem: MenuItem) async throws -> MenuItem {
    guard let oid = ObjectId(menuItem.id) else { throw Errors.notFound }
    _ = try await db[menu].updateOne(where: "_id" == oid, to: menuItem.toDocument(using: oid))
    return menuItem
  }

  public func deleteMenuItem(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[menu].deleteOne(where: "_id" == oid)
  }

  // MARK: Reservations
  public func create(reservation: Reservation) async throws -> Reservation {
    try await db[reservations].insert(reservation.toDocument())
    return reservation
  }

  public func listReservations() async throws -> [Reservation] {
    var result: [Reservation] = []
    for try await doc in db[reservations].find() {
      result.append(try Reservation.fromDocument(doc))
    }
    return result
  }

  public func findReservation(by id: String) async throws -> Reservation? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[reservations].findOne("_id" == oid) {
      return try Reservation.fromDocument(doc)
    }
    return nil
  }

  public func deleteReservation(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[reservations].deleteOne(where: "_id" == oid)
  }

  // MARK: Users
  public func createUser(_ user: User) async throws {
    try await db[users].insert(user.toDocument())
  }

  public func listUsers() async throws -> [User] {
    var result: [User] = []
    for try await doc in db[users].find() { result.append(try User.fromDocument(doc)) }
    return result
  }

  public func findUser(byId id: String) async throws -> User? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[users].findOne("_id" == oid) { return try User.fromDocument(doc) }
    return nil
  }

  public func findUser(byEmail emailLowercased: String) async throws -> User? {
    if let doc = try await db[users].findOne("email" == emailLowercased) {
      return try User.fromDocument(doc)
    }
    return nil
  }

  public func updateUser(_ user: User) async throws -> User {
    guard let oid = ObjectId(user.id) else { throw Errors.notFound }
    _ = try await db[users].updateOne(where: "_id" == oid, to: user.toDocument(using: oid))
    return user
  }

  public func updatePassword(user: User) async throws {
    guard let oid = ObjectId(user.id) else { throw Errors.notFound }
    _ = try await db[users].updateOne(where: "_id" == oid, to: user.toDocument(using: oid))
  }

  public func deleteUser(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[users].deleteOne(where: "_id" == oid)
  }

  // MARK: Refresh Tokens
  public func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws
    -> Data
  {
    let data = try BSONEncoder().encode(token).makeData()
    let sealed = try AES.GCM.seal(data, using: symmetricKey)
    guard let combined = sealed.combined else { throw Abort(.badRequest) }
    let enc = EncryptedObject(refreshToken: combined)
    try await db[refresh].insert(try BSONEncoder().encode(enc))
    return combined
  }

  public func findUser(refreshToken: Data) async throws -> User? {
    for try await doc in db[refresh].find() {
      if let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        enc.refreshToken == refreshToken
      {
        return nil
      }
    }
    return nil
  }

  public func cleanupExpiredTokens() async throws {}

  public func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey)
    async throws
  {
    var toDelete: [Document] = []
    for try await doc in db[refresh].find() {
      if let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        let dec = try? AES.GCM.open(.init(combined: enc.refreshToken), using: symmetricKey),
        let tok = try? BSONDecoder().decode(RefreshToken.self, from: Document(data: dec))
      {
        if tok._id == username && tok.expiresAt < Date() { toDelete.append(doc) }
      }
    }
    for d in toDelete { _ = try await db[refresh].deleteOne(where: d) }
  }

  public func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws {
    var toDelete: [Document] = []
    for try await doc in db[refresh].find() {
      if let enc = try? BSONDecoder().decode(EncryptedObject.self, from: doc),
        let dec = try? AES.GCM.open(.init(combined: enc.refreshToken), using: symmetricKey),
        let tok = try? BSONDecoder().decode(RefreshToken.self, from: Document(data: dec))
      {
        if tok._id == id { toDelete.append(doc) }
      }
    }
    for d in toDelete { _ = try await db[refresh].deleteOne(where: d) }
  }

  public func removeUserTokens(_ user: User) async throws {
    // Best-effort: tokens are user-encrypted; without symmetric key, we can't match
  }

  // MARK: Recipes
  public func create(recipe: Recipe) async throws -> Recipe {
    try await db[recipesCol].insert(recipe.toDocument())
    return recipe
  }

  public func listRecipes() async throws -> [Recipe] {
    var result: [Recipe] = []
    for try await doc in db[recipesCol].find() { result.append(try Recipe.fromDocument(doc)) }
    return result
  }

  public func findRecipe(by id: String) async throws -> Recipe? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[recipesCol].findOne("_id" == oid) { return try Recipe.fromDocument(doc) }
    return nil
  }

  public func findRecipes(menuItemId: String) async throws -> [Recipe] {
    var result: [Recipe] = []
    for try await doc in db[recipesCol].find(["menuItemId": menuItemId]) {
      result.append(try Recipe.fromDocument(doc))
    }
    return result
  }

  public func update(recipe: Recipe) async throws -> Recipe {
    guard let oid = ObjectId(recipe.id) else { throw Errors.notFound }
    _ = try await db[recipesCol].updateOne(where: "_id" == oid, to: recipe.toDocument(using: oid))
    return recipe
  }

  public func deleteRecipe(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[recipesCol].deleteOne(where: "_id" == oid)
  }

  // MARK: Seating Areas
  public func create(seatingArea: SeatingArea) async throws -> SeatingArea {
    try await db[seatingAreasCol].insert(seatingArea.toDocument())
    return seatingArea
  }

  public func listSeatingAreas() async throws -> [SeatingArea] {
    var result: [SeatingArea] = []
    for try await doc in db[seatingAreasCol].find() { result.append(try SeatingArea.fromDocument(doc)) }
    return result
  }

  public func findSeatingArea(by id: String) async throws -> SeatingArea? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[seatingAreasCol].findOne("_id" == oid) { return try SeatingArea.fromDocument(doc) }
    return nil
  }

  public func update(seatingArea: SeatingArea) async throws -> SeatingArea {
    guard let oid = ObjectId(seatingArea.id) else { throw Errors.notFound }
    _ = try await db[seatingAreasCol].updateOne(where: "_id" == oid, to: seatingArea.toDocument(using: oid))
    return seatingArea
  }

  public func deleteSeatingArea(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[seatingAreasCol].deleteOne(where: "_id" == oid)
    // Cascade delete tables in this area
    for try await doc in db[tablesCol].find(["areaId": id]) {
      _ = try await db[tablesCol].deleteOne(where: doc)
    }
  }

  // MARK: Tables
  public func create(table: Table) async throws -> Table {
    try await db[tablesCol].insert(table.toDocument())
    return table
  }

  public func listTables() async throws -> [Table] {
    var result: [Table] = []
    for try await doc in db[tablesCol].find() { result.append(try Table.fromDocument(doc)) }
    return result
  }

  public func findTable(by id: String) async throws -> Table? {
    guard let oid = ObjectId(id) else { return nil }
    if let doc = try await db[tablesCol].findOne("_id" == oid) { return try Table.fromDocument(doc) }
    return nil
  }

  public func listTables(in areaId: String) async throws -> [Table] {
    var result: [Table] = []
    for try await doc in db[tablesCol].find(["areaId": areaId]) { result.append(try Table.fromDocument(doc)) }
    return result
  }

  public func update(table: Table) async throws -> Table {
    guard let oid = ObjectId(table.id) else { throw Errors.notFound }
    _ = try await db[tablesCol].updateOne(where: "_id" == oid, to: table.toDocument(using: oid))
    return table
  }

  public func deleteTable(id: String) async throws {
    guard let oid = ObjectId(id) else { return }
    _ = try await db[tablesCol].deleteOne(where: "_id" == oid)
  }

  // MARK: Business Config
  public func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig {
    if let oid = ObjectId(config.id) {
      _ = try await db[businessConfigCol].updateOne(where: "_id" == oid, to: config.toDocument(using: oid))
      return config
    } else {
      try await db[businessConfigCol].insert(config.toDocument())
      return config
    }
  }

  public func getBusinessConfig() async throws -> BusinessConfig? {
    if let doc = try await db[businessConfigCol].findOne() { return try BusinessConfig.fromDocument(doc) }
    return nil
  }
}
