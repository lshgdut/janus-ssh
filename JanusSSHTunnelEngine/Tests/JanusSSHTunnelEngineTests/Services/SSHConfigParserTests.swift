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
}