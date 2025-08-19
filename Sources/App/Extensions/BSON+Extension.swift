//
//  BSON+Extension.swift
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

/// Extension to make BSONEncoder compatible with Vapor's ContentEncoder protocol.
///
/// This extension allows BSONEncoder to be used as a content encoder in Vapor
/// applications, enabling automatic BSON serialization of response bodies.
/// It converts Swift objects to BSON documents and sets the appropriate
/// content type header.
///
/// ## Usage
/// ```swift
/// // Configure BSON encoding globally
/// ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
///
/// // Use in routes
/// app.get("data") { req -> Response in
///     let data = MyDataModel(...)
///     var response = Response()
///     try BSONEncoder().encode(data, to: &response.body, headers: &response.headers)
///     return response
/// }
/// ```
extension BSONEncoder: @retroactive ContentEncoder, @unchecked Sendable {
  /**
   * Encodes a Swift object to BSON and writes it to the response body.
   *
   * This method converts the encodable object to a BSON document and
   * writes it to the provided byte buffer. It also sets the content
   * type header to indicate BSON format.
   *
   * - Parameters:
   *   - encodable: The Swift object to encode
   *   - body: The byte buffer to write the encoded data to
   *   - headers: The HTTP headers to update with content type
   * - Throws: Encoding errors if the object cannot be converted to BSON
   */
  public func encode<E>(_ encodable: E, to body: inout ByteBuffer, headers: inout HTTPHeaders)
    throws where E: Encodable
  {
    let document = try self.encode(encodable)
    body = document.makeByteBuffer()
    headers.add(name: .contentType, value: "application/bson")
  }
}

/// Extension to make BSONDecoder compatible with Vapor's ContentDecoder protocol.
///
/// This extension allows BSONDecoder to be used as a content decoder in Vapor
/// applications, enabling automatic BSON deserialization of request bodies.
/// It converts BSON documents from request bodies back to Swift objects.
///
/// ## Usage
/// ```swift
/// // Configure BSON decoding globally
/// ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)
///
/// // Use in routes
/// app.post("data") { req -> Response in
///     let data = try req.content.decode(MyDataModel.self)
///     // Process the decoded data...
///     return Response(status: .ok)
/// }
/// ```
extension BSONDecoder: @retroactive ContentDecoder {
  /**
   * Decodes a BSON document from the request body to a Swift object.
   *
   * This method reads BSON data from the provided byte buffer and
   * converts it to the specified Swift type.
   *
   * - Parameters:
   *   - decodable: The Swift type to decode to
   *   - body: The byte buffer containing BSON data
   *   - headers: The HTTP headers (unused in this implementation)
   * - Returns: The decoded Swift object
   * - Throws: Decoding errors if the BSON cannot be converted to the target type
   */
  public func decode<D>(_ decodable: D.Type, from body: ByteBuffer, headers: HTTPHeaders) throws
    -> D where D: Decodable
  {
    return try self.decode(decodable, from: Document(buffer: body))
  }
}

// Provide a convenient protocol to encode BSON directly as HTTP responses
public protocol BSONResponseEncodable: AsyncResponseEncodable, Encodable {}

public extension BSONResponseEncodable {
  func encodeResponse(for request: Request) async throws -> Response {
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/bson")
    let body = try BSONEncoder().encode(self)
    return .init(status: .ok, headers: headers, body: .init(buffer: body.makeByteBuffer()))
  }
}
