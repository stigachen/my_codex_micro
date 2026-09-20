import Testing
@testable import MicroKeysCore

@Suite struct KeyChordTests {
    @Test func rightModifiersOnly() throws {
        let c = try KeyChord.parse("rctrl+rshift")
        #expect(c.key == nil)
        #expect(c.modifiers.map(\.keyCode) == [0x3E, 0x3C])
        #expect(c.allFlags == KeyTable.flagControl | KeyTable.flagShift | KeyTable.devRCtrl | KeyTable.devRShift)
    }

    @Test func modifiersPlusKeyCaseAndSpaces() throws {
        let c = try KeyChord.parse(" Cmd + Shift + 4 ")
        #expect(c.modifiers.map(\.name) == ["cmd", "shift"])
        #expect(c.key?.keyCode == 0x15)
    }

    @Test func symbolsAndAliases() throws {
        #expect(try KeyChord.parse("⌘+⇧+esc").key?.keyCode == 0x35)
        #expect(try KeyChord.parse("right_control").modifiers.first?.keyCode == 0x3E)
        #expect(try KeyChord.parse("f13").key?.keyCode == 0x69)
        #expect(try KeyChord.parse("fn").modifiers.first?.flag == KeyTable.flagFn)
    }

    @Test func mediaKeys() throws {
        let up = try KeyChord.parse("volumeup")
        #expect(up.key?.mediaKey == .soundUp)
        #expect(up.modifiers.isEmpty)
        let fine = try KeyChord.parse("shift+option+volumedown")
        #expect(fine.key?.mediaKey == .soundDown)
        #expect(fine.modifiers.map(\.name) == ["shift", "option"])
        #expect(try KeyChord.parse("mute").key?.mediaKey == .mute)
        #expect(try KeyChord.parse("playpause").key?.mediaKey == .play)
        #expect(try KeyChord.parse("f13").key?.mediaKey == nil)
        #expect(throws: KeyChord.ParseError.tooManyKeys("volumeup", "volumedown")) { try KeyChord.parse("volumeup+volumedown") }
    }

    @Test func errors() {
        #expect(throws: KeyChord.ParseError.empty) { try KeyChord.parse("") }
        #expect(throws: KeyChord.ParseError.emptyToken) { try KeyChord.parse("cmd++a") }
        #expect(throws: KeyChord.ParseError.unknownKey("bogus")) { try KeyChord.parse("cmd+bogus") }
        #expect(throws: KeyChord.ParseError.duplicateModifier("command")) { try KeyChord.parse("cmd+command+a") }
        #expect(throws: KeyChord.ParseError.tooManyKeys("a", "b")) { try KeyChord.parse("a+b") }
    }
}
