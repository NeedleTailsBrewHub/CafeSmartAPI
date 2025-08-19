//
//  Request+Extension.swift
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

import Meow
import MongoKitten
import Vapor

extension Request {

  public var store: any MongoStore {
    application.mongoStore
  }

  public var mongoDB: MongoDatabase {
    return application.mongoDB
  }

  public var meow: MeowDatabase {
    MeowDatabase(mongoDB)
  }
}
