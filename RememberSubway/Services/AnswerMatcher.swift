import Foundation

enum AnswerMatcher {
    private static let ignored = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    static func normalize(_ value: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        let scalars = normalized.unicodeScalars.filter { !ignored.contains($0) }
        var result = String(String.UnicodeScalarView(scalars)).lowercased()
        if result.hasSuffix("역") { result.removeLast() }
        return result
    }

    static func matches(_ answer: String, station: Station) -> Bool {
        let candidate = normalize(answer)
        guard !candidate.isEmpty else { return false }
        return station.acceptedAnswers.contains { normalize($0) == candidate }
    }

    static func initialConsonants(of value: String) -> String {
        let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
        return String(value.compactMap { character in
            guard let scalar = character.unicodeScalars.first else { return character }
            let code = Int(scalar.value)
            guard (0xAC00...0xD7A3).contains(code) else { return character }
            return initials[(code - 0xAC00) / 588]
        })
    }
}

