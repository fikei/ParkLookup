import Foundation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "BlockfaceLoader")

/// Loads blockface data from embedded JSON file
class BlockfaceLoader {
    static let shared = BlockfaceLoader()

    private var cachedBlockfaces: [Blockface]?

    private init() {}

    /// Load blockfaces from sample JSON
    func loadBlockfaces() throws -> [Blockface] {
        if let cached = cachedBlockfaces {
            logger.info("Returning cached blockfaces")
            return cached
        }

        logger.info("Loading blockfaces from sample JSON")

        guard let url = Bundle.main.url(forResource: "sample_blockfaces", withExtension: "json") else {
            logger.error("sample_blockfaces.json not found in bundle")
            throw BlockfaceLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(BlockfaceDataResponse.self, from: data)

        cachedBlockfaces = response.blockfaces

        logger.info("Loaded \(response.blockfaces.count) blockfaces")

        return response.blockfaces
    }

    /// Find blockfaces with active street cleaning
    func getActiveStreetCleaningBlockfaces(at date: Date = Date()) throws -> [Blockface] {
        let blockfaces = try loadBlockfaces()
        return blockfaces.filter { $0.hasActiveStreetCleaning(at: date) }
    }
}

struct BlockfaceDataResponse: Codable {
    let blockfaces: [Blockface]
}

enum BlockfaceLoaderError: Error {
    case fileNotFound
    case invalidData
}
