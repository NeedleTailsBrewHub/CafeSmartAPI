//
//  Data+Extension.swift
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

/// Extension to add utility methods to Data instances.
///
/// This extension provides convenient methods for working with Data objects,
/// including file size formatting and hexadecimal conversion utilities.
/// These utilities are commonly used in the NeedleTail system for handling
/// binary data, cryptographic operations, and file management.
///
/// ## Features
/// - **File Size Formatting**: Human-readable file size strings
/// - **Hexadecimal Conversion**: Convert between Data and hex strings
/// - **Binary Data Handling**: Utilities for cryptographic and binary operations
///
/// ## Usage
/// ```swift
/// let data = someBinaryData
///
/// // Get human-readable file size
/// let sizeString = data.fileSize // "1.25 MB"
///
/// // Convert to hex string
/// let hexString = data.hexString // "48656c6c6f"
///
/// // Convert from hex string
/// let newData = Data(hex: "48656c6c6f")
/// ```
extension Data {

  /**
   * Returns a human-readable string representation of the data size.
   *
   * This computed property converts the byte count to the most appropriate
   * unit (bytes, KB, MB, or GB) and formats it with appropriate precision.
   *
   * ## Size Ranges
   * - **< 1 KB**: Displayed in bytes
   * - **1 KB - 1 MB**: Displayed in kilobytes (KB)
   * - **1 MB - 1 GB**: Displayed in megabytes (MB)
   * - **≥ 1 GB**: Displayed in gigabytes (GB)
   *
   * ## Examples
   * - 512 bytes → "512 bytes"
   * - 1536 bytes → "1.50 KB"
   * - 2097152 bytes → "2.00 MB"
   * - 3221225472 bytes → "3.00 GB"
   *
   * - Returns: A formatted string representing the data size
   */
  public var fileSize: String {
    let byteCount = self.count

    if byteCount < 1024 {
      // Size is in bytes
      return "\(byteCount) bytes"
    } else if byteCount < 1024 * 1024 {
      // Size is in kilobytes
      let fileSizeInKB = Double(byteCount) / 1024.0
      return String(format: "%.2f KB", fileSizeInKB)
    } else if byteCount < 1024 * 1024 * 1024 {
      // Size is in megabytes
      let fileSizeInMB = Double(byteCount) / (1024.0 * 1024.0)
      return String(format: "%.2f MB", fileSizeInMB)
    } else {
      // Size is in gigabytes
      let fileSizeInGB = Double(byteCount) / (1024.0 * 1024.0 * 1024.0)
      return String(format: "%.2f GB", fileSizeInGB)
    }
  }

  /**
   * Converts the Data instance to a hexadecimal string.
   *
   * This computed property converts each byte in the Data to its
   * two-digit hexadecimal representation and joins them together.
   *
   * ## Format
   * Each byte is represented as two lowercase hexadecimal digits (0-9, a-f).
   * No separators or prefixes are added.
   *
   * ## Examples
   * - Data([72, 101, 108, 108, 111]) → "48656c6c6f"
   * - Data([0, 255, 16]) → "00ff10"
   *
   * - Returns: A string representing the hexadecimal values of the data
   */
  var hexString: String {
    return self.map { String(format: "%02hhx", $0) }.joined()
  }

  /**
   * Initializes a Data instance from a hexadecimal string.
   *
   * This initializer converts a hexadecimal string back to binary data.
   * It supports both uppercase and lowercase hex digits and requires
   * an even number of characters.
   *
   * ## Requirements
   * - The hex string must have an even number of characters
   * - All characters must be valid hexadecimal digits (0-9, a-f, A-F)
   *
   * ## Examples
   * - "48656c6c6f" → Data([72, 101, 108, 108, 111])
   * - "00FF10" → Data([0, 255, 16])
   * - "1A2B3C" → Data([26, 43, 60])
   *
   * ## Invalid Inputs
   * - "123" (odd number of characters) → nil
   * - "12G3" (invalid hex digit) → nil
   * - "12 34" (spaces not allowed) → nil
   *
   * - Parameter hex: A string representing hexadecimal values
   * - Returns: A Data instance if the conversion is successful, nil otherwise
   */
  init?(hex: String) {
    var data = Data()
    var tempHex = hex

    // Ensure the hex string has an even number of characters
    if tempHex.count % 2 != 0 {
      return nil
    }

    // Convert each pair of hex characters to a byte
    while !tempHex.isEmpty {
      let startIndex = tempHex.startIndex
      let endIndex = tempHex.index(startIndex, offsetBy: 2)
      let hexPair = String(tempHex[startIndex..<endIndex])
      guard let byte = UInt8(hexPair, radix: 16) else {
        return nil
      }
      data.append(byte)
      tempHex.removeSubrange(startIndex..<endIndex)
    }

    self = data
  }
}
