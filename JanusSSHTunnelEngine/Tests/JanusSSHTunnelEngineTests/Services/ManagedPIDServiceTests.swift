import XCTest
import Darwin
@testable import JanusSSHTunnelEngine

final class ManagedPIDServiceTests: XCTestCase {

    func test_sweepOrphans_returns_zero_when_no_pids() async throws {
        let dao = InMemoryManagedPIDDAO()
        let service = ManagedPIDServiceImpl(
            dao: dao,
            procPidPath: { _ in nil }
        )

        let killed = try await service.sweepOrphans()

        XCTAssertEqual(killed, 0)
    }

    func test_sweepOrphans_kills_pids_no_longer_running() async throws {
        let dao = InMemoryManagedPIDDAO()
        let profileID = UUID()
        try await dao.upsert(ManagedPID(
            profileID: profileID,
            pid: 99999,
            startedAt: Date(),
            exePath: "/usr/bin/ssh"
        ))
        let killBag = Bag()
        let service = ManagedPIDServiceImpl(
            dao: dao,
            procPidPath: { _ in nil },  // proc_pidpath returns nil = pid is gone
            kill: { pid in await killBag.add(pid) }
        )

        let killed = try await service.sweepOrphans()

        XCTAssertEqual(killed, 1)
        let killedPIDs = await killBag.snapshot()
        XCTAssertEqual(killedPIDs, [99999])
        let remaining = try await dao.loadAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_sweepOrphans_skips_pids_still_alive() async throws {
        let dao = InMemoryManagedPIDDAO()
        let alivePID = getpid()
        try await dao.upsert(ManagedPID(
            profileID: UUID(),
            pid: alivePID,
            startedAt: Date(),
            exePath: "/usr/bin/ssh"
        ))
        let killBag = Bag()
        let service = ManagedPIDServiceImpl(
            dao: dao,
            procPidPath: { pid in pid == alivePID ? "/usr/bin/ssh" : nil },
            kill: { pid in
                await killBag.add(pid)
                XCTFail("should not kill alive pid \(pid)")
            }
        )

        let killed = try await service.sweepOrphans()

        XCTAssertEqual(killed, 0)
        let killedPIDs = await killBag.snapshot()
        XCTAssertEqual(killedPIDs, [])
        let remaining = try await dao.loadAll()
        XCTAssertEqual(remaining.count, 1)
    }

    func test_track_then_clear_round_trips() async throws {
        let dao = InMemoryManagedPIDDAO()
        let service = ManagedPIDServiceImpl(
            dao: dao,
            procPidPath: { _ in nil }
        )
        let pid: Int32 = 4242

        try await service.track(pid: pid, exePath: "/usr/bin/ssh", profileID: UUID())
        let afterTrack = try await dao.loadAll()
        XCTAssertEqual(afterTrack.count, 1)

        try await service.clear(pid: pid)
        let afterClear = try await dao.loadAll()
        XCTAssertEqual(afterClear.count, 0)
    }
}

/// 内存版 DAO — 测试隔离,完全替代 JSONManagedPIDDAOImpl。
private actor InMemoryManagedPIDDAO: ManagedPIDDAO {
    private var storage: [ManagedPID] = []

    func loadAll() async throws -> [ManagedPID] { storage }

    func upsert(_ entry: ManagedPID) async throws {
        if let idx = storage.firstIndex(where: { $0.pid == entry.pid }) {
            storage[idx] = entry
        } else {
            storage.append(entry)
        }
    }

    func delete(pid: Int32) async throws {
        storage.removeAll { $0.pid == pid }
    }
}

/// 记录被 kill 的 PID,让 @Sendable closure 安全地 mutate。
private actor Bag {
    private var items: [Int32] = []
    func add(_ item: Int32) { items.append(item) }
    func snapshot() -> [Int32] { items }
}
