import AppKit
import SwiftUI
import CoreLocation
import BottomBarSDK

class LocationBarPlugin: NSObject, BottomBarPlugin {
    let id = "location"
    let title = ""
    let icon = ""
    let panelWidth: CGFloat = 0
    let panelHeight: CGFloat = 0

    func makeContentView(close: @escaping () -> Void) -> NSView { NSView() }

    func makeBarNSView() -> NSView? {
        NSHostingView(rootView: LocationInlineView())
    }
}

private class LocationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var city: String = ""
    let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var refreshTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            if let city = placemarks?.first?.locality {
                DispatchQueue.main.async {
                    self?.city = city
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

private struct LocationInlineView: View {
    @StateObject private var model = LocationModel()

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "location.fill")
                .font(BarFont.regular(9))
                .foregroundColor(.secondary)
            Text(model.city)
                .font(BarFont.regular(12))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
    }
}
