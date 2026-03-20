import CoreText
import Foundation

enum FontLoader {
    static func registerAll() {
        let fonts = [
            "ArchitypeStedelijkW00.ttf",
            "AzeretMono.ttf",
        ]
        for name in fonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
                print("[FontLoader] Not found in bundle: \(name)")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let e = error?.takeRetainedValue() {
                print("[FontLoader] Failed to register \(name): \(e)")
            }
        }
    }
}
