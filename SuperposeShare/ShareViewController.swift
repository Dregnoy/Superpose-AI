import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point: receives an image shared from Instagram, Pinterest,
/// Safari, or Photos and forwards it to Superpose's live pose & ghost extractor.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleIncomingSharedImage()
    }

    private func handleIncomingSharedImage() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finishExtension()
            return
        }

        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] data, _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let image = Self.extractImage(from: data) {
                            SharedPoseImportStore.saveSharedImage(image)
                            self.openHostApp()
                        }
                        self.finishExtension()
                    }
                }
                return
            }
        }

        finishExtension()
    }

    private static func extractImage(from item: NSSecureCoding?) -> UIImage? {
        if let image = item as? UIImage {
            return image
        }
        if let url = item as? URL, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        if let data = item as? Data {
            return UIImage(data: data)
        }
        return nil
    }

    private func openHostApp() {
        let url = SharedPoseImportStore.deepLinkURL
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }
    }

    private func finishExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
