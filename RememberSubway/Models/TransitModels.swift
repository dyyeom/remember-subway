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

struct RoutePattern: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case main, branch, loop }

    let id: String
    let lineID: String
    let name: String
    let kind: Kind
    let stationIDs: [String]
    let stationCodes: [String: String]?
}
