// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Test func zoomStepsAreSafarisFromFiftyToThreeHundredPercent() {
    var zoom = PageZoom.actualSize
    var larger: [String] = []
    while let next = zoom.zoomedIn {
        zoom = next
        larger.append(zoom.percentage)
    }
    #expect(larger == ["115%", "125%", "150%", "175%", "200%", "250%", "300%"])
    zoom = .actualSize
    var smaller: [String] = []
    while let next = zoom.zoomedOut {
        zoom = next
        smaller.append(zoom.percentage)
    }
    #expect(smaller == ["85%", "75%", "50%"])
    #expect(PageZoom.actualSize.percentage == "100%")
    #expect(PageZoom.actualSize.isActualSize)
    #expect(PageZoom(factor: 1.15).isActualSize == false)
}

@Test func aFactorBetweenTwoStepsSnapsToTheNearest() {
    #expect(PageZoom(factor: 1.22).factor == 1.25)
    #expect(PageZoom(factor: 9).factor == 3)
    #expect(PageZoom(factor: 0.1).factor == 0.5)
}

@Test func aZoomBelongsToTheHostWhateverTheSchemePortOrPath() {
    #expect(ZoomSite(URL(string: "https://News.Example.com/a?b=1")!)?.host == "news.example.com")
    #expect(ZoomSite(URL(string: "http://news.example.com:8080/")!) == ZoomSite(URL(string: "https://news.example.com/x")!))
    #expect(ZoomSite(URL(string: "https://example.com/")!) != ZoomSite(URL(string: "https://www.example.com/")!))
    #expect(ZoomSite(URL(string: "file:///Users/me/page.html")!) == nil)
    #expect(ZoomSite(URL(string: "about:blank")!) == nil)
    #expect(ZoomSite(nil) == nil)
}
