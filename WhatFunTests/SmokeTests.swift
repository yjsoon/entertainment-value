import Testing
@testable import WhatFun

@Suite("Entertainment Value smoke tests")
struct SmokeTests {
    @Test("The test target loads the app module")
    func moduleLoads() {
        #expect(Config.applicationName == "EVal")
    }
}
