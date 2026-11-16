// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// What the user chose to install, sorted by kind before anything is read by WebKit.
enum ExtensionPackage: Equatable {
    /// A folder holding `manifest.json`.
    case folder(URL)
    /// A ZIP archive, read by WebKit as it is.
    case zip(Data)
    /// A Chrome CRX3 package: the ZIP after its header, and the identifier the header names.
    case crx(zip: Data, identifier: String?)

    /// Reads the folder or file at `url`. A CRX is unwrapped here; any other kind of file is refused.
    static func read(_ url: URL) throws -> ExtensionPackage {
        guard url.isFileURL else { throw ExtensionInstallError.unsupportedFile(name: url.lastPathComponent) }
        let url = url.absoluteURL.standardizedFileURL
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard FileManager.default.fileExists(atPath: url.appending(path: "manifest.json").path(percentEncoded: false)) else {
                throw ExtensionInstallError.noManifest(name: url.lastPathComponent)
            }
            return .folder(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ExtensionInstallError.unreadable(name: url.lastPathComponent)
        }
        if data.starts(with: CRX3.magic) {
            let package = try CRX3.unwrap(data, name: url.lastPathComponent)
            return .crx(zip: package.zip, identifier: package.identifier)
        }
        if data.starts(with: Self.zipMagic) {
            return .zip(data)
        }
        throw ExtensionInstallError.unsupportedFile(name: url.lastPathComponent)
    }

    /// A ZIP's local file header, which starts every archive WebKit can read.
    static let zipMagic = Data([0x50, 0x4B, 0x03, 0x04])
}

/// Chrome's CRX3 package: `Cr24`, the format version (3), the header's length, a `CrxFileHeader` protocol buffer, then
/// the ZIP. The header's `signed_header_data` holds a `SignedData` message whose `crx_id` is the extension's
/// identifier, 16 bytes that Chrome writes as 32 letters from `a` to `p`.
enum CRX3 {
    static let magic = Data("Cr24".utf8)

    struct Package: Equatable {
        let zip: Data
        let identifier: String?
    }

    static func unwrap(_ data: Data, name: String) throws -> Package {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, Data(bytes[0..<4]) == magic else { throw ExtensionInstallError.damagedCRX(name: name) }
        let version = littleEndian(bytes, at: 4)
        guard version == 3 else { throw ExtensionInstallError.unsupportedCRXVersion(name: name, version: Int(version)) }
        let headerLength = Int(littleEndian(bytes, at: 8))
        let zipStart = 12 + headerLength
        guard headerLength >= 0, zipStart <= bytes.count else { throw ExtensionInstallError.damagedCRX(name: name) }
        let zip = Data(bytes[zipStart...])
        guard zip.starts(with: ExtensionPackage.zipMagic) else { throw ExtensionInstallError.damagedCRX(name: name) }
        let header = Array(bytes[12..<zipStart])
        let signedData = ProtocolBuffer.field(10_000, in: header)
        let crxID = signedData.flatMap { ProtocolBuffer.field(1, in: $0) }
        return Package(zip: zip, identifier: crxID.flatMap(ExtensionIdentity.identifier(forCRXID:)))
    }

    private static func littleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
}

/// The few protocol buffer rules a CRX3 header needs: the first length-delimited field with a number, others skipped.
enum ProtocolBuffer {
    static func field(_ number: UInt64, in bytes: [UInt8]) -> [UInt8]? {
        var index = 0
        while index < bytes.count {
            guard let tag = varint(bytes, &index) else { return nil }
            switch tag & 0x7 {
            case 0:
                guard varint(bytes, &index) != nil else { return nil }
            case 1:
                index += 8
            case 2:
                guard let length = varint(bytes, &index), length <= UInt64(bytes.count - index) else { return nil }
                let end = index + Int(length)
                if tag >> 3 == number { return Array(bytes[index..<end]) }
                index = end
            case 5:
                index += 4
            default:
                return nil
            }
        }
        return nil
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}

/// Why an extension was not installed, worded for the alert that says so.
public enum ExtensionInstallError: LocalizedError, Equatable {
    case unsupportedFile(name: String)
    case noManifest(name: String)
    case unreadable(name: String)
    case damagedCRX(name: String)
    case unsupportedCRXVersion(name: String, version: Int)
    case alreadyInstalled(name: String)
    case differentExtension(name: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name):
            String(localized: "“\(name)” is not an extension. Choose a folder that holds a manifest.json file, or a .zip or .crx file.",
                   table: "SafiraWeb", bundle: .module, comment: "Extension install error; the argument is a file name")
        case .noManifest(let name):
            String(localized: "The folder “\(name)” has no manifest.json file. Choose the folder that holds the extension’s manifest.",
                   table: "SafiraWeb", bundle: .module, comment: "Extension install error; the argument is a folder name")
        case .unreadable(let name):
            String(localized: "Safira could not read “\(name)”.", table: "SafiraWeb", bundle: .module,
                   comment: "Extension install error; the argument is a file name")
        case .damagedCRX(let name):
            String(localized: "“\(name)” is not a valid CRX file.", table: "SafiraWeb", bundle: .module,
                   comment: "Extension install error; the argument is a file name")
        case .unsupportedCRXVersion(let name, let version):
            String(localized: "“\(name)” is a CRX\(version) file. Safira reads CRX3 files only.", table: "SafiraWeb",
                   bundle: .module, comment: "Extension install error; the arguments are a file name and a format version")
        case .alreadyInstalled(let name):
            String(localized: "“\(name)” is already installed. Remove it in Settings › Extensions to install it again.",
                   table: "SafiraWeb", bundle: .module, comment: "Extension install error; the argument is an extension's name")
        case .differentExtension(let name):
            String(localized: "This folder holds another extension than “\(name)”.", table: "SafiraWeb", bundle: .module,
                   comment: "Extension locate error; the argument is an extension's name")
        }
    }
}
