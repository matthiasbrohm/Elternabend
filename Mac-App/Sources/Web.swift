import Foundation

struct WebAntwort {
    let status: Int
    let location: String
    let body: String
}

/// Schickt Formulare an gilde-elternabend.de – genau wie die Import-Felder auf der Webseite.
/// Weiterleitungen werden nicht verfolgt: An ihrem Ziel („?m=import“) erkennt die App, ob es geklappt hat.
final class WebClient: NSObject, URLSessionTaskDelegate {
    static let basis = "https://gilde-elternabend.de/"

    private final class Fach: @unchecked Sendable {
        var ergebnis: Result<WebAntwort, Error> = .failure(URLError(.unknown))
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 240
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpShouldSetCookies = false
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    private static let erlaubt: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()

    private static func kodiert(_ s: String) -> String {
        return s.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? ""
    }

    /// Blockiert, bis die Antwort da ist – nur von einem Hintergrund-Thread aufrufen.
    func post(_ seite: String, _ felder: [(String, String)]) -> Result<WebAntwort, Error> {
        guard let url = URL(string: WebClient.basis + seite) else { return .failure(URLError(.badURL)) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("ElternabendAbgleich/" + appVersion + " (Mac)", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(felder.map { WebClient.kodiert($0.0) + "=" + WebClient.kodiert($0.1) }.joined(separator: "&").utf8)

        let fach = Fach()
        let fertig = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: req) { data, response, error in
            if let error = error {
                fach.ergebnis = .failure(error)
            } else if let h = response as? HTTPURLResponse {
                fach.ergebnis = .success(WebAntwort(status: h.statusCode,
                                                    location: h.value(forHTTPHeaderField: "Location") ?? "",
                                                    body: String(decoding: data ?? Data(), as: UTF8.self)))
            }
            fertig.signal()
        }
        task.resume()
        fertig.wait()
        return fach.ergebnis
    }
}

let appVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
