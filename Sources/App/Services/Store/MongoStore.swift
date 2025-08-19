//
//  MongoStore.swift
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
import Foundation
import MongoKitten
import Vapor

public protocol MongoStore: Sendable {
  // Orders
  func create(order: Order) async throws -> Order
  func listOrders() async throws -> [Order]
  func findOrder(by id: String) async throws -> Order?
  func update(order: Order) async throws -> Order
  func deleteOrder(id: String) async throws

  // Inventory
  func create(inventoryItem: InventoryItem) async throws -> InventoryItem
  func listInventory() async throws -> [InventoryItem]
  func findInventory(by id: String) async throws -> InventoryItem?
  func update(inventoryItem: InventoryItem) async throws -> InventoryItem
  func deleteInventory(id: String) async throws

  // Menu Items
  func create(menuItem: MenuItem) async throws -> MenuItem
  func listMenu() async throws -> [MenuItem]
  func findMenuItem(by id: String) async throws -> MenuItem?
  func update(menuItem: MenuItem) async throws -> MenuItem
  func deleteMenuItem(id: String) async throws

  // Reservations
  func create(reservation: Reservation) async throws -> Reservation
  func listReservations() async throws -> [Reservation]
  func findReservation(by id: String) async throws -> Reservation?
  func deleteReservation(id: String) async throws

  // Users (CRUD)
  func createUser(_ user: User) async throws
  func listUsers() async throws -> [User]
  func findUser(byId id: String) async throws -> User?
  func findUser(byEmail emailLowercased: String) async throws -> User?
  func updateUser(_ user: User) async throws -> User
  func updatePassword(user: User) async throws
  func deleteUser(id: String) async throws

  // Refresh tokens / posts (for testing parity)
  func createRefreshToken(_ token: RefreshToken, symmetricKey: SymmetricKey) async throws -> Data
  func findUser(refreshToken: Data) async throws -> User?
  func cleanupExpiredTokens() async throws
  func cleanupExpiredTokensForUser(_ username: String, symmetricKey: SymmetricKey) async throws
  func deleteToken(_ id: String, symmetricKey: SymmetricKey) async throws
  func removeUserTokens(_ user: User) async throws

  // Recipes
  func create(recipe: Recipe) async throws -> Recipe
  func listRecipes() async throws -> [Recipe]
  func findRecipe(by id: String) async throws -> Recipe?
  func findRecipes(menuItemId: String) async throws -> [Recipe]
  func update(recipe: Recipe) async throws -> Recipe
  func deleteRecipe(id: String) async throws

  // Seating
  func create(seatingArea: SeatingArea) async throws -> SeatingArea
  func listSeatingAreas() async throws -> [SeatingArea]
  func findSeatingArea(by id: String) async throws -> SeatingArea?
  func update(seatingArea: SeatingArea) async throws -> SeatingArea
  func deleteSeatingArea(id: String) async throws

  func create(table: Table) async throws -> Table
  func listTables() async throws -> [Table]
  func findTable(by id: String) async throws -> Table?
  func listTables(in areaId: String) async throws -> [Table]
  func update(table: Table) async throws -> Table
  func deleteTable(id: String) async throws

  // Business config (assume singleton)
  func upsertBusinessConfig(_ config: BusinessConfig) async throws -> BusinessConfig
  func getBusinessConfig() async throws -> BusinessConfig?

  // ML model artifacts
  func createModelArtifact(_ artifact: MLModelArtifact) async throws
  func listModelArtifacts() async throws -> [MLModelArtifact]
  func findModelArtifact(by id: String) async throws -> MLModelArtifact?
  func setActiveModel(id: String) async throws
  func deleteModelArtifact(id: String) async throws
}

// App storage for dependency injection
extension Application {
  private struct MongoStoreKey: StorageKey { typealias Value = any MongoStore }
  public var mongoStore: any MongoStore {
    get { storage[MongoStoreKey.self]! }
    set { storage[MongoStoreKey.self] = newValue }
  }
}
