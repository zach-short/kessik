import XCTest
@testable import Kessik

final class SSHLineTests: XCTestCase {
    private func line(_ user: String?, _ host: String, _ port: Int = 22, jump: JumpHost? = nil) -> SSHLine {
        SSHLine(username: user, hostname: host, port: port, jump: jump)
    }

    func testParsesEachForm() {
        let bastion = JumpHost(hostname: "bastion.example.com", port: 2222, username: "ops")
        let cases: [(String, SSHLine)] = [
            ("zach@mac.local", line("zach", "mac.local")),
            ("  zach@mac.local\n", line("zach", "mac.local")),
            ("zach@mac.local:2222", line("zach", "mac.local", 2222)),
            ("zach@100.64.0.1:2200", line("zach", "100.64.0.1", 2200)),
            ("zach@[fd7a::1]:2222", line("zach", "fd7a::1", 2222)),
            ("zach@[fd7a::1]", line("zach", "fd7a::1")),
            ("zach@fd7a::1", line("zach", "fd7a::1")),
            ("ssh://zach@mac.local:2222", line("zach", "mac.local", 2222)),
            ("ssh://zach@mac.local/", line("zach", "mac.local")),
            ("ssh://zach@[fd7a::1]:2222", line("zach", "fd7a::1", 2222)),
            ("ssh://mac.local", line(nil, "mac.local")),
            ("ssh zach@mac.local", line("zach", "mac.local")),
            ("ssh mac.local", line(nil, "mac.local")),
            ("ssh -p 2222 zach@mac.local", line("zach", "mac.local", 2222)),
            ("ssh -p2222 zach@mac.local", line("zach", "mac.local", 2222)),
            ("ssh -l zach mac.local", line("zach", "mac.local")),
            ("ssh -l zach -p 2200 mac.local", line("zach", "mac.local", 2200)),
            ("ssh -J ops@bastion.example.com:2222 zach@studio.lan",
             line("zach", "studio.lan", jump: bastion)),
            ("ssh -J bastion.example.com zach@studio.lan",
             line("zach", "studio.lan", jump: JumpHost(hostname: "bastion.example.com", username: ""))),
            ("ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -F cfg -L 8080:localhost:80 -R 9000:x:9 -D 1080 zach@mac.local",
             line("zach", "mac.local")),
            ("ssh -v -A -t zach@mac.local", line("zach", "mac.local")),
            ("ssh -vAt -p 2222 zach@mac.local", line("zach", "mac.local", 2222)),
            ("ssh -vp 2222 zach@mac.local", line("zach", "mac.local", 2222)),
            ("ssh -- zach@mac.local", line("zach", "mac.local")),
            ("ssh -t zach@mac.local tmux attach -t main", line("zach", "mac.local")),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(SSHLine.parse(text), expected, text)
        }
    }

    func testPlainHostnameIsLeftAlone() {
        for text in ["mac.local", "mac.tailnet.ts.net", "100.64.0.1", "fd7a::1", "mac.local:2222", "", "ssh", "sshmac"] {
            XCTAssertNil(SSHLine.parse(text), text)
        }
    }

    func testInvalidLinesAreNil() {
        let cases = [
            "ssh", "ssh ", "ssh -v", "ssh -p", "ssh -p 2222",
            "zach@", "@mac.local", "ssh @mac.local", "ssh://@mac.local",
            "zach@mac.local:0", "zach@mac.local:65536", "zach@mac.local:abc", "zach@mac.local:",
            "ssh -p 0 zach@mac.local", "ssh -p abc zach@mac.local",
            "zach@[fd7a::1", "zach@[fd7a::1]2222", "zach smith@mac.local",
            "ssh -J a@one,b@two zach@mac.local", "ssh -J ops@ zach@mac.local",
            "ssh -J ops@bastion:99999 zach@mac.local", "ssh://zach@mac.local/path",
        ]
        for text in cases {
            XCTAssertNil(SSHLine.parse(text), text)
        }
    }
}
