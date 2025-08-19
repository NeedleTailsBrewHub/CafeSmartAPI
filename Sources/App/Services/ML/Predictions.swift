//
//  Predictions.swift
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

import Foundation
import Vapor

#if os(Linux) && arch(x86_64) && canImport(CONNX)
import CONNX

actor Predictor {
    enum Errors: Error { case msg(String) }
    
    private nonisolated(unsafe) let api: UnsafePointer<OrtApi>
    private nonisolated(unsafe) var env: OpaquePointer?
    private nonisolated(unsafe) var session: OpaquePointer?
    private nonisolated(unsafe) var mem: OpaquePointer?
    
    init(modelPath: String) async throws {
        guard let base = OrtGetApiBase() else { throw Errors.msg("OrtGetApiBase returned nil") }
        guard let apiPtr = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else { throw Errors.msg("GetApi nil") }
        self.api = apiPtr
        
        try check(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "vapor-ort", &env))
        do {
            var opts: OpaquePointer?
            try check(api.pointee.CreateSessionOptions(&opts))
            defer { if let o = opts { api.pointee.ReleaseSessionOptions(o) } }
            
            // Avoid capturing non-Sendable options in a closure; use an explicit C string
            let cstr = strdup(modelPath)
            guard let cstr else { throw Errors.msg("strdup failed for modelPath") }
            defer { free(cstr) }
            
            try check(api.pointee.CreateSession(env, cstr, opts, &session))
        }
        try check(api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem))
    }
    
    deinit {
        if let s = session { api.pointee.ReleaseSession(s) }
        if let m = mem { api.pointee.ReleaseMemoryInfo(m) }
        if let e = env { api.pointee.ReleaseEnv(e) }
    }
    
    func ioNames() throws -> (String, String) {
        var alloc: UnsafeMutablePointer<OrtAllocator>?
        try check(api.pointee.GetAllocatorWithDefaultOptions(&alloc))
        guard let A = alloc else { throw Errors.msg("No default allocator") }
        var inC: UnsafeMutablePointer<CChar>?
        var outC: UnsafeMutablePointer<CChar>?
        try check(api.pointee.SessionGetInputName(session, 0, A, &inC))
        try check(api.pointee.SessionGetOutputName(session, 0, A, &outC))
        let i = String(cString: inC!)
        let o = String(cString: outC!)
        if let freeFn = A.pointee.Free {
            if let inC { freeFn(A, UnsafeMutableRawPointer(inC)) }
            if let outC { freeFn(A, UnsafeMutableRawPointer(outC)) }
        }
        return (i, o)
    }
    
    func predictFloat(input: [Float], shape: [Int64], inputName: String, outputName: String) throws -> [Float] {
        let elementCount = input.count
        let byteCount = elementCount * MemoryLayout<Float>.stride
        let dataPtr = UnsafeMutablePointer<Float>.allocate(capacity: elementCount)
        for i in 0..<elementCount { dataPtr[i] = input[i] }
        
        let dimsCount = shape.count
        let dimsPtr = UnsafeMutablePointer<Int64>.allocate(capacity: dimsCount)
        for i in 0..<dimsCount { dimsPtr[i] = shape[i] }
        
        var inVal: OpaquePointer?
        try check(api.pointee.CreateTensorWithDataAsOrtValue(
            mem,
            UnsafeMutableRawPointer(dataPtr), byteCount,
            dimsPtr, Int(dimsCount),
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &inVal
        ))
        defer {
            if let v = inVal { api.pointee.ReleaseValue(v) }
            dimsPtr.deallocate()
            dataPtr.deallocate()
        }
        
        let inC = inputName.withCString { strdup($0) }
        let outC = outputName.withCString { strdup($0) }
        guard let inC, let outC else { throw Errors.msg("strdup failed for names") }
        defer { free(inC); free(outC) }
        
        let inNames = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: 1)
        inNames[0] = UnsafePointer(inC)
        defer { inNames.deallocate() }
        
        let outNames = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: 1)
        outNames[0] = UnsafePointer(outC)
        defer { outNames.deallocate() }
        
        let inVals = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
        inVals[0] = inVal
        defer { inVals.deallocate() }
        
        let outVals = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
        outVals[0] = nil
        defer { outVals.deallocate() }
        
        try check(api.pointee.Run(
            session, nil,
            inNames, inVals, 1,
            outNames, 1,
            outVals
        ))
        
        guard let outOrt = outVals[0] else { throw Errors.msg("No output") }
        defer { api.pointee.ReleaseValue(outOrt) }
        var raw: UnsafeMutableRawPointer?
        try check(api.pointee.GetTensorMutableData(outOrt, &raw))
        var typeShape: OpaquePointer?
        try check(api.pointee.GetTensorTypeAndShape(outOrt, &typeShape))
        defer { if let ts = typeShape { api.pointee.ReleaseTensorTypeAndShapeInfo(ts) } }
        var count: Int = 0
        try check(api.pointee.GetTensorShapeElementCount(typeShape, &count))
        let ptr = raw!.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
    
    private func check(_ st: OrtStatusPtr?) throws {
        if let s = st {
            defer { api.pointee.ReleaseStatus(s) }
            let cMsg = api.pointee.GetErrorMessage(s)
            let msg = cMsg.map { String(cString: $0) } ?? "Unknown ORT error"
            throw Errors.msg(msg)
        }
    }
}

