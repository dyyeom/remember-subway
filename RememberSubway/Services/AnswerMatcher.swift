import Foundation

enum AnswerMatcher {
    /// 역명의 가운뎃점(U+00B7) 대신 입력될 수 있는 문자들.
    /// 한국어 키보드(특히 천지인)는 가운뎃점을 아래아 `ㆍ`(U+318D)로 넣는데, 이는 글자로 분류돼
    /// 문장부호 제거에 걸리지 않으므로 직접 지정한다. 나머지는 문장부호·기호지만 명시해 둔다.
    static let middleDotVariants: [Unicode.Scalar] = [
        "\u{00B7}", // · MIDDLE DOT (역명 표기)
        "\u{318D}", // ㆍ HANGUL LETTER ARAEA (천지인 등)
        "\u{119E}", // ᆞ HANGUL JUNGSEONG ARAEA (조합형 아래아)
        "\u{2027}", // ‧ HYPHENATION POINT
        "\u{30FB}", // ・ KATAKANA MIDDLE DOT
        "\u{FF65}", // ･ HALFWIDTH KATAKANA MIDDLE DOT
        "\u{2022}", // • BULLET
        "\u{2219}", // ∙ BULLET OPERATOR
        "\u{22C5}"  // ⋅ DOT OPERATOR
    ]

    private static let ignored = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
        .union(CharacterSet(middleDotVariants))

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

