// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraWeb
import Testing

/// #122: pinching zooms a page and a two-finger swipe goes back and forward, on every page Safira builds.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct PageGestureTests {
    @Test func aTabOfAProfileAllowsPinchAndSwipe() async {
        let profile = ProfileID(rawValue: UUID())
        do {
            let page = ProfileWebContext(profileID: profile).makePage(for: TabID())
            #expect(page.webView.allowsMagnification == true)
            #expect(page.webView.allowsBackForwardNavigationGestures == true)
            #expect(page.pageZoom == 1)
            page.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aTabOfAPrivateWindowAllowsPinchAndSwipe() {
        let page = ProfileWebContext(privateWindowOf: ProfileID(rawValue: UUID())).makePage(for: TabID())
        #expect(page.webView.allowsMagnification == true)
        #expect(page.webView.allowsBackForwardNavigationGestures == true)
        page.pageZoom = 1.25
        #expect(page.webView.pageZoom == 1.25)
        page.close()
    }
}
