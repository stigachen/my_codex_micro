import Testing
@testable import MicroKeysCore

@Suite struct PadNameTests {
    @Test func tidiesProductStrings() {
        #expect(PadName.display("Codex Micro") == "Codex Micro")
        #expect(PadName.display("Codex Micro #1") == "Codex Micro")   // over Bluetooth
        #expect(PadName.display("Creator Micro 2") == "Creator Micro 2")
        #expect(PadName.display("  Creator Micro 2 #12 ") == "Creator Micro 2")
        #expect(PadName.display("#1") == "#1")                        // nothing to strip before it
        #expect(PadName.display("") == nil)
        #expect(PadName.display("   ") == nil)
        #expect(PadName.display(nil) == nil)
    }
}
