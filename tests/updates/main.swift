import Foundation

var failures = 0
func expect(_ condition: Bool, _ name: String) {
    print(condition ? "PASS: \(name)" : "FAIL: \(name)")
    if !condition { failures += 1 }
}

// Version rules: only stable, strictly newer x.y.z versions count; anything unparseable is not newer.
expect(UpdateRules.isNewer("0.2.0", than: "0.1.1"), "newer minor")
expect(UpdateRules.isNewer("1.0.0", than: "0.9.9"), "newer major")
expect(UpdateRules.isNewer("0.1.10", than: "0.1.9"), "numeric, not text, comparison")
expect(!UpdateRules.isNewer("0.2.0", than: "0.2.0"), "equal is not newer")
expect(!UpdateRules.isNewer("0.1.1", than: "0.2.0"), "older is not newer")
expect(!UpdateRules.isNewer("0.3.0-beta.1", than: "0.2.0"), "prerelease ignored")
expect(!UpdateRules.isNewer("v0.3.0", than: "0.2.0"), "tag prefix ignored")
expect(!UpdateRules.isNewer("0.3", than: "0.2.0"), "two-part version ignored")
expect(!UpdateRules.isNewer("0.3.0.1", than: "0.2.0"), "four-part version ignored")
expect(!UpdateRules.isNewer("garbage", than: "0.2.0"), "garbage ignored")
expect(!UpdateRules.isNewer("", than: "0.2.0"), "empty ignored")
expect(!UpdateRules.isNewer("99999999999999999999.0.0", than: "0.2.0"), "overflow ignored")
expect(!UpdateRules.isNewer("0.3.0", than: "garbage"), "unparseable current never prompts")

// Notice text.
expect(UpdateRules.notice(available: "0.3.0", current: "0.2.0") == "UltraLink 0.3.0 is available — you have 0.2.0.", "notice text")

// Scheduled checks stay off under CI, with the opt-out, and in QA/snapshot launches.
func allowed(_ env: [String: String], _ args: [String] = ["UltraLink"]) -> Bool {
    UpdateRules.backgroundChecksAllowed(environment: env, arguments: args)
}
expect(allowed([:]), "normal launch checks in the background")
expect(!allowed(["CI": "true"]), "CI set: no background check")
expect(!allowed(["CI": ""]), "CI set but empty: no background check")
expect(!allowed(["ULTRALINK_NO_UPDATE_CHECK": "1"]), "opt-out env: no background check")
expect(allowed(["ULTRALINK_NO_UPDATE_CHECK": "0"]), "opt-out env other than 1 is ignored")
expect(!allowed([:], ["UltraLink", "--demo", "--show-settings", "--snapshot", "/tmp/x"]), "snapshot launch: no background check")
expect(!allowed([:], ["UltraLink", "--show-popover"]), "QA window launch: no background check")
expect(allowed([:], ["UltraLink", "--show-popover", "--scheduled-check"]), "--scheduled-check allows a QA check")
expect(!allowed(["CI": "1"], ["UltraLink", "--scheduled-check"]), "CI wins over --scheduled-check")

// Shipped defaults: daily signed checks on, automatic install off.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let info = NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist"))!
expect(info["SUEnableAutomaticChecks"] as? Bool == true, "automatic checks on by default")
expect(info["SUScheduledCheckInterval"] as? Int == 86400, "at most one check per 24 h")
expect(info["SUAutomaticallyUpdate"] as? Bool == false, "automatic install off by default")
expect(info["SUAllowsAutomaticUpdates"] as? Bool == true, "automatic install can be turned on")
expect((info["SUPublicEDKey"] as? String)?.isEmpty == false, "feed signature key present")
expect((info["SUFeedURL"] as? String)?.hasPrefix("https://github.com/") == true, "feed is the public GitHub release")

// Docs: contract marker, short README sections, privacy detail in PRIVACY.md.
func read(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
func section(_ text: String, _ heading: String) -> [Substring] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let start = lines.firstIndex(of: Substring(heading)) else { return [] }
    return lines[(start + 1)...].prefix { !$0.hasPrefix("## ") }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}
let readme = read("README.md")
expect(read("docs/updates.md").contains("<!-- update-contract: v1 -->"), "docs/updates.md has the contract marker")
let updates = section(readme, "## Updates")
expect(!updates.isEmpty && updates.count <= 3 && updates.joined().contains("docs/updates.md"), "README Updates is short and links the docs")
let privacy = section(readme, "## Privacy")
expect((3...6).contains(privacy.count) && privacy.joined().contains("PRIVACY.md"), "README Privacy is 3-6 lines and links PRIVACY.md")
expect(read("PRIVACY.md").contains("anonymous"), "PRIVACY.md describes the update request")
let version = info["CFBundleShortVersionString"] as? String ?? ""
expect(read("CHANGELOG.md").contains("## [\(version)]"), "CHANGELOG has an entry for the shipped version \(version)")

if failures > 0 { print("\(failures) failed"); exit(1) }
