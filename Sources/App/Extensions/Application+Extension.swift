import Meow
import MongoKitten
// MIT License
//
// Copyright (c) 2025 CafeSmartAPI contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
import Vapor

/// Storage key for MongoDB database instance.
///
/// This key is used to store the MongoDB database connection
/// in the Vapor application's storage.
private struct MongoDBStorageKey: StorageKey {
    typealias Value = MongoDatabase
}

/// Extension to add MongoDB support to Vapor applications.
///
/// This extension provides convenient access to MongoDB database
/// connections and Meow ODM functionality within Vapor applications.
/// It includes methods for initializing database connections and
/// accessing both raw MongoDB and Meow database instances.
///
/// ## Features
/// - **MongoDB Integration**: Direct access to MongoDatabase instances
/// - **Meow ODM Support**: Access to Meow database for object-document mapping
/// - **Connection Management**: Easy database initialization and connection setup
/// - **Storage Integration**: Seamless integration with Vapor's storage system
///
/// ## Usage
/// ```swift
/// // Initialize MongoDB connection
/// try await app.initializeMongoDB(connectionString: "mongodb://localhost:27017")
///
/// // Access MongoDB directly
/// let collection = app.mongoDB["users"]
///
/// // Access Meow ODM
/// let meowDB = app.meow
/// ```
extension Application {
    
    /**
     * Access to the Meow database for object-document mapping.
     *
     * This property provides access to the Meow ODM database,
     * which offers a more Swift-friendly interface for working
     * with MongoDB documents.
     *
     * - Returns: The Meow database instance
     */
    public var meow: MeowDatabase {
        MeowDatabase(mongoDB)
    }
    
    /**
     * Access to the MongoDB database instance.
     *
     * This property provides direct access to the MongoDB database
     * connection stored in the application's storage. It will crash
     * if the database hasn't been initialized.
     *
     * - Returns: The MongoDB database instance
     * - Note: This will crash if `initializeMongoDB` hasn't been called
     */
    public var mongoDB: MongoDatabase {
        get {
            storage[MongoDBStorageKey.self]!
        }
        set {
            storage[MongoDBStorageKey.self] = newValue
        }
    }
    
    /**
     * Initialize MongoDB connection with the provided connection string.
     *
     * This method establishes a connection to MongoDB using the provided
     * connection string and stores the database instance in the application's
     * storage for later use.
     *
     * - Parameter connectionString: The MongoDB connection string
     * - Throws: Various MongoDB connection errors
     *
     * ## Connection String Format
     * ```
     * mongodb://username:password@host:port/database
     * mongodb://localhost:27017/needletail
     * mongodb+srv://username:password@cluster.mongodb.net/database
     * ```
     */
    public func initializeMongoDB(connectionString: String) async throws {
        self.mongoDB = try await MongoDatabase.connect(to: connectionString)
    }
    
    private struct CafeTestWriterKey: StorageKey { typealias Value = CafeEventTestWriter }
    var cafeMetricsTestWriter: CafeEventTestWriter? {
        get { storage[CafeTestWriterKey.self] }
        set { storage[CafeTestWriterKey.self] = newValue }
    }
}
