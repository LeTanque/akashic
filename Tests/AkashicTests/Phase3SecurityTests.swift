import AkashicCore
import Foundation
import GRDB
import XCTest
@testable import Akashic

final class Phase3SecurityTests: XCTestCase {
    func testPasswordWrapUnwrap() throws {
        let (meta, _, _, _) = try DataKeyManager.generateMetadata(username: "u", password: "correct horse battery")
        let key = try DataKeyManager.unwrapDataKey(metadata: meta, password: "correct horse battery")
        XCTAssertEqual(key.count, 32)
    }

    func testWrongPasswordFails() throws {
        let (meta, _, _, _) = try DataKeyManager.generateMetadata(username: "u", password: "secretsecret")
        XCTAssertThrowsError(try DataKeyManager.unwrapDataKey(metadata: meta, password: "wrongwrongwrong"))
    }

    func testRecoveryWrapUnwrap() throws {
        let (metadata, recoveryDisplay, _, _) = try DataKeyManager.generateMetadata(username: "u", password: "pw")
        let keyPwd = try DataKeyManager.unwrapDataKey(metadata: metadata, password: "pw")
        let keyRec = try DataKeyManager.unwrapDataKey(metadata: metadata, recoveryCode: recoveryDisplay)
        XCTAssertEqual(keyPwd, keyRec)
    }

    func testPasswordChangeRewraps() throws {
        let dk = try DataKeyManager.randomDataKey()
        var meta = try DataKeyManager.generateMetadata(username: "u", password: "old-old-old", dataKey: dk).metadata
        meta = try DataKeyManager.changePassword(metadata: meta, oldPassword: "old-old-old", newPassword: "new-new-new")
        let unwrapped = try DataKeyManager.unwrapDataKey(metadata: meta, password: "new-new-new")
        XCTAssertEqual(unwrapped, dk)
        XCTAssertThrowsError(try DataKeyManager.unwrapDataKey(metadata: meta, password: "old-old-old"))
    }

    /// RFC 6238 Appendix B test vectors (8-digit); app uses 6-digit — verify drift validation on 6-digit codes.
    func testTOTPRFC6238Vectors() {
        let secret = Data("12345678901234567890".utf8)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let t59 = f.date(from: "1970-01-01T00:00:59Z"),
              let t1111111109 = f.date(from: "2005-03-18T01:58:29Z"),
              let t1111111111 = f.date(from: "2005-03-18T01:58:31Z"),
              let t1234567890 = f.date(from: "2009-02-13T23:31:30Z"),
              let t2000000000 = f.date(from: "2033-05-18T03:33:20Z")
        else {
            XCTFail("date parse")
            return
        }
        XCTAssertEqual(TOTP.code(secret: secret, date: t59, digits: 8), "94287082")
        XCTAssertEqual(TOTP.code(secret: secret, date: t1111111109, digits: 8), "07081804")
        XCTAssertEqual(TOTP.code(secret: secret, date: t1111111111, digits: 8), "14050471")
        XCTAssertEqual(TOTP.code(secret: secret, date: t1234567890, digits: 8), "89005924")
        XCTAssertEqual(TOTP.code(secret: secret, date: t2000000000, digits: 8), "69279037")

        let c6 = TOTP.code(secret: secret, date: t1111111109, digits: 6)
        XCTAssertTrue(TOTP.validate(secret: secret, code: c6, date: t1111111109, digits: 6, allowedDrift: 1))
        XCTAssertFalse(TOTP.validate(secret: secret, code: "000000", date: t1111111109, digits: 6, allowedDrift: 1))
    }

    func testPlaintextToEncryptedMigrationPreservesRows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-mig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plainURL = dir.appendingPathComponent("plain.sqlite")
        let encURL = dir.appendingPathComponent("enc.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        var plainQueue: DatabaseQueue? = try DatabaseQueue(path: plainURL.path)
        try TodoDatabase.migrator.migrate(plainQueue!)
        try plainQueue!.write { db in
            try db.execute(
                sql: """
                INSERT INTO todos (id, title, description, completed, priority, created_on, updated_at, sort_order)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                arguments: [UUID().uuidString, "t", "", 0, "medium", Date(), Date(), 0]
            )
        }
        let before = try plainQueue!.read { try AkashicPlaintextMigration.countRows(in: $0) }
        // Release the writer before export so ATTACH/DETACH is not blocked.
        plainQueue = nil

        let dataKey = try DataKeyManager.randomDataKey()
        try AkashicPlaintextMigration.exportPlaintextToEncrypted(
            plaintextURL: plainURL,
            encryptedDestinationURL: encURL,
            dataKey: dataKey
        )
        let encQueue = try TodoDatabase.openEncrypted(at: encURL, passphrase: dataKey)
        let after = try encQueue.read { try AkashicPlaintextMigration.countRows(in: $0) }
        XCTAssertEqual(before, after)
    }

    func testExportWithEmptyKeyLeavesPlaintext() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-mig2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plainURL = dir.appendingPathComponent("akashic.sqlite")
        let encURL = dir.appendingPathComponent("tmp.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        let plainQueue = try DatabaseQueue(path: plainURL.path)
        try TodoDatabase.migrator.migrate(plainQueue)

        XCTAssertThrowsError(
            try AkashicPlaintextMigration.exportPlaintextToEncrypted(
                plaintextURL: plainURL,
                encryptedDestinationURL: encURL,
                dataKey: Data()
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: plainURL.path))
    }

    func testLockedAPIResponse() {
        let r = TodoAPIServer.lockedResponse()
        XCTAssertEqual(r.statusCode, .locked)
    }
}
