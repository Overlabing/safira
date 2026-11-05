// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import Testing

@Suite struct LinkRuleEventTests {
    @Test func aSkippedRuleIsWrittenWithItsPositionAndReasonOnly() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: true)

        logger.record(.linkRuleSkipped(index: 2, reason: .unknownProfile))
        logger.record(.linkRuleSkipped(index: 0, reason: .ambiguousSpace))
        await logger.sink.flush()

        #expect(messages(in: directory) == [
            "notice [links] link-rule-skipped index=2 reason=unknownProfile",
            "notice [links] link-rule-skipped index=0 reason=ambiguousSpace",
        ])
    }

    @Test func anInvalidRulesFileIsWrittenAsAnErrorWithTheKindOfProblemOnly() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: true)

        logger.record(.linkRulesInvalid(.invalidField))
        await logger.sink.flush()

        #expect(messages(in: directory) == ["error [links] link-rules-invalid problem=invalidField"])
    }

    @Test func neitherEventIsPrivateSoTheyReachOnlyTheSystemLogWhileDebugModeIsOff() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: false, systemLog: systemLog)

        logger.record(.linkRuleSkipped(index: 0, reason: .unknownSpace))
        logger.record(.linkRulesInvalid(.notJSON))
        await logger.sink.flush()

        #expect(systemLog.lines == [
            .init(category: "links", type: .default, redacted: "link-rule-skipped index=0 reason=unknownSpace", full: nil),
            .init(category: "links", type: .error, redacted: "link-rules-invalid problem=notJSON", full: nil),
        ])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
