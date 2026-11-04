// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct DownloadPolicyTests {
    @Test func aTypeTheEngineCannotShowIsSaved() {
        #expect(DownloadPolicy.savesResponse(canShowType: false, contentDisposition: nil))
        #expect(DownloadPolicy.savesResponse(canShowType: false, contentDisposition: "inline"))
    }

    @Test func aTypeTheEngineCanShowIsShownUnlessTheServerMarksItAsAnAttachment() {
        #expect(!DownloadPolicy.savesResponse(canShowType: true, contentDisposition: nil))
        #expect(!DownloadPolicy.savesResponse(canShowType: true, contentDisposition: "inline; filename=\"a.pdf\""))
        #expect(DownloadPolicy.savesResponse(canShowType: true, contentDisposition: "attachment; filename=\"a.pdf\""))
        #expect(DownloadPolicy.savesResponse(canShowType: true, contentDisposition: "Attachment"))
        #expect(DownloadPolicy.savesResponse(canShowType: true, contentDisposition: " ATTACHMENT ;filename=a.txt"))
    }

    @Test func aDispositionThatMerelyMentionsAttachmentIsNotOne() {
        #expect(!DownloadPolicy.savesResponse(canShowType: true, contentDisposition: "inline; filename=\"attachment\""))
        #expect(!DownloadPolicy.savesResponse(canShowType: true, contentDisposition: "form-data; name=\"attachment\""))
    }
}

@Suite struct DownloadFileNameTests {
    @Test func aNameThatCannotLeaveTheFolderKeepsItsMeaning() {
        #expect(DownloadFileName.sanitized("report.pdf") == "report.pdf")
        #expect(DownloadFileName.sanitized("../../etc/passwd") == "_.._etc_passwd")
        #expect(DownloadFileName.sanitized("a:b/c.txt") == "a_b_c.txt")
        #expect(DownloadFileName.sanitized("tab\tname\n.txt") == "tab_name_.txt")
    }

    @Test func aLeadingDotAndAnEmptyNameAreReplaced() {
        #expect(DownloadFileName.sanitized(".hidden") == "hidden")
        #expect(DownloadFileName.sanitized("...") == "download")
        #expect(DownloadFileName.sanitized("   ") == "download")
        #expect(DownloadFileName.sanitized("") == "download")
    }

    @Test func aTakenNameGetsTheNextFreeNumberBeforeItsExtension() {
        #expect(DownloadFileName.unique("a.zip") { _ in false } == "a.zip")
        #expect(DownloadFileName.unique("a.zip") { ["a.zip"].contains($0) } == "a 2.zip")
        #expect(DownloadFileName.unique("a.zip") { ["a.zip", "a 2.zip"].contains($0) } == "a 3.zip")
        #expect(DownloadFileName.unique("Makefile") { ["Makefile"].contains($0) } == "Makefile 2")
        #expect(DownloadFileName.unique("a.tar.gz") { ["a.tar.gz"].contains($0) } == "a.tar 2.gz")
    }
}

@Suite struct DownloadRecordTests {
    private func record(received: Int64, total: Int64?, state: DownloadState = .active) -> DownloadRecord {
        DownloadRecord(sourceURL: URL(string: "https://example.com/a.zip")!, fileName: "a.zip", state: state,
                       receivedBytes: received, totalBytes: total, startedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func theFractionIsTheShareOfTheKnownSizeAndNilWhenTheSizeIsUnknown() {
        #expect(record(received: 25, total: 100).fractionCompleted == 0.25)
        #expect(record(received: 150, total: 100).fractionCompleted == 1)
        #expect(record(received: 25, total: nil).fractionCompleted == nil)
        #expect(record(received: 25, total: 0).fractionCompleted == nil)
    }

    @Test func onlyAStoppedTransferCanBeRetried() {
        #expect(record(received: 0, total: nil, state: .active).canRetry == false)
        #expect(record(received: 0, total: nil, state: .completed).canRetry == false)
        #expect(record(received: 0, total: nil, state: .failed).canRetry)
        #expect(record(received: 0, total: nil, state: .cancelled).canRetry)
    }

    @Test func aSavedFileIsFoundThroughItsBookmarkEvenAfterItMovesAndNilOnceItIsGone() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "a.zip")
        try Data("x".utf8).write(to: file)
        var saved = record(received: 1, total: 1, state: .completed)
        saved.fileBookmark = try file.bookmarkData()

        #expect(saved.savedFileURL()?.lastPathComponent == "a.zip")
        let moved = folder.appending(path: "b.zip")
        try FileManager.default.moveItem(at: file, to: moved)
        #expect(saved.savedFileURL()?.lastPathComponent == "b.zip")
        try FileManager.default.removeItem(at: moved)
        #expect(saved.savedFileURL() == nil)
        #expect(record(received: 1, total: 1, state: .completed).savedFileURL() == nil)
    }
}
