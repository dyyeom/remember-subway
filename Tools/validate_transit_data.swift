#!/usr/bin/env swift
import Foundation

struct Catalog: Decodable {
    struct Item: Decodable { let id: String }
    struct Source: Decodable { let title: String; let url: URL }
    struct Line: Decodable { let id: String; let regionID: String; let operatorID: String; let colorHex: String }
    struct Pattern: Decodable { let id: String; let lineID: String; let kind: String; let stationIDs: [String]; let stationCodes: [String: String]? }
    let schemaVersion: Int
    let contentVersion: String
    let dataAsOf: String
    let sources: [Source]
    let regions: [Item]
    let operators: [Item]
    let stations: [Item]
    let lines: [Line]
    let routePatterns: [Pattern]
}

let path = CommandLine.arguments.dropFirst().first ?? "RememberSubway/Resources/transit_data.json"
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let catalog = try JSONDecoder().decode(Catalog.self, from: data)
var errors: [String] = []
func checkUnique(_ ids: [String], _ label: String) {
    if Set(ids).count != ids.count { errors.append("중복 \(label) ID") }
}
checkUnique(catalog.regions.map(\.id), "지역")
checkUnique(catalog.operators.map(\.id), "운영기관")
checkUnique(catalog.stations.map(\.id), "역")
checkUnique(catalog.lines.map(\.id), "노선")
checkUnique(catalog.routePatterns.map(\.id), "계통")
if catalog.contentVersion.isEmpty { errors.append("콘텐츠 버전 누락") }
if ISO8601DateFormatter().date(from: "\(catalog.dataAsOf)T00:00:00Z") == nil { errors.append("기준일 오류") }
if catalog.sources.isEmpty || catalog.sources.contains(where: { $0.title.isEmpty || $0.url.host == nil }) {
    errors.append("출처 누락 또는 오류")
}
let regions = Set(catalog.regions.map(\.id)), operators = Set(catalog.operators.map(\.id))
let lines = Set(catalog.lines.map(\.id)), stations = Set(catalog.stations.map(\.id))
for line in catalog.lines {
    if !regions.contains(line.regionID) || !operators.contains(line.operatorID) { errors.append("잘못된 노선 참조: \(line.id)") }
    if line.colorHex.count != 6 || !line.colorHex.allSatisfy(\.isHexDigit) { errors.append("잘못된 노선색: \(line.id)") }
}
for pattern in catalog.routePatterns {
    if !lines.contains(pattern.lineID) { errors.append("잘못된 노선 참조: \(pattern.id)") }
    if pattern.stationIDs.count < 2 || pattern.stationIDs.contains(where: { !stations.contains($0) }) { errors.append("잘못된 역 경로: \(pattern.id)") }
    if zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains(where: ==) { errors.append("연속 중복 역: \(pattern.id)") }
    if pattern.stationCodes?.keys.contains(where: { !pattern.stationIDs.contains($0) }) == true { errors.append("잘못된 역 번호 참조: \(pattern.id)") }
}
func contains(_ candidate: [String], asContiguousSubsequenceOf route: [String]) -> Bool {
    guard candidate.count < route.count else { return false }
    for start in 0...(route.count - candidate.count) {
        if Array(route[start..<(start + candidate.count)]) == candidate { return true }
    }
    return false
}
for line in catalog.lines {
    let mainPatterns = catalog.routePatterns.filter { $0.lineID == line.id && $0.kind == "main" }
    for pattern in mainPatterns where mainPatterns.contains(where: {
        $0.id != pattern.id && contains(pattern.stationIDs, asContiguousSubsequenceOf: $0.stationIDs)
    }) {
        errors.append("중복 부분 계통: \(pattern.id)")
    }
}
if errors.isEmpty { print("OK: \(catalog.lines.count)개 노선, \(catalog.stations.count)개 역, \(catalog.routePatterns.count)개 계통") }
else { errors.forEach { fputs("ERROR: \($0)\n", stderr) }; exit(1) }