#elseif canImport(CoreML)
import CoreML

actor Predictor {
    enum Errors: Error { case msg(String) }
    
    private let model: MLModel
    
    init(modelPath: String) async throws {
        let url = URL(fileURLWithPath: modelPath)
        let fm = FileManager.default
        
        if url.pathExtension == "mlmodel" {
            let compiledURL = try await MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } else if url.pathExtension == "mlmodelc" || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || (fm.fileExists(atPath: url.path, isDirectory: nil)) {
            self.model = try MLModel(contentsOf: url)
        } else {
            throw Errors.msg("Unsupported model file at path: \(modelPath)")
        }
    }
    
    func ioNames() throws -> (String, String) {
        let inName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"
        return (inName, outName)
    }
    
    func predictFloat(input: [Float], shape: [Int64], inputName: String, outputName: String) throws -> [Float] {
        let shapeNums = shape.map { NSNumber(value: $0) }
        let array = try MLMultiArray(shape: shapeNums, dataType: .float32)
        
        let elementCount = input.count
        let byteCount = elementCount * MemoryLayout<Float32>.stride
        _ = input.withUnsafeBytes { src in
            memcpy(array.dataPointer, src.baseAddress!, byteCount)
        }
        
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: array)])
        let out = try model.prediction(from: provider)
        
        guard let outValue = out.featureValue(for: outputName)?.multiArrayValue else {
            throw Errors.msg("Output feature not found: \(outputName)")
        }
        
        let count = outValue.count
        var result = [Float](repeating: 0, count: count)
        let bytes = count * MemoryLayout<Float32>.stride
        memcpy(&result, outValue.dataPointer, bytes)
        return result
    }
}

#else
actor Predictor {
    enum Errors: Error { case msg(String) }
    init(modelPath: String) async throws { throw Errors.msg("Predictor not supported on this platform") }
    func ioNames() throws -> (String, String) { throw Errors.msg("Predictor not supported on this platform") }
    func predictFloat(input: [Float], shape: [Int64], inputName: String, outputName: String) throws -> [Float] { throw Errors.msg("Predictor not supported on this platform") }
}
#endif

// MARK: - PredictorRegistry

actor PredictorRegistry {
    struct Entry: Sendable {
        let kind: PredictorKind
        let runtime: PredictRuntime
        let path: String
        let predictor: Predictor
    }
    
    private var byKind: [PredictorKind: Entry] = [:]
    
    func set(kind: PredictorKind, runtime: PredictRuntime, path: String, predictor: Predictor) {
        byKind[kind] = Entry(kind: kind, runtime: runtime, path: path, predictor: predictor)
    }
    
    func get(_ kind: PredictorKind) -> Predictor? { byKind[kind]?.predictor }
}

extension Application {
    private struct PredictorRegistryKey: StorageKey { typealias Value = PredictorRegistry }
    var predictors: PredictorRegistry {
        get { storage[PredictorRegistryKey.self] ?? { let r = PredictorRegistry(); storage[PredictorRegistryKey.self] = r; return r }() }
        set { storage[PredictorRegistryKey.self] = newValue }
    }
}
