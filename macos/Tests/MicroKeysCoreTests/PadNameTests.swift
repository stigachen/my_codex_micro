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

    /// Review #15: a nameless pad stores nil, and the generic name is picked
    /// in whatever language is current when it is shown.
    @Test func genericNameFollowsTheLanguage() {
        let stored = PadName.display("  ")
        #expect(stored == nil)
        #expect(PadName.label(stored, language: .zhHans) == "Work Louder 键盘")
        #expect(PadName.label(stored, language: .en) == "Work Louder pad")
        #expect(PadName.label("Creator Micro 2", language: .en) == "Creator Micro 2")
    }
}
