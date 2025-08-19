//
//  RealtimeHub.swift
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

import BSON
import Vapor

enum OrderInfo: Codable, Sendable, Equatable {
  case created(Order)
  case updated(Order)
  case deleted(Order)
}

enum InventoryInfo: Codable, Sendable, Equatable {
  case runningLow(InventoryItem)
  case restocked(InventoryItem)
  case outOfStock(InventoryItem)
  case reordered(InventoryItem)
}

enum ReservationInfo: Codable, Sendable, Equatable {
  case created(Reservation)
  case updated(Reservation)
  case deleted(Reservation)
}

// MARK: - RealtimeHub

actor RealtimeHub {

  struct RealTimeEvent {
    let id: ObjectIdentifier
    let topic: Topic
    let packet: MessagePacket
  }

  enum MessagePacket: Codable, Sendable, Equatable {
    case order(OrderInfo)
    case inventory(InventoryInfo)
    case reservation(ReservationInfo)
    case modelUploaded(MLModelArtifact)
    case modelActivated(kind: PredictorKind, id: String)
    case modelDeleted(id: String)
    case predictorReady(kind: PredictorKind)
    case none
  }

  struct EquatableWebSocket: Equatable {
    let id = UUID()
    let ws: WebSocket
    static func == (lhs: EquatableWebSocket, rhs: EquatableWebSocket) -> Bool {
      lhs.id == rhs.id
    }
  }

  // Track active connections by WebSocket identity
  private var connections: [ObjectIdentifier: (topic: Topic, ws: WebSocket)] = [:]

  enum Topic: Equatable {
    case merchant
    case customer
  }

  /// One-time subscribe for a connection to a topic. Attaches basic lifecycle handlers.
  func subscribe(topic: Topic, ws: WebSocket) {
    let id = ObjectIdentifier(ws)
    connections[id] = (topic, ws)
      
    ws.onBinary { [weak self] ws, buffer in
      guard let self else { return }
        var buffer = buffer
        if let bytes: [UInt8] = buffer.readBytes(length: buffer.readableBytes) {
            for connection in await self.connections.values.filter({ $0.topic == topic }) {
                do {
                    try await connection.ws.send(bytes)
                } catch {
                    print("Failed to send message")
                }
            }
        }
    }

    ws.onClose.whenComplete { _ in
      Task { [weak self] in
        guard let self else { return }
        await self.purge(ws: ws)  //clean up
      }
    }
  }

  private func purge(ws: WebSocket) {
    let id = ObjectIdentifier(ws)
    connections.removeValue(forKey: id)
  }

  // Broadcast a message packet to all subscribers of a topic
  func publish(_ packet: MessagePacket, to topic: Topic) async {
    do {
      let document = try BSONEncoder().encode(packet)
      let data = document.makeData()
      var buffer = ByteBufferAllocator().buffer(capacity: data.count)
      buffer.writeBytes(data)
      for (_, entry) in connections where entry.topic == topic {
        entry.ws.send(buffer)
      }
    } catch {
      print("RealtimeHub.publish error: \(error)")
    }
  }
}

// MARK: - Application Storage

extension Application {
  private struct RealtimeKey: StorageKey { typealias Value = RealtimeHub }
  var realtime: RealtimeHub {
    get {
      if let hub = storage[RealtimeKey.self] { return hub }
      let hub = RealtimeHub()
      storage[RealtimeKey.self] = hub
      return hub
    }
    set { storage[RealtimeKey.self] = newValue }
  }
}


public struct CreateOrderRequest: Codable, Sendable, Equatable {
    public var customerName: String?
    public var items: [OrderItem]
    public var pickupTime: Date?
    public var channel: Order.OrderChannel?
    public var serviceType: Order.ServiceType?
    public var tableId: String?
    public var guests: Int?
    public var reservationId: String?

    public init(
        customerName: String? = nil,
        items: [OrderItem],
        pickupTime: Date? = nil,
        channel: Order.OrderChannel? = nil,
        serviceType: Order.ServiceType? = nil,
        tableId: String? = nil,
        guests: Int? = nil,
        reservationId: String? = nil
    ) {
        self.customerName = customerName
        self.items = items
        self.pickupTime = pickupTime
        self.channel = channel
        self.serviceType = serviceType
        self.tableId = tableId
        self.guests = guests
        self.reservationId = reservationId
    }
}
