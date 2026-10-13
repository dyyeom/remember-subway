import Foundation

struct TransitCatalog: Codable, Sendable {
    let schemaVersion: Int
    let contentVersion: String
    let challengePoolVersion: String
    let dataAsOf: String
    let sources: [CatalogSource]
    let regions: [Region]
    let operators: [TransitOperator]
    let stations: [Station]
    let lines: [Line]
    let routePatterns: [RoutePattern]

    static let empty = TransitCatalog(
        schemaVersion: 1,
        contentVersion: "empty",
        challengePoolVersion: "empty",
        dataAsOf: "",
        sources: [], regions: [], operators: [], stations: [], lines: [], routePatterns: []
    )

    var stationByID: [String: Station] { Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) }) }
    var lineByID: [String: Line] { Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) }) }

    func lines(in region: Region) -> [Line] {
        lines.filter { $0.regionID == region.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func patterns(for line: Line) -> [RoutePattern] {
        routePatterns.filter { $0.lineID == line.id }
    }
}

struct CatalogSource: Codable, Hashable, Sendable {
    let title: String
    let url: URL
}

struct Region: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int
}

struct TransitOperator: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct Station: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let fullName: String?
    let aliases: [String]

    var acceptedAnswers: [String] { [name, fullName].compactMap { $0 } + aliases }
}

struct Line: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let regionID: String
    let operatorID: String
    let name: String
    let shortName: String
    let colorHex: String
    let sortOrder: Int
}

extension Line {
    /// 노선 칩처럼 좁은 자리에 쓰는 짧은 이름. 전체 이름은 VoiceOver·제목에 그대로 쓴다.
    var chipName: String { Self.chipName(for: name) }

    /// - "서울 2호선"·"부산 1호선" 같은 '<지역> N호선'은 "N호선"
    /// - "인천 N호선"은 수도권에서 서울 노선과 구분되도록 "인천N"
    /// - 그 밖에 '선'으로 끝나는 이름은 끝의 '선'을 뗀다(수인분당선 → 수인분당). 두 글자 이하는 그대로 둔다.
    /// - 수도권 경전철 브랜드 이름은 `chipNameOverrides`의 약칭을 쓴다(김포골드라인 → 김포골드).
    static func chipName(for name: String) -> String {
        if let override = chipNameOverrides[name] { return override }
        let parts = name.split(separator: " ")
        if parts.count == 2, parts[1].hasSuffix("호선") {
            let number = parts[1].dropLast(2)
            if !number.isEmpty, number.allSatisfy(\.isNumber) {
                return parts[0] == "인천" ? "인천\(number)" : String(parts[1])
            }
        }
        if name.hasSuffix("선"), name.count > 2 {
            return String(name.dropLast())
        }
        return name
    }

    /// '선'으로 끝나지 않는 긴 노선 이름의 칩 약칭.
    static let chipNameOverrides: [String: String] = [
        "김포골드라인": "김포골드",
        "용인에버라인": "에버라인",
        "의정부경전철": "의정부"
    ]
}

struct RoutePattern: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case main, branch, loop }

    let id: String
    let lineID: String
    let name: String
    let kind: Kind
    let stationIDs: [String]
    let stationCodes: [String: String]?
}
