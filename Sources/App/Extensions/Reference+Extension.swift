//
//  Reference+Extension.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  All rights reserved. Unauthorized copying, distribution, or use
//  of this software is strictly prohibited.
//
//  This file is part of the CafeSmartAPI Project
//
import BSON
import Meow

extension Reference where M.Identifier == Document {
  init<E: Encodable>(unsafeToEncoded encoded: E) throws {
    try self.init(unsafeTo: BSONEncoder().encode(encoded))
  }
}
