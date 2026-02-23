//
//  TesterDataParsing.swift
//  TestLog
//
//  Created by Codex on 2/21/26.
//

import Foundation

struct ParsedForceSample: Identifiable, Hashable {
    let id = UUID()
    let timeSeconds: Double
    let forceKN: Double

    var forceLbs: Double {
        forceKN * 224.80894387096
    }
}

protocol TesterDataParsing {
    func parseSamples(from url: URL) throws -> [ParsedForceSample]
}

struct LBYTesterDataParser: TesterDataParsing, Sendable {
    nonisolated init() {}

    nonisolated func parseSamples(from url: URL) throws -> [ParsedForceSample] {
        if !url.pathExtension.isEmpty, url.pathExtension.lowercased() != "lby" {
            return []
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        let dataOffset = findDataOffset(in: data)
        guard dataOffset < data.count else { return [] }
        let payload = data.subdata(in: dataOffset..<data.count)
        let samples = loadWordsLE(from: payload)

        // Source units are kN*1000 (per Python reference).
        return samples.enumerated().map { index, raw in
            let forceKN = Double(raw) * 0.001
            return ParsedForceSample(
                timeSeconds: Double(index) * 0.5,
                forceKN: forceKN
            )
        }
    }

    private nonisolated func findDataOffset(in data: Data) -> Int {
        let upperBound = min(800, max(256, data.count - 100))
        guard upperBound > 256 else { return min(608, data.count) }

        var offset = 256
        while offset < upperBound {
            if let variation = sampleVariationAtOffset(offset, in: data), variation > 100 {
                return offset
            }
            offset += 4
        }
        return min(608, data.count)
    }

    private nonisolated func sampleVariationAtOffset(_ offset: Int, in data: Data) -> Int? {
        let minBytes = 80
        guard offset >= 0, offset + minBytes <= data.count else { return nil }
        let window = data.subdata(in: offset..<(offset + minBytes))
        let words = loadWordsLE(from: window)
        guard words.count >= 20 else { return nil }

        let positiveValues = words.filter { $0 > 0 && $0 < 100_000 }
        guard positiveValues.count >= 10, let minValue = positiveValues.min(), let maxValue = positiveValues.max() else {
            return nil
        }
        return Int(maxValue - minValue)
    }

    private nonisolated func loadWordsLE(from data: Data) -> [Int32] {
        let wordCount = data.count / 4
        guard wordCount > 0 else { return [] }
        return data.withUnsafeBytes { bytes in
            var output: [Int32] = []
            output.reserveCapacity(wordCount)
            for i in 0..<wordCount {
                let start = i * 4
                let value = bytes.loadUnaligned(fromByteOffset: start, as: Int32.self)
                output.append(Int32(littleEndian: value))
            }
            return output
        }
    }
}
