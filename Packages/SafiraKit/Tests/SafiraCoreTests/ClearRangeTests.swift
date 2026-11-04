// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct ClearRangeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theLastHourStartsAnHourAgo() {
        #expect(ClearRange.lastHour.start(now: now) == Date(timeIntervalSince1970: 1_799_996_400))
    }

    @Test func theLastDayStartsADayAgo() {
        #expect(ClearRange.lastDay.start(now: now) == Date(timeIntervalSince1970: 1_799_913_600))
    }

    @Test func allTimeReachesBackToTheBeginningOfTime() {
        #expect(ClearRange.allTime.start(now: now) == .distantPast)
    }

    @Test func theRangesAreOfferedFromTheShortestToTheLongest() {
        #expect(ClearRange.allCases == [.lastHour, .lastDay, .allTime])
    }
}
