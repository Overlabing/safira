// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import Testing

@Suite struct LinkRuleEventTests {
    @Test func aSkippedRuleIsWrittenWithItsPositionAndReasonOnly() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true,
                                      clock: { Date(timeIntervalSince1970: 1_793_700_000.25) })

        logger.record(.linkRuleSkipped(index: 2, reason: .unknownProfile))
        logger.record(.linkRuleSkipped(index: 0, reason: .ambiguousSpace))
        logger.flush()

        #expect(allLines(in: directory) == [
            "2026-11-03T10:00:00.250Z notice link-rule-skipped index=2 reason=unknownProfile",
            "2026-11-03T10:00:00.250Z notice link-rule-skipped index=0 reason=ambiguousSpace",
        ])
    }

    @Test func anInvalidRulesFileIsWrittenAsAnErrorWithTheKindOfProblemOnly() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true,
                                      clock: { Date(timeIntervalSince1970: 1_793_700_000.25) })

        logger.record(.linkRulesInvalid(.invalidField))
        logger.flush()

        #expect(allLines(in: directory) == ["2026-11-03T10:00:00.250Z error link-rules-invalid problem=invalidField"])
    }

    @Test func neitherEventCarriesSiteInformationOrWritesAnythingWhileDebugModeIsOff() {
        #expect(!DiagnosticEvent.linkRuleSkipped(index: 0, reason: .unknownSpace).carriesSiteInformation)
        #expect(!DiagnosticEvent.linkRulesInvalid(.notJSON).carriesSiteInformation)

        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory)
        logger.record(.linkRulesInvalid(.notJSON))
        logger.flush()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
