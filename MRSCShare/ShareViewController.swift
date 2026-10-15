import CoreTransferable
import UIKit
import UniformTypeIdentifiers

/// Share ▸ MRSC from Spotify, Apple Music, YouTube Music or Deezer. Stays tiny: it saves the shared link in the
/// App Group and opens the app, which reads the playlist in its song-list import. If iOS doesn't let it open
/// the app, the link waits there until MRSC is opened next.
final class ShareViewController: UIViewController {
    private static let appGroup = "group.com.ecki.mrsc"
    private static let pendingKey = "pendingPlaylistLink"   // PlaylistLinkInbox.defaultsKey in the app

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Opening MRSC…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        Task { await handOff() }
    }

    private func handOff() async {
        guard let link = await sharedLink() else {
            finish("There's no link in what was shared. Share a playlist from Spotify, Apple Music, YouTube Music or Deezer.")
            return
        }
        UserDefaults(suiteName: Self.appGroup)?.set(link, forKey: Self.pendingKey)
        var c = URLComponents()
        c.scheme = "mrsc"
        c.host = "import-playlist"
        c.queryItems = [URLQueryItem(name: "url", value: link)]
        if let url = c.url, openApp(url) {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            finish("Link saved. Open MRSC to import the playlist.")
        }
    }

    /// The first web link among the shared items (a URL, or text with a link in it as Spotify sends).
    private func sharedLink() async -> String? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(p, URL.self), url.scheme?.hasPrefix("http") == true { return url.absoluteString }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await load(p, String.self),
               let r = text.range(of: #"https?://\S+"#, options: .regularExpression) { return String(text[r]) }
        }
        return nil
    }

    private func load<T: Transferable & Sendable>(_ provider: NSItemProvider, _ type: T.Type) async -> T? {
        await withCheckedContinuation { c in
            _ = provider.loadTransferable(type: type) { c.resume(returning: try? $0.get()) }
        }
    }

    /// Extensions can't call UIApplication.open directly; the app object is reachable through the responder chain.
    private func openApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r is UIApplication, r.responds(to: selector), let imp = r.method(for: selector) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(imp, to: Open.self)(r, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = r.next
        }
        return false
    }

    private func finish(_ message: String) {
        label.text = message
        navigationItem.title = "MRSC"
        let done = UIButton(configuration: .prominentGlass(), primaryAction: UIAction(title: "Done") { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        done.tintColor = .systemRed
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(done)
        NSLayoutConstraint.activate([
            done.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            done.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
        ])
    }
}
