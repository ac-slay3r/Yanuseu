import Foundation

enum SkillFileReader {
    static func read(_ url: URL) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: 16_385) ?? Data()
                guard bytes.count <= 16_384 else { throw SkillError.tooLarge }
                return bytes
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw SkillError.invalidDocument }
        return try result.get()
    }
}
