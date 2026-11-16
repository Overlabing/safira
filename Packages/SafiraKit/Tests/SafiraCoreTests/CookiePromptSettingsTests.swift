// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct CookiePromptSettingsTests {
    @Test func aNewProfileRejectsPromptsEverywhere() {
        let settings = WebContentSettings().cookiePrompts
        #expect(settings.isRejecting == true)
        #expect(settings.exceptions == [])
        #expect(settings.answers(onHost: "news.example") == true)
    }

    @Test func anExceptionCoversTheSiteAndItsSubdomainsOnly() {
        var settings = CookiePromptSettings()
        settings.addException(forHost: "WWW.Example.com")

        #expect(settings.exceptions == ["example.com"])
        #expect(settings.answers(onHost: "example.com") == false)
        #expect(settings.answers(onHost: "www.example.com") == false)
        #expect(settings.answers(onHost: "shop.example.com") == false)
        #expect(settings.answers(onHost: "notexample.com") == true)
        #expect(settings.answers(onHost: "example.org") == true)

        settings.removeException("example.com")
        #expect(settings.answers(onHost: "example.com") == true)
    }

    @Test func theSwitchOffAnswersNothing() {
        let settings = CookiePromptSettings(isRejecting: false)
        #expect(settings.answers(onHost: "example.com") == false)
        #expect(settings.answers(onHost: nil) == false)
    }

    @Test func theSettingsSurviveEncoding() throws {
        let settings = WebContentSettings(cookiePrompts: CookiePromptSettings(isRejecting: false, exceptions: ["a.test"]))
        let decoded = try JSONDecoder().decode(WebContentSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}
