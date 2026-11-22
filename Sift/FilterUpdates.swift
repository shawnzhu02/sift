import CryptoKit
import Foundation

/// Over-the-air filter updates. The page filters (the CSS and JS in
/// Resources) can change without a new app build: the app downloads a signed
/// `filters.json` from the public sift-filters repo, checks its signature
/// against the key built into the app, and caches it. Anything wrong (no
/// network, bad signature, a bundle made for a different app) means the
/// filters built into the app are used instead.
///
/// The filters workflow (.github/workflows/filters.yml) builds and signs the
/// bundle whenever Sift/Resources changes on main.
enum FilterUpdates {
    /// Bump this (in this file only; the workflow reads it from here) when
    /// new filters need app code that older builds don't have, such as a new
    /// switch flag. Older builds then keep their built-in filters.
    static let schema = 1

    /// Ed25519 public key that `filters.json` must be signed with.
    static let publicKeyBase64 = "eOt3pjMSrlFYC2YSGdwu0bNs+mabvvKhi+hRpTqOnTk="

    static let bundleURL = URL(string: "https://raw.githubusercontent.com/shawnzhu02/sift-filters/main/filters.json")!
    static let signatureURL = URL(string: "https://raw.githubusercontent.com/shawnzhu02/sift-filters/main/filters.json.sig")!

    /// Every file a bundle must carry. A bundle missing one is ignored.
    static let fileNames = ["common.js", "swipe.js", "instagram.css", "instagram.js", "youtube.css", "youtube.js"]

    /// How often to look for a new bundle while the app is in use.
    static let checkInterval: TimeInterval = 30 * 60

    struct FilterBundle: Decodable, Equatable {
        let schema: Int
        /// Seconds since 1970 of the commit the filters came from.
        let version: Int
        let commit: String?
        let files: [String: String]
    }

    // MARK: Checking a bundle

    static var publicKey: Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: publicKeyBase64) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// The bundle in `data` if the signature matches, it was made for this
    /// app's schema and it carries every filter file. Otherwise nil.
    static func verify(_ data: Data, signature: Data, key: Curve25519.Signing.PublicKey?) -> FilterBundle? {
        guard let key, key.isValidSignature(signature, for: data),
              let bundle = try? JSONDecoder().decode(FilterBundle.self, from: data),
              bundle.schema == schema,
              fileNames.allSatisfy({ bundle.files[$0] != nil })
        else { return nil }
        return bundle
    }

    /// The signature file holds the signature as base64 text.
    static func decodeSignature(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A downloaded bundle replaces the cached one only if it is newer.
    static func shouldReplace(_ current: FilterBundle?, with new: FilterBundle) -> Bool {
        guard let current else { return true }
        return new.version > current.version
    }

    // MARK: The bundle in use

    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded = false
    nonisolated(unsafe) private static var active: FilterBundle?
    nonisolated(unsafe) private static var lastCheck: Date?

    /// The verified bundle in use, or nil when the built-in filters are.
    static var current: FilterBundle? {
        lock.lock(); defer { lock.unlock() }
        if !loaded {
            loaded = true
            active = readCache()
        }
        return active
    }

    /// One filter file's text from the downloaded bundle, if there is one.
    static func file(_ name: String) -> String? {
        current?.files[name]
    }

    /// Settings shows which filters are in use.
    static var statusText: String {
        guard let bundle = current else { return "Filters: built into the app" }
        let date = Date(timeIntervalSince1970: TimeInterval(bundle.version))
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return "Filters: updated \(when)"
    }

    // MARK: Cache

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Filters", isDirectory: true)
    }

    private static var cachedBundleURL: URL { cacheDirectory.appendingPathComponent("filters.json") }
    private static var cachedSignatureURL: URL { cacheDirectory.appendingPathComponent("filters.json.sig") }

    /// The cached bundle, checked again so a damaged file is never used.
    private static func readCache() -> FilterBundle? {
        guard let data = try? Data(contentsOf: cachedBundleURL),
              let sigData = try? Data(contentsOf: cachedSignatureURL),
              let signature = decodeSignature(sigData)
        else { return nil }
        return verify(data, signature: signature, key: publicKey)
    }

    private static func writeCache(_ data: Data, _ sigData: Data) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try sigData.write(to: cachedSignatureURL, options: .atomic)
        try data.write(to: cachedBundleURL, options: .atomic)
    }

    // MARK: Download

    /// Downloads the newest bundle. Returns true when a newer verified bundle
    /// was saved and is now in use. Checks at most every `checkInterval`
    /// unless `force` is set.
    static func refresh(force: Bool = false) async -> Bool {
        let now = Date()
        lock.lock()
        if !force, let last = lastCheck, now.timeIntervalSince(last) < checkInterval {
            lock.unlock()
            return false
        }
        lastCheck = now
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        do {
            async let bundleResponse = session.data(from: bundleURL)
            async let signatureResponse = session.data(from: signatureURL)
            let (data, response) = try await bundleResponse
            let (sigData, sigResponse) = try await signatureResponse
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  (sigResponse as? HTTPURLResponse)?.statusCode == 200,
                  let signature = decodeSignature(sigData),
                  let bundle = verify(data, signature: signature, key: publicKey),
                  shouldReplace(current, with: bundle)
            else { return false }
            try writeCache(data, sigData)
            lock.lock()
            active = bundle
            loaded = true
            lock.unlock()
            return true
        } catch {
            return false
        }
    }
}
