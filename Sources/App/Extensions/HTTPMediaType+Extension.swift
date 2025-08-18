//
//  HTTPMediaType+Extension.swift
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
import Vapor

extension HTTPMediaType {
  public static var bson: HTTPMediaType {
    HTTPMediaType(type: "application", subType: "bson")
  }
}
