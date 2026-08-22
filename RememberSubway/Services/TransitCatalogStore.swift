import Foundation

@MainActor
final class TransitCatalogStore: ObservableObject {
    @Published private(set) var catalog: TransitCatalog = .empty
    @Published private(set) var loadingError: String?

    init(bundle: Bundle = .main) {
        do {
            catalog = try Self.load(from: bundle)
        } catch {
            loadingError = error.localizedDescription
        }
    }

    static func load(from bundle: Bundle) throws -> TransitCatalog {
        guard let url = bundle.url(forResource: "transit_data", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(TransitCatalog.self, from: data)
        let errors = CatalogValidator.validate(catalog)
        guard errors.isEmpty else { throw CatalogError.invalid(errors) }
        return catalog
    }
}

enum CatalogError: LocalizedError {
    case missingResource
    case invalid([String])

    var errorDescription: String? {
        switch self {
        case .missingResource: "노선 데이터 파일을 찾을 수 없습니다."
        case .invalid(let errors): "노선 데이터가 올바르지 않습니다: \(errors.joined(separator: ", "))"
        }
    }
}

enum CatalogValidator {
    static func validate(_ catalog: TransitCatalog) -> [String] {
        var errors: [String] = []
        func duplicates<T: Hashable>(_ values: [T]) -> Set<T> {
            var seen = Set<T>()
            return Set(values.filter { !seen.insert($0).inserted })
        }

        if catalog.schemaVersion != 1 { errors.append("지원하지 않는 schemaVersion") }
        if !duplicates(catalog.regions.map(\.id)).isEmpty { errors.append("중복 지역 ID") }
        if !duplicates(catalog.operators.map(\.id)).isEmpty { errors.append("중복 운영기관 ID") }
        if !duplicates(catalog.stations.map(\.id)).isEmpty { errors.append("중복 역 ID") }
        if !duplicates(catalog.lines.map(\.id)).isEmpty { errors.append("중복 노선 ID") }
        if !duplicates(catalog.routePatterns.map(\.id)).isEmpty { errors.append("중복 계통 ID") }

        let regionIDs = Set(catalog.regions.map(\.id))
        let operatorIDs = Set(catalog.operators.map(\.id))
        let lineIDs = Set(catalog.lines.map(\.id))
        let stationIDs = Set(catalog.stations.map(\.id))
        for line in catalog.lines {
            if !regionIDs.contains(line.regionID) { errors.append("\(line.id)의 지역 누락") }
            if !operatorIDs.contains(line.operatorID) { errors.append("\(line.id)의 운영기관 누락") }
            if !line.colorHex.allSatisfy(\.isHexDigit) || line.colorHex.count != 6 {
                errors.append("\(line.id)의 노선색 오류")
            }
        }
        for pattern in catalog.routePatterns {
            if !lineIDs.contains(pattern.lineID) { errors.append("\(pattern.id)의 노선 누락") }
            if pattern.stationIDs.count < 2 { errors.append("\(pattern.id)의 역 부족") }
            if pattern.stationIDs.contains(where: { !stationIDs.contains($0) }) { errors.append("\(pattern.id)의 역 참조 누락") }
            if zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains(where: ==) { errors.append("\(pattern.id)의 연속 중복 역") }
            if pattern.stationCodes?.keys.contains(where: { !pattern.stationIDs.contains($0) }) == true {
                errors.append("\(pattern.id)의 역 번호 참조 오류")
            }
        }
        for line in catalog.lines {
            let mainPatterns = catalog.routePatterns.filter { $0.lineID == line.id && $0.kind == .main }
            for pattern in mainPatterns where mainPatterns.contains(where: {
                $0.id != pattern.id && contains(pattern.stationIDs, asContiguousSubsequenceOf: $0.stationIDs)
            }) {
                errors.append("\(pattern.id)의 중복 부분 계통")
            }
        }
        return errors
    }

    private static func contains(_ candidate: [String], asContiguousSubsequenceOf route: [String]) -> Bool {
        guard candidate.count < route.count else { return false }
        for start in 0...(route.count - candidate.count) {
            if Array(route[start..<(start + candidate.count)]) == candidate { return true }
        }
        return false
    }
}
