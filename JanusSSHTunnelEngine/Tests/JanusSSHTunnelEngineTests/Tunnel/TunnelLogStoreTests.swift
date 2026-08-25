import XCTest
@testable import JanusSSHTunnelEngine

/// TunnelLogStore 是 per-profile 的环形缓冲日志,UI 通过 subscribe 拿到实时流。
/// MVP 约束:每个 Profile 最多 1000 条,超出后丢弃最旧的。
final class TunnelLogStoreTests: XCTestCase {

    func test_append_and_snapshot_roundtrip() async {
        let store = TunnelLogStore()
        let profileID = UUID()

        await store.append(profileID: profileID, kind: .stdout, message: "hello")
        await store.append(profileID: profileID, kind: .stderr, message: "world", level: .error)

        let snapshot = await store.snapshot(profileID: profileID)
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[0].message, "hello")
        XCTAssertEqual(snapshot[1].message, "world")
    }

    func test_buffer_does_not_exceed_capacity() async {
        let store = TunnelLogStore()
        let profileID = UUID()

        // 添加 1500 条,只保留最后 1000
        for i in 0..<1500 {
            await store.append(profileID: profileID, kind: .stdout, message: "line-\(i)")
        }

        let snapshot = await store.snapshot(profileID: profileID)
        XCTAssertEqual(snapshot.count, 1000)
        XCTAssertEqual(snapshot.first?.message, "line-500")
        XCTAssertEqual(snapshot.last?.message, "line-1499")
    }

    func test_subscribe_receives_live_entries() async {
        let store = TunnelLogStore()
        let profileID = UUID()

        let receivedTask = Task<[TunnelLogStore.Entry], Never> {
            var collected: [TunnelLogStore.Entry] = []
            for await entry in await store.subscribe(profileID: profileID) {
                collected.append(entry)
                if collected.count >= 2 { return collected }
            }
            return collected
        }

        // 异步追加,确保订阅者有机会注册
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await store.append(profileID: profileID, kind: .stdout, message: "first")
            try? await Task.sleep(nanoseconds: 50_000_000)
            await store.append(profileID: profileID, kind: .stdout, message: "second")
        }

        let received = await receivedTask.value
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0].message, "first")
        XCTAssertEqual(received[1].message, "second")
    }

    func test_clear_empties_buffer() async {
        let store = TunnelLogStore()
        let profileID = UUID()

        await store.append(profileID: profileID, kind: .stdout, message: "x")
        await store.clear(profileID: profileID)

        let snapshot = await store.snapshot(profileID: profileID)
        XCTAssertTrue(snapshot.isEmpty)
    }
}