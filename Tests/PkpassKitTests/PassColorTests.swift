//
//  PassColorTests.swift
//  PkpassKitTests
//

import Testing
import Foundation
@testable import PkpassKit

struct PassColorTests {

    @Test func parsesRGBString() throws {
        let color = try #require(PassColor("rgb(20, 110, 200)"))
        #expect(abs(color.red - 20.0 / 255) < 0.001)
        #expect(abs(color.green - 110.0 / 255) < 0.001)
        #expect(abs(color.blue - 200.0 / 255) < 0.001)
    }

    @Test func parsesRGBWithoutSpaces() throws {
        let color = try #require(PassColor("rgb(255,0,0)"))
        #expect(color.css == "rgb(255, 0, 0)")
    }

    @Test func parsesHexLong() throws {
        let color = try #require(PassColor("#0a7d2c"))
        #expect(color.css == "rgb(10, 125, 44)")
    }

    @Test func parsesHexShort() throws {
        let color = try #require(PassColor("#fff"))
        #expect(color.css == "rgb(255, 255, 255)")
    }

    @Test func rejectsNilAndGarbage() {
        #expect(PassColor(nil) == nil)
        #expect(PassColor("") == nil)
        #expect(PassColor("not a color") == nil)
        #expect(PassColor("rgb(1,2)") == nil)
    }

    @Test func computesLightness() throws {
        #expect(try #require(PassColor("#ffffff")).isLight)
        #expect(!(try #require(PassColor("#000000")).isLight))
    }

    @Test func readableForegroundContrasts() throws {
        let darkBackground = try #require(PassColor("rgb(20, 30, 40)"))
        #expect(darkBackground.readableForeground.isLight) // white text on dark
        let lightBackground = try #require(PassColor("rgb(240, 240, 240)"))
        #expect(!lightBackground.readableForeground.isLight) // black text on light
    }

    @Test func emitsRGBA() throws {
        let color = try #require(PassColor("rgb(0, 0, 0)"))
        #expect(color.css(alpha: 0.5) == "rgba(0, 0, 0, 0.5)")
    }
}
