// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
@testable import SafiraWeb
import Testing

/// What a chosen folder or file is, and the identifier an install gets: the manifest `key`'s, else a CRX3 header's,
/// else a UUID made at install. Every CRX here is built by the test.
@Suite struct ExtensionPackageTests {
    static let ascending: [UInt8] = Array(0x00...0x0F)
    static let high: [UInt8] = Array(0xF0...0xFF)
    /// Not a real archive, only its signature: what the reader checks before WebKit reads the rest.
    static let zipLike = ExtensionPackage.zipMagic + Data("rest of the archive".utf8)

    @Test func theIdentifierOfACRX3ComesFromItsHeaderInChromesLetters() throws {
        let first = try CRX3.unwrap(Self.crx(zip: Self.zipLike, crxID: Self.ascending), name: "a.crx")
        #expect(first.identifier == "aaabacadaeafagahaiajakalamanaoap")
        #expect(first.zip == Self.zipLike)
        let second = try CRX3.unwrap(Self.crx(zip: Self.zipLike, crxID: Self.high), name: "b.crx")
        #expect(second.identifier == "papbpcpdpepfpgphpipjpkplpmpnpopp")
    }

    @Test func aCRX3WithoutSignedHeaderDataNamesNoIdentifier() throws {
        let package = try CRX3.unwrap(Self.crx(zip: Self.zipLike, crxID: nil), name: "a.crx")
        #expect(package.identifier == nil)
        #expect(package.zip == Self.zipLike)
        #expect(ExtensionIdentity.identifier(forCRXID: [1, 2, 3]) == nil)
    }

    @Test func theManifestKeyWinsOverTheCRXHeader() {
        let id = ExtensionIdentity.identifier(forManifest: ["key": "c2FmaXJhLXRlc3Qta2V5"],
                                              crxIdentifier: "aaabacadaeafagahaiajakalamanaoap")
        #expect(id == "pfikphmpnbnmihdgfbljkjgfnamcpjme")
        #expect(ExtensionIdentity.identifier(forManifest: ["name": "No key"], crxIdentifier: "aaabacadaeafagahaiajakalamanaoap")
            == "aaabacadaeafagahaiajakalamanaoap")
    }

    @Test func withNeitherKeyNorCRXAnInstallMakesAUUID() throws {
        let first = ExtensionIdentity.identifier(forManifest: ["name": "No key"])
        let second = ExtensionIdentity.identifier(forManifest: ["name": "No key"])
        #expect(first != second)
        #expect(first == first.lowercased())
        #expect(UUID(uuidString: first) != nil)
    }

    @Test func aCRX2IsRefusedByName() {
        var data = CRX3.magic
        data += Self.littleEndian(2) + Self.littleEndian(0) + Self.littleEndian(0) + Self.zipLike
        #expect(throws: ExtensionInstallError.unsupportedCRXVersion(name: "old.crx", version: 2)) {
            try CRX3.unwrap(data, name: "old.crx")
        }
    }

    @Test func aCRXWhoseHeaderRunsPastTheEndIsRefused() {
        var data = CRX3.magic
        data += Self.littleEndian(3) + Self.littleEndian(1_000) + Data([1, 2, 3])
        #expect(throws: ExtensionInstallError.damagedCRX(name: "cut.crx")) {
            try CRX3.unwrap(data, name: "cut.crx")
        }
    }

    @Test func aFolderAZipAndACRXAreReadAndAnythingElseIsRefused() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "safira-package-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Extension", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "manifest.json"))
        let empty = root.appending(path: "Empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let zip = root.appending(path: "extension.zip")
        try Self.zipLike.write(to: zip)
        let crx = root.appending(path: "extension.crx")
        try Self.crx(zip: Self.zipLike, crxID: Self.ascending).write(to: crx)
        let text = root.appending(path: "notes.txt")
        try Data("hello".utf8).write(to: text)

        #expect(try ExtensionPackage.read(folder) == .folder(folder))
        #expect(try ExtensionPackage.read(zip) == .zip(Self.zipLike))
        #expect(try ExtensionPackage.read(crx) == .crx(zip: Self.zipLike, identifier: "aaabacadaeafagahaiajakalamanaoap"))
        #expect(throws: ExtensionInstallError.unsupportedFile(name: "notes.txt")) { try ExtensionPackage.read(text) }
        #expect(throws: ExtensionInstallError.noManifest(name: "Empty")) { try ExtensionPackage.read(empty) }
        #expect(throws: ExtensionInstallError.unsupportedFile(name: "extension")) {
            try ExtensionPackage.read(URL(string: "https://example.com/extension")!)
        }
    }

    @Test func thePermissionSheetWordsAllWebsitesAsSafariDoes() {
        let lines = ExtensionPermissionWording.lines(permissions: ["unlimitedStorage", "storage", "nativeMessaging", "alarms",
                                                                   "someFutureAPI"],
                                                     matchPatterns: ["https://*/*"], hasAccessToAllHosts: true)
        #expect(lines == [
            "Can read and modify webpages on all websites",
            "Can run tasks on a schedule",
            "Can exchange messages with apps on this Mac",
            "Can use “someFutureAPI”",
            "Can store data on this Mac",
        ])
    }

    @Test func somePagesAreNamedByTheirHost() {
        #expect(ExtensionPermissionWording.lines(permissions: [], matchPatterns: ["https://github.com/*", "http://localhost/*"],
                                                 hasAccessToAllHosts: false)
            == ["Can read and modify webpages on github.com and localhost"])
        #expect(ExtensionPermissionWording.hosts(["https://a.com/*", "*://*.b.org/path/*", "https://a.com/other"])
            == ["a.com", "*.b.org"])
        let many = ["a.com", "b.com", "c.com", "d.com", "e.com", "f.com"].map { "https://\($0)/*" }
        let line = ExtensionPermissionWording.lines(permissions: [], matchPatterns: many, hasAccessToAllHosts: false)[0]
        #expect(line.hasPrefix("Can read and modify webpages on a.com"))
        #expect(line.hasSuffix(" and 2 more websites"))
        #expect(ExtensionPermissionWording.lines(permissions: [], matchPatterns: [], hasAccessToAllHosts: false) == [])
    }

    // MARK: Helpers

    /// A CRX3 file: `Cr24`, version 3, the header's length, a header holding one RSA proof (skipped by the reader)
    /// and, when given, `signed_header_data` with the `crx_id`, then the ZIP.
    static func crx(zip: Data, crxID: [UInt8]?) -> Data {
        let proof: [UInt8] = [0x0A, 4, 1, 2, 3, 4, 0x12, 3, 9, 9, 9]
        var header: [UInt8] = [0x12, UInt8(proof.count)] + proof
        if let crxID {
            let signed: [UInt8] = [0x0A, UInt8(crxID.count)] + crxID
            header += varint(10_000 << 3 | 2) + varint(UInt64(signed.count)) + signed
        }
        var data = CRX3.magic
        data += littleEndian(3) + littleEndian(UInt32(header.count))
        data += Data(header)
        data += zip
        return data
    }

    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    static func littleEndian(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
    }
}
