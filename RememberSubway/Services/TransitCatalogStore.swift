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
        case .missingResource: AppLocalization.text("catalog.error.missingResource")
        case .invalid(let errors): AppLocalization.format("catalog.error.invalid.format", errors.joined(separator: ", "))
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

        if catalog.schemaVersion != 1 { errors.append(AppLocalization.text("catalog.validation.unsupportedSchema")) }
        if !duplicates(catalog.regions.map(\.id)).isEmpty { errors.append(AppLocalization.text("catalog.validation.duplicateRegionID")) }
        if !duplicates(catalog.operators.map(\.id)).isEmpty { errors.append(AppLocalization.text("catalog.validation.duplicateOperatorID")) }
        if !duplicates(catalog.stations.map(\.id)).isEmpty { errors.append(AppLocalization.text("catalog.validation.duplicateStationID")) }
        if !duplicates(catalog.lines.map(\.id)).isEmpty { errors.append(AppLocalization.text("catalog.validation.duplicateLineID")) }
        if !duplicates(catalog.routePatterns.map(\.id)).isEmpty { errors.append(AppLocalization.text("catalog.validation.duplicateRoutePatternID")) }

        let regionIDs = Set(catalog.regions.map(\.id))
        let operatorIDs = Set(catalog.operators.map(\.id))
        let lineIDs = Set(catalog.lines.map(\.id))
        let stationIDs = Set(catalog.stations.map(\.id))
        for line in catalog.lines {
            if !regionIDs.contains(line.regionID) { errors.append(AppLocalization.format("catalog.validation.missingRegion.format", line.id)) }
            if !operatorIDs.contains(line.operatorID) { errors.append(AppLocalization.format("catalog.validation.missingOperator.format", line.id)) }
            if !line.colorHex.allSatisfy(\.isHexDigit) || line.colorHex.count != 6 {
                errors.append(AppLocalization.format("catalog.validation.invalidLineColor.format", line.id))
            }
        }
        for pattern in catalog.routePatterns {
            if !lineIDs.contains(pattern.lineID) { errors.append(AppLocalization.format("catalog.validation.missingLine.format", pattern.id)) }
            if pattern.stationIDs.count < 2 { errors.append(AppLocalization.format("catalog.validation.insufficientStations.format", pattern.id)) }
            if pattern.stationIDs.contains(where: { !stationIDs.contains($0) }) { errors.append(AppLocalization.format("catalog.validation.missingStationReference.format", pattern.id)) }
            if zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains(where: ==) { errors.append(AppLocalization.format("catalog.validation.consecutiveDuplicateStation.format", pattern.id)) }
            if pattern.stationCodes?.keys.contains(where: { !pattern.stationIDs.contains($0) }) == true {
                errors.append(AppLocalization.format("catalog.validation.invalidStationCodeReference.format", pattern.id))
            }
        }
        for line in catalog.lines {
            let mainPatterns = catalog.routePatterns.filter { $0.lineID == line.id && $0.kind == .main }
            for pattern in mainPatterns where mainPatterns.contains(where: {
                $0.id != pattern.id && contains(pattern.stationIDs, asContiguousSubsequenceOf: $0.stationIDs)
            }) {
                errors.append(AppLocalization.format("catalog.validation.duplicateSubroute.format", pattern.id))
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
