// Command-line checks for a signed Sparkle appcast — the file the app's
// "Check for Updates…" button fetches, and the update archive it advertises.
//
// Sparkle's gate on an archive is the EdDSA signature in the item's
// `sparkle:edSignature`, verified against the `SUPublicEDKey` compiled into the
// running app, plus the `length` it compares against the bytes it downloaded.
// Both are checked here against the real archive, with the key *and* the feed
// URL read out of the app's own Info.plist — so the enclosure URL is measured
// against the repo the app actually fetches its feed from, rather than against
// a second copy of that address kept in the release tooling.
//
// What that buys: a release whose appcast would be rejected by every installed
// copy fails at the command line that made it, instead of on every Mac that
// presses the button.
//
// Usage: check <appcast.xml> <archive.zip> <Info.plist> <version> [tag]
// Run from the workspace root — see README.md beside this file.

import CryptoKit
import Foundation

var failures = 0
var checks = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    checks += 1
    if condition {
        print("ok   \(name)")
    } else {
        failures += 1
        print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 5 || arguments.count == 6 else {
    FileHandle.standardError.write(
        Data("usage: check <appcast.xml> <archive.zip> <Info.plist> <version> [tag]\n".utf8)
    )
    exit(2)
}

let appcastPath = arguments[1]
let archivePath = arguments[2]
let infoPlistPath = arguments[3]
let releaseVersion = arguments[4].hasPrefix("v")
    ? String(arguments[4].dropFirst())
    : arguments[4]
/// The tag whose assets the enclosure URL has to name. It is `v<version>` for
/// a release this repo's script made, and given explicitly for the hand-made
/// tags already on GitHub (`v.2.0.3`), whose release is the one the feed URL
/// resolves to even though the app inside it reports another version.
let releaseTag = arguments.count == 6 ? arguments[5] : "v\(releaseVersion)"

// MARK: - The app's side of the contract

/// The two keys the running app contributes: the public key every update must
/// be signed with, and the address it will look for the appcast at.
struct AppContract {
    var feedURL = ""
    var publicKey: Curve25519.Signing.PublicKey?
    var keyText = ""
}

func readAppContract(_ path: String) -> AppContract {
    var contract = AppContract()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let plist = try? PropertyListSerialization.propertyList(
              from: data, options: [], format: nil
          ) as? [String: Any]
    else {
        print("FAIL app contract\(path.isEmpty ? "" : " — \(path)") is not a readable plist")
        failures += 1
        checks += 1
        return contract
    }
    contract.feedURL = plist["SUFeedURL"] as? String ?? ""
    contract.keyText = (plist["SUPublicEDKey"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let raw = Data(base64Encoded: contract.keyText) {
        contract.publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }
    return contract
}

let app = readAppContract(infoPlistPath)

check(
    "app: SUPublicEDKey is a 32-byte Ed25519 public key",
    app.publicKey != nil,
    "SUPublicEDKey in \(infoPlistPath) is \"\(app.keyText)\""
)

/// The download prefix the enclosure URLs have to be built from: everything in
/// the feed URL up to `/releases/`, which is the repo the app is pinned to.
/// A feed URL of any other shape means this check cannot speak for the release
/// — said out loud rather than passed over.
let feedURL = app.feedURL
let releasesMarker = "/releases/"
let markerRange = feedURL.range(of: releasesMarker)
let downloadOwner = markerRange.map { String(feedURL[feedURL.startIndex..<$0.lowerBound]) } ?? ""

check(
    "app: SUFeedURL is a GitHub release asset URL",
    !downloadOwner.isEmpty && feedURL.hasPrefix("https://github.com/"),
    "SUFeedURL is \"\(feedURL)\""
)

// MARK: - The archive, as downloaded

let archiveURL = URL(fileURLWithPath: archivePath)
let archive = (try? Data(contentsOf: archiveURL, options: .mappedIfSafe)) ?? Data()

check(
    "archive: readable and non-empty",
    !archive.isEmpty,
    "\(archivePath) is \(archive.count) bytes"
)

// MARK: - The appcast

struct Item {
    var version = ""
    var shortVersion = ""
    var minimumSystemVersion = ""
    var url = ""
    var length = -1
    var signature = ""
    var hasReleaseNotes = false
}

/// Reads the item fields with their prefixed names left intact, because that is
/// how they are written: Sparkle's own namespace declares `sparkle:version` and
/// the signature lives in an attribute of the same shape on `enclosure`.
///
/// A field counts only as a direct child of the `item` being read. Nesting under
/// an `item` is what a `description` carrying release notes looks like, while a
/// `description` under `channel` is RSS boilerplate rather than notes — the same
/// element name, opposite meanings.
final class AppcastReader: NSObject, XMLParserDelegate {
    var items: [Item] = []
    private var path: [String] = []
    private var text = ""
    private var itemField: String?

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        let parent = path.last
        path.append(elementName)
        text = ""
        itemField = nil

        if elementName == "item" {
            items.append(Item())
            return
        }
        guard parent == "item" else { return }

        itemField = elementName
        if elementName == "enclosure" {
            mutate {
                $0.url = attributeDict["url"] ?? ""
                $0.signature = attributeDict["sparkle:edSignature"] ?? ""
                $0.length = Int(attributeDict["length"] ?? "") ?? -1
            }
        }
        if elementName == "description" || elementName == "sparkle:releaseNotesLink" {
            mutate { $0.hasReleaseNotes = true }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName: String?
    ) {
        if !path.isEmpty { path.removeLast() }
        defer { text = ""; itemField = nil }
        guard itemField == elementName else { return }

        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "sparkle:version": mutate { $0.version = value }
        case "sparkle:shortVersionString": mutate { $0.shortVersion = value }
        case "sparkle:minimumSystemVersion": mutate { $0.minimumSystemVersion = value }
        default: break
        }
    }

    private func mutate(_ body: (inout Item) -> Void) {
        guard let last = items.indices.last else { return }
        body(&items[last])
    }
}

let appcastData = (try? Data(contentsOf: URL(fileURLWithPath: appcastPath))) ?? Data()
let reader = AppcastReader()
let parser = XMLParser(data: appcastData)
parser.delegate = reader
let parsed = parser.parse()

check(
    "appcast: parses as XML",
    parsed && !appcastData.isEmpty,
    appcastData.isEmpty
        ? "\(appcastPath) is missing, empty or unreadable"
        : (parser.parserError?.localizedDescription ?? "the XML is not well formed")
)

check("appcast: carries at least one item", !reader.items.isEmpty)

check(
    "appcast: every item is signed",
    !reader.items.isEmpty && reader.items.allSatisfy { !$0.signature.isEmpty },
    "\(reader.items.filter { $0.signature.isEmpty }.count) unsigned item(s)"
)

let archiveName = archiveURL.lastPathComponent
let matches = reader.items.filter { $0.url.hasSuffix("/\(archiveName)") }

check(
    "appcast: exactly one item advertises \(archiveName)",
    matches.count == 1,
    "\(matches.count) of \(reader.items.count) items match"
)

// The item's own checks are meaningless without the item they describe, and the
// failure above already names why. Saying they were skipped is the honest thing
// to print; reporting a missing item's empty fields as failures would bury the
// one line that explains them.
if matches.count == 1, let item = matches.first {
    // Reported rather than required: an update installs without notes, and the
    // release body carries the same text on GitHub.
    print("info release notes: \(item.hasReleaseNotes ? "carried by the appcast" : "none")")

    // The comparison number, and the only one Sparkle ranks an update by
    // (`SUAppcastItem.m`: `sparkle:version` is the version, the short string is
    // what the dialog displays). A repeat of the running app's number is an
    // update nobody is offered, so this one is required, not reported.
    check(
        "item: sparkle:version is the release being published",
        item.version == releaseVersion,
        "sparkle:version is \"\(item.version)\", expected \"\(releaseVersion)\""
    )

    check(
        "item: short version string is declared for display",
        !item.shortVersion.isEmpty
    )

    check(
        "item: enclosure URL points at this release's asset",
        item.url == "\(downloadOwner)\(releasesMarker)download/\(releaseTag)/\(archiveName)",
        "enclosure url is \"\(item.url)\""
    )

    check(
        "item: declared length is the archive's own length",
        item.length > 0 && item.length == archive.count,
        "appcast says \(item.length), \(archivePath) is \(archive.count) bytes"
    )

    check(
        "item: minimum system version is declared",
        !item.minimumSystemVersion.isEmpty
    )

    // The signature itself, over the bytes exactly as they would be downloaded.
    if let publicKey = app.publicKey {
        let signature = Data(base64Encoded: item.signature) ?? Data()
        check(
            "item: edSignature verifies against the app's SUPublicEDKey",
            signature.count == 64 && publicKey.isValidSignature(signature, for: archive),
            signature.count != 64
                ? "signature decodes to \(signature.count) bytes, expected 64"
                : "the signature does not verify over \(archiveName)"
        )
    } else {
        check("item: edSignature verifies against the app's SUPublicEDKey", false,
              "no usable public key to verify with")
    }
} else {
    print("skip item checks — no single item advertises \(archiveName)")
}

print("checks: \(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
