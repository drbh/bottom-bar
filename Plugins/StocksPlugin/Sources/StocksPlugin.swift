import AppKit
import SwiftUI
import BottomBarSDK

class StocksBarPlugin: NSObject, BottomBarPlugin {
    let id = "stocks"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: StocksTickerView())
    }
}

// MARK: - Model

private struct StockQuote {
    let symbol: String
    let price: Double
    let change: Double
}

// MARK: - Yahoo Finance Fetcher (v8 chart endpoint)

private class StocksFetcher: ObservableObject {
    @Published var quotes: [StockQuote] = []

    static let symbols = ["AAPL", "GOOGL", "TSLA", "MSFT", "AMZN"]

    func fetch() {
        let group = DispatchGroup()
        var results: [String: StockQuote] = [:]
        let lock = NSLock()

        for symbol in Self.symbols {
            group.enter()
            let urlString = "https://query2.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=2d"
            guard let url = URL(string: urlString) else { group.leave(); continue }

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: request) { data, _, error in
                defer { group.leave() }
                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let chart = json["chart"] as? [String: Any],
                      let resultArr = chart["result"] as? [[String: Any]],
                      let first = resultArr.first,
                      let meta = first["meta"] as? [String: Any],
                      let price = meta["regularMarketPrice"] as? Double else { return }

                let prevClose = meta["chartPreviousClose"] as? Double ?? price
                let change = price - prevClose

                lock.lock()
                results[symbol] = StockQuote(symbol: symbol, price: price, change: change)
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            // Preserve original symbol order
            self?.quotes = Self.symbols.compactMap { results[$0] }
        }
    }
}

// MARK: - View

private struct StocksTickerView: View {
    @StateObject private var fetcher = StocksFetcher()
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            if fetcher.quotes.isEmpty {
                Text("Stocks ...")
                    .font(BarFont.regular(11))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                ForEach(Array(fetcher.quotes.enumerated()), id: \.offset) { _, quote in
                    HStack(spacing: 3) {
                        Text(quote.symbol)
                            .font(BarFont.medium(10))
                            .foregroundColor(.white.opacity(0.6))
                        Text(priceString(quote.price))
                            .font(BarFont.regular(12))
                            .foregroundColor(.white)
                        Text(changeString(quote.change))
                            .font(BarFont.regular(10))
                            .foregroundColor(quote.change >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .onAppear { fetcher.fetch() }
        .onReceive(refreshTimer) { _ in fetcher.fetch() }
    }

    private func priceString(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }

    private func changeString(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@%.2f", sign, change)
    }
}
