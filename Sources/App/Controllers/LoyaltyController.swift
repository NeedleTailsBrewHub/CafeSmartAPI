@preconcurrency import BSON
import MongoKitten
import Vapor

private struct DBLoyalty: Codable {
    var _id: ObjectId
    var userId: String
    var points: Int
    var tier: String
    var createdAt: Date
}

struct LoyaltyEnrollRequest: Content {
    let userId: String
}

struct LoyaltyAccrueRequest: Content {
    let userId: String
    let points: Int
}

struct LoyaltyRedeemRequest: Content {
    let userId: String
    let points: Int
}

struct LoyaltyAccountPublic: Content {
    let id: String
    let userId: String
    let points: Int
    let tier: String
}

actor LoyaltyController {
    private let collection = "loyalty_accounts"
    
    // In-memory backing store for testing environment
    private struct LoyaltyMemoryKey: StorageKey {
        typealias Value = [DBLoyalty]
    }
    
    private func loadMemory(_ app: Application) -> [DBLoyalty] {
        app.storage[LoyaltyMemoryKey.self] ?? []
    }
    
    private func saveMemory(_ app: Application, _ accounts: [DBLoyalty]) {
        app.storage[LoyaltyMemoryKey.self] = accounts
    }
    
    func enroll(req: Request) async throws -> LoyaltyAccountPublic {
        let body = try req.content.decode(LoyaltyEnrollRequest.self)
        if req.application.environment == .testing {
            var accounts = loadMemory(req.application)
            if let acc = accounts.first(where: { $0.userId == body.userId }) {
                return LoyaltyAccountPublic(id: acc._id.hexString, userId: acc.userId, points: acc.points, tier: acc.tier)
            }
            let oid = ObjectId()
            let acc = DBLoyalty(
                _id: oid,
                userId: body.userId,
                points: 0,
                tier: "basic",
                createdAt: Date())
            
            accounts.append(acc)
            saveMemory(req.application, accounts)
            return LoyaltyAccountPublic(
                id: oid.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        } else {
            let coll = req.mongoDB[collection]
            if let existing = try await coll.findOne("userId" == body.userId) {
                let acc = try BSONDecoder().decode(DBLoyalty.self, from: existing)
                return LoyaltyAccountPublic(
                    id: acc._id.hexString,
                    userId: acc.userId,
                    points: acc.points,
                    tier: acc.tier)
            }
            let oid = ObjectId()
            let db = DBLoyalty(_id: oid, userId: body.userId, points: 0, tier: "basic", createdAt: Date())
            try await req.mongoDB[collection].insert(BSONEncoder().encode(db))
            return LoyaltyAccountPublic(
                id: oid.hexString,
                userId: db.userId,
                points: db.points,
                tier: db.tier)
        }
    }
    
    func get(req: Request) async throws -> LoyaltyAccountPublic {
        guard let id = req.parameters.get("id"), let oid = ObjectId(id) else { throw Abort(.badRequest) }
        if req.application.environment == .testing {
            let accounts = loadMemory(req.application)
            guard let acc = accounts.first(where: { $0._id == oid }) else {
                throw Abort(.notFound)
            }
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        } else {
            guard let doc = try await req.mongoDB[collection].findOne("_id" == oid) else { throw Abort(.notFound) }
            let acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        }
    }
    
    func accrue(req: Request) async throws -> LoyaltyAccountPublic {
        let body = try req.content.decode(LoyaltyAccrueRequest.self)
        if req.application.environment == .testing {
            var accounts = loadMemory(req.application)
            guard let idx = accounts.firstIndex(where: { $0.userId == body.userId }) else {
                throw Abort(.notFound)
            }
            accounts[idx].points += body.points
            accounts[idx].tier = tierFor(points: accounts[idx].points)
            saveMemory(req.application, accounts)
            let acc = accounts[idx]
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        } else {
            let coll = req.mongoDB[collection]
            guard let doc = try await coll.findOne("userId" == body.userId) else { throw Abort(.notFound) }
            var acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
            acc.points += body.points
            acc.tier = tierFor(points: acc.points)
            _ = try await coll.updateOne(where: "_id" == acc._id, to: BSONEncoder().encode(acc))
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        }
    }
    
    func redeem(req: Request) async throws -> LoyaltyAccountPublic {
        let body = try req.content.decode(LoyaltyRedeemRequest.self)
        if req.application.environment == .testing {
            var accounts = loadMemory(req.application)
            guard let idx = accounts.firstIndex(where: { $0.userId == body.userId }) else {
                throw Abort(.notFound)
            }
            guard accounts[idx].points >= body.points else {
                throw Abort(.badRequest, reason: "Insufficient points")
            }
            accounts[idx].points -= body.points
            accounts[idx].tier = tierFor(points: accounts[idx].points)
            saveMemory(req.application, accounts)
            let acc = accounts[idx]
            
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
            
        } else {
            let coll = req.mongoDB[collection]
            guard let doc = try await coll.findOne("userId" == body.userId) else {
                throw Abort(.notFound)
            }
            var acc = try BSONDecoder().decode(DBLoyalty.self, from: doc)
            guard acc.points >= body.points else {
                throw Abort(.badRequest, reason: "Insufficient points")
            }
            acc.points -= body.points
            acc.tier = tierFor(points: acc.points)
            _ = try await coll.updateOne(where: "_id" == acc._id, to: BSONEncoder().encode(acc))
            
            return LoyaltyAccountPublic(
                id: acc._id.hexString,
                userId: acc.userId,
                points: acc.points,
                tier: acc.tier)
        }
    }
    
    private func tierFor(points: Int) -> String {
        switch points {
        case 0..<100: return "basic"
        case 100..<300: return "silver"
        case 300..<700: return "gold"
        default: return "platinum"
        }
    }
}
