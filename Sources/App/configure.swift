//
//  configure.swift
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

import JWT
import Metrics
import MongoKitten
import NIOSSL
import Vapor
import VaporSecurityHeaders

public func configure(_ app: Application) async throws {

  // Configure environment-specific settings
  switch app.environment {
  case .production:
    // Production configuration with Let's Encrypt SSL
    let homePath = FileManager().currentDirectoryPath
    let letsEncryptCertPath = homePath + (Environment.get("API_LOCAL_FULL_CHAIN") ?? "")
    let letsEncryptKeyPath = homePath + (Environment.get("API_LOCAL_PRIV_KEY") ?? "")
    let certs = try NIOSSLCertificate.fromPEMFile(letsEncryptCertPath)
      .map { NIOSSLCertificateSource.certificate($0) }
    let privateKey = try NIOSSLPrivateKey(file: letsEncryptKeyPath, format: .pem)
    var configuration = TLSConfiguration.makeServerConfiguration(
      certificateChain: certs, privateKey: .privateKey(privateKey))
    configuration.minimumTLSVersion = .tlsv13
    configuration.maximumTLSVersion = .tlsv13

    // Production server configuration (enable HTTP/1.1 for WebSocket upgrades and HTTP/2 for HTTPS)
    app.http.server.configuration = .init(
      hostname: "0.0.0.0",
      port: 8080,
      backlog: 256,
      reuseAddress: true,
      tcpNoDelay: true,
      responseCompression: .disabled,
      requestDecompression: .disabled,
      supportPipelining: true,
      supportVersions: Set<HTTPVersionMajor>([.one, .two]),
      tlsConfiguration: configuration,
      serverName: "CafeSmartAPI",
      logger: Logger(label: "[ com.needletails.cafesmart.api ]"))

  case .development:

    /// Dockerized containers need to have the host name set to 0.0.0.0 in order for it to be accessed outside of the container
    /// For example if NGINX is trying to access the port.
    app.http.server.configuration = .init(
      hostname: "0.0.0.0",
      port: 8080,
      supportVersions: Set<HTTPVersionMajor>([.one]),
      tlsConfiguration: .none,
      serverName: "CafeSmartAPI",
      logger: Logger(label: "[ com.needletails.cafesmart.api ]"))
  default:
    break
  }

  // Initialize data store
  // By default use in-memory TestableMongoStore in testing, or when USE_TEST_STORE=true/1/yes
  let useTestStoreEnv = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
  let useTestStore = app.environment == .testing
    || useTestStoreEnv == "1" || useTestStoreEnv == "true" || useTestStoreEnv == "yes"
  if useTestStore {
    // In tests, never seed to keep counts deterministic; in dev with test store, seed by default
    let shouldSeed = app.environment == .testing ? false : true
    app.mongoStore = TestableMongoStore(seedDummyData: shouldSeed)
  } else {
    let mongoURL = Environment.get("MONGO_URL") ?? ""
    try await app.initializeMongoDB(connectionString: mongoURL)
    app.mongoStore = MongoCacheManager(database: app.mongoDB)
  }

  // Configure request body size limit (allow larger uploads for models)
  app.routes.defaultMaxBodySize = 150_000_000 // ~150MB

  // Configure BSON encoding/decoding
  ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
  ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)

  // Configure JWT HMAC signing
  let hmacSecret = Environment.get("HMAC_SECRET") ?? ""
  await app.jwt.keys.add(hmac: HMACKey(stringLiteral: hmacSecret), digestAlgorithm: .sha256)

  // MARK: Middleware Configuration

  // CORS configuration for cross-origin requests
  let corsConfiguration = CORSMiddleware.Configuration(
    allowedOrigin: .all,
    allowedMethods: [.GET, .POST, .OPTIONS, .PUT, .DELETE, .PATCH],
    allowedHeaders: [
      .accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent,
      .accessControlAllowOrigin,
    ])

  let corsMiddleware = CORSMiddleware(configuration: corsConfiguration)
  let routeLogging = RouteLoggingMiddleware(logLevel: .info)

  // Initialize middleware stack
  app.middleware = .init()

  // Security headers configuration
  let securityHeadersFactory = SecurityHeadersFactory.api()
  securityHeadersFactory.with(contentTypeOptions: .init(option: .nosniff))
  securityHeadersFactory.with(frameOptions: .init(option: .deny))
  securityHeadersFactory.with(referrerPolicy: .init(.noReferrer))

  // Add HSTS in production
  if app.environment == .production {
    securityHeadersFactory.with(strictTransportSecurity: .init())
  }

  // Apply middleware in order
  app.middleware.use(securityHeadersFactory.build())
  app.middleware.use(corsMiddleware)
  app.middleware.use(routeLogging)
  app.middleware.use(ErrorMiddleware.default(environment: app.environment))
  app.middleware.use(app.sessions.middleware)

  // Configure logging level based on build configuration
  #if DEBUG
    app.logger.logLevel = .trace
  #else
    app.logger.logLevel = .info
  #endif

  
  // Initialize Swift Metrics mapping to cafe metrics events
  // Skip in testing since the test runner already bootstraps a Metrics factory
  if app.environment != .testing {
    if await !metricsIntialized {
      await setMetricsInitialized()
      await CafeDomainMetrics.initialize(app: app)
    }
  }
  // Register API routes
  app.realtime = RealtimeHub()
  try routes(app)
  print(app.routes.all)
}

@MainActor
func setMetricsInitialized() async {
    metricsIntialized = true
}
@MainActor
var metricsIntialized = false
