//
//  AlphabetSong.swift
//  MorserX
//
//  The alphabet song, sent in morse and sung at the same time.
//
//  A caveat worth stating in the file rather than burying in a commit: pitch
//  mnemonics work against copying, for the same reason counting dits does. On
//  the air there is one tone, and an operator who has learned "E is the high
//  short one" has to unlearn it. So this is deliberately not a copy drill. It's
//  a way in — hear that the letters exist, in an order you already know by
//  heart — and the pitch is meant to be taken away again. `fade` does that.
//

import Foundation
import Morse

enum AlphabetSong {

    /// C major, an octave above the piano's middle so the notes land in the
    /// range a sidetone lives in. Below about 400Hz a CW note starts to sound
    /// like a hum rather than a tone.
    enum Note: Float, CaseIterable {
        case C = 523.25
        case D = 587.33
        case E = 659.25
        case F = 698.46
        case G = 783.99
        case A = 880.00
    }

    /// The tune's phrasing, which is the actual mnemonic — most people can't
    /// recite the alphabet without it. The groups are the song's breaths:
    /// `ABCDEFG / HIJKLMNOP / QRS / TUV / WX / YZ`.
    static let phrases = ["abcdefg", "hijklmnop", "qrs", "tuv", "wx", "yz"]

    static var text: String { phrases.joined(separator: " ") }

    /// Which note each letter is sung on, in the common variant of the tune.
    ///
    /// L-M-N-O-P is the crowded bar everyone rushes: four letters on D and P on
    /// C, which is why it's the part people most often lose.
    static let notes: [Character: Note] = [
        "A": .C, "B": .C, "C": .G, "D": .G, "E": .A, "F": .A, "G": .G,
        "H": .F, "I": .F, "J": .E, "K": .E, "L": .D, "M": .D, "N": .D, "O": .D, "P": .C,
        "Q": .G, "R": .G, "S": .F,
        "T": .E, "U": .E, "V": .D,
        "W": .G, "X": .G,
        "Y": .F, "Z": .F
    ]

    /// The pitch for a letter, or nil to leave it on the plain sidetone.
    /// - Parameter fade: 0 sings it, 1 sends it flat. The crutch is meant to be
    ///   removed, so removing it is a setting rather than a rewrite.
    static func pitch(for character: Character, fade: Double = 0) -> Float? {
        guard fade < 1,
              let note = notes[Character(String(character).uppercased())]
        else { return nil }

        guard fade > 0 else { return note.rawValue }

        // Collapse the melody toward the sidetone as the fade comes up, so the
        // tune flattens instead of switching off in one step.
        let sidetone: Float = 600
        return note.rawValue + (sidetone - note.rawValue) * Float(fade)
    }
}
