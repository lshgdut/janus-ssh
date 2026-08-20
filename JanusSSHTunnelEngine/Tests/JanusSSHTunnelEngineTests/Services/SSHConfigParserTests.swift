import XCTest
@testable import JanusSSHTunnelEngine

final class SSHConfigParserTests: XCTestCase {

    func test_parses_basic_hosts() {
        let config = """
        # comment
        Host production
          HostName 10.10.0.10
          User root
          Port 22
          IdentityFile ~/.ssh/id_ed25519

        Host staging
          HostName 10.30.0.10
          User ubuntu
        """
        let entries = SSHConfigParser.parse(config)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].alias, "production")
        XCTAssertEqual(entries[0].options[.hostname], "10.10.0.10")
        XCTAssertEqual(entries[0].options[.user], "root")
        XCTAssertEqual(entries[1].alias, "staging")
    }

    func test_skips_wildcard_hosts() {
        let config = """
        Host *
          ServerAliveInterval 60
        Host production
          HostName 10.10.0.10
        """
        let entries = SSHConfigParser.parse(config)
        XCTAssertEqual(entries.count, 1, "通配 Host * 应被过滤")
        XCTAssertEqual(entries.first?.alias, "production")
    }

    func test_parses_proxy_jump() {
        let config = """
        Host bastion
          HostName bastion.example.com
          Port 2222
        Host private-server
          HostName internal.example.com
          ProxyJump bastion
        """
        let entries = SSHConfigParser.parse(config)
        XCTAssertEqual(entries[1].options[.proxyJump], "bastion")
        XCTAssertEqual(entries[0].options[.port], "2222")
    }

    func test_skips_comments_and_blank_lines() {
        let config = """
        # This is a comment

        # Another comment
        Host production
          HostName 10.10.0.10
        """
        let entries = SSHConfigParser.parse(config)
        XCTAssertEqual(entries.count, 1)
    }

    func test_first_alias_in_compound_host_line() {
        let config = """
        Host production prod-prd
          HostName 10.10.0.10
        """
        let entries = SSHConfigParser.parse(config)
        XCTAssertEqual(entries.first?.alias, "production",
                       "compound Host 行应使用第一个 alias")
    }

    func test_parses_open_design_four_host_fixture() {
        // 对齐 OpenDesign 原型 SSH Hosts 页
        let config = """
        Host production
          HostName 10.10.0.10
          User root
          IdentityFile ~/.ssh/id_ed25519
          ForwardAgent no

        Host staging
          HostName 10.30.0.10
          User ubuntu

        Host bastion
          HostName bastion.example.com
          Port 2222
          ForwardAgent yes

        Host private-server
          HostName private.example.com
          ProxyJump bastion
        """
        let entries = SSHConfigParser.parse(config)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.map { $0.alias },
                       ["production", "staging", "bastion", "private-server"])
        XCTAssertEqual(entries[3].options[.proxyJump], "bastion")
    }

    // MARK: - Include (recursive, glob, cycle-safe)

    func test_include_resolves_relative_path() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("janus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        Host dev-server
            HostName dev.local
            User developer
        """.write(to: tempDir.appendingPathComponent("hosts.conf"),
                  atomically: true, encoding: .utf8)

        try """
        Host main-server
            HostName main.local

        Include hosts.conf
        """.write(to: tempDir.appendingPathComponent("config"),
                  atomically: true, encoding: .utf8)

        let entries = SSHConfigParser.parse(
            try String(contentsOf: tempDir.appendingPathComponent("config"), encoding: .utf8),
            basePath: tempDir.appendingPathComponent("config").path
        )
        let aliases = Set(entries.map { $0.alias })
        XCTAssertTrue(aliases.contains("main-server"))
        XCTAssertTrue(aliases.contains("dev-server"),
                      "Include 应该递归解析 hosts.conf 中的 dev-server")
    }

    func test_include_supports_glob_star() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("janus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for name in ["hosts-prod.conf", "hosts-stage.conf", "readme.txt"] {
            try "Host \(name)\n    HostName 1.2.3.4\n".write(
                to: tempDir.appendingPathComponent(name),
                atomically: true, encoding: .utf8
            )
        }

        try "Include hosts-*.conf\n".write(
            to: tempDir.appendingPathComponent("config"),
            atomically: true, encoding: .utf8
        )

        let entries = SSHConfigParser.parse(
            try String(contentsOf: tempDir.appendingPathComponent("config"), encoding: .utf8),
            basePath: tempDir.appendingPathComponent("config").path
        )
        let aliases = Set(entries.map { $0.alias })
        XCTAssertTrue(aliases.contains("hosts-prod.conf"))
        XCTAssertTrue(aliases.contains("hosts-stage.conf"))
        XCTAssertFalse(aliases.contains("readme.txt"),
                       "glob 不应匹配 readme.txt")
    }

    func test_include_prevents_circular_reference() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("janus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "Include b.conf\nHost a\n    HostName a.local\n".write(
            to: tempDir.appendingPathComponent("a.conf"),
            atomically: true, encoding: .utf8
        )
        try "Include a.conf\nHost b\n    HostName b.local\n".write(
            to: tempDir.appendingPathComponent("b.conf"),
            atomically: true, encoding: .utf8
        )

        let entries = SSHConfigParser.parse(
            try String(contentsOf: tempDir.appendingPathComponent("a.conf"), encoding: .utf8),
            basePath: tempDir.appendingPathComponent("a.conf").path
        )
        // 不能死循环;两条 host 都该出现
        let aliases = Set(entries.map { $0.alias })
        XCTAssertTrue(aliases.contains("a"))
        XCTAssertTrue(aliases.contains("b"))
    }

    func test_missing_include_file_is_silently_skipped() {
        let content = """
        Include /tmp/does-not-exist-\(UUID().uuidString).conf

        Host existing
            HostName example.com
        """
        let entries = SSHConfigParser.parse(content, basePath: nil)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.alias, "existing")
    }
}