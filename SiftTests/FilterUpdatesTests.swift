import CryptoKit
import XCTest
@testable import Sift

/// Over-the-air filters: only a correctly signed, complete bundle made for
/// this app is ever used.
final class FilterUpdatesTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()

    private func bundleData(schema: Int = FilterUpdates.schema, version: Int = 100, drop: String? = nil) -> Data {
        var files: [String: String] = [:]
        for name in FilterUpdates.fileNames where name != drop { files[name] = "/* \(name) */" }
        let object: [String: Any] = ["schema": schema, "version": version, "commit": "abc", "files": files]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sign(_ data: Data, with signer: Curve25519.Signing.PrivateKey? = nil) -> Data {
        try! (signer ?? key).signature(for: data)
    }

    func testBuiltInKeyParses() {
        XCTAssertNotNil(FilterUpdates.publicKey)
    }

    func testAcceptsSignedBundle() {
        let data = bundleData()
        let bundle = FilterUpdates.verify(data, signature: sign(data), key: key.publicKey)
        XCTAssertEqual(bundle?.version, 100)
        XCTAssertEqual(bundle?.files["youtube.css"], "/* youtube.css */")
    }

    func testRejectsChangedBytes() {
        let data = bundleData()
        let signature = sign(data)
        var changed = data
        changed[changed.count - 2] ^= 0x01
        XCTAssertNil(FilterUpdates.verify(changed, signature: signature, key: key.publicKey))
    }

    func testRejectsOtherKey() {
        let data = bundleData()
        let stranger = Curve25519.Signing.PrivateKey()
        XCTAssertNil(FilterUpdates.verify(data, signature: sign(data, with: stranger), key: key.publicKey))
        XCTAssertNil(FilterUpdates.verify(data, signature: sign(data), key: nil))
    }

    func testRejectsOtherSchema() {
        let data = bundleData(schema: FilterUpdates.schema + 1)
        XCTAssertNil(FilterUpdates.verify(data, signature: sign(data), key: key.publicKey))
    }

    func testRejectsMissingFile() {
        let data = bundleData(drop: "instagram.js")
        XCTAssertNil(FilterUpdates.verify(data, signature: sign(data), key: key.publicKey))
    }

    func testSignatureFileIsBase64Text() {
        let raw = Data([1, 2, 3, 250])
        let text = Data((raw.base64EncodedString() + "\n").utf8)
        XCTAssertEqual(FilterUpdates.decodeSignature(text), raw)
        XCTAssertNil(FilterUpdates.decodeSignature(Data("not base64!".utf8)))
    }

    func testOnlyNewerReplaces() {
        let data = bundleData(version: 100)
        let old = FilterUpdates.verify(data, signature: sign(data), key: key.publicKey)!
        let newerData = bundleData(version: 200)
        let newer = FilterUpdates.verify(newerData, signature: sign(newerData), key: key.publicKey)!
        XCTAssertTrue(FilterUpdates.shouldReplace(nil, with: old))
        XCTAssertTrue(FilterUpdates.shouldReplace(old, with: newer))
        XCTAssertFalse(FilterUpdates.shouldReplace(newer, with: old))
        XCTAssertFalse(FilterUpdates.shouldReplace(old, with: old))
    }
}
