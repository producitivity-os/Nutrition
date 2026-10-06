import AppKit
@preconcurrency import MapKit
import Observation
import SwiftUI

struct LocationSelection: Hashable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

@MainActor @Observable
final class LocationSearchModel: NSObject, @MainActor MKLocalSearchCompleterDelegate {
    var query = "" { didSet { completer.queryFragment = query } }
    var results: [MKLocalSearchCompletion] = []
    var selection: LocationSelection
    private let completer = MKLocalSearchCompleter()

    init(selection: LocationSelection?) {
        self.selection = selection ?? LocationSelection(name: "", address: "", latitude: 3.139, longitude: 101.6869)
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func choose(_ completion: MKLocalSearchCompletion) {
        Task { @MainActor in
            guard let item = try? await MKLocalSearch(request: .init(completion: completion)).start().mapItems.first else { return }
            let address = [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.locality, item.placemark.country].compactMap { $0 }.joined(separator: ", ")
            selection = LocationSelection(name: item.name ?? completion.title, address: address, latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            results = []
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = Array(completer.results.prefix(6)) }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) { results = [] }
}

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: LocationSearchModel
    let completion: (LocationSelection) -> Void

    init(selection: LocationSelection?, completion: @escaping (LocationSelection) -> Void) {
        _model = State(initialValue: LocationSearchModel(selection: selection))
        self.completion = completion
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                TextField("Search for an address or place", text: $model.query).textFieldStyle(.roundedBorder)
                if !model.results.isEmpty {
                    List(model.results, id: \.self) { result in
                        Button { model.choose(result) } label: { VStack(alignment: .leading) { Text(result.title); Text(result.subtitle).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                    }.frame(height: 112)
                }
            }.padding(12)
            DraggableMapView(latitude: $model.selection.latitude, longitude: $model.selection.longitude).frame(maxWidth: .infinity, maxHeight: .infinity)
            Form {
                TextField("Branch name", text: $model.selection.name)
                TextField("Address", text: $model.selection.address)
                HStack { TextField("Latitude", value: $model.selection.latitude, format: .number); TextField("Longitude", value: $model.selection.longitude, format: .number) }
            }.formStyle(.grouped).frame(height: 122)
            HStack { Button("Cancel") { dismiss() }; Spacer(); Text("Click the map or drag the pin to adjust.").font(.caption).foregroundStyle(.secondary); Button("Use Location") { completion(model.selection); dismiss() }.keyboardShortcut(.defaultAction).disabled(model.selection.name.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(12).background(.bar)
        }
        .frame(minWidth: 520, minHeight: 440)
    }
}

private struct DraggableMapView: NSViewRepresentable {
    @Binding var latitude: Double
    @Binding var longitude: Double
    func makeCoordinator() -> Coordinator { Coordinator(latitude: $latitude, longitude: $longitude) }
    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let annotation = MKPointAnnotation(); annotation.coordinate = .init(latitude: latitude, longitude: longitude); map.addAnnotation(annotation)
        map.setRegion(.init(center: annotation.coordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000), animated: false)
        map.addGestureRecognizer(NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.clicked(_:))))
        context.coordinator.map = map
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard let annotation = map.annotations.first as? MKPointAnnotation else { return }
        if abs(annotation.coordinate.latitude - latitude) > 0.000001 || abs(annotation.coordinate.longitude - longitude) > 0.000001 { annotation.coordinate = coordinate; map.setCenter(coordinate, animated: true) }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var latitude: Binding<Double>; var longitude: Binding<Double>; weak var map: MKMapView?
        init(latitude: Binding<Double>, longitude: Binding<Double>) { self.latitude = latitude; self.longitude = longitude }
        @objc func clicked(_ gesture: NSClickGestureRecognizer) { guard let map else { return }; update(map.convert(gesture.location(in: map), toCoordinateFrom: map)) }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? { let view = mapView.dequeueReusableAnnotationView(withIdentifier: "branch") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "branch"); view.annotation = annotation; view.isDraggable = true; view.markerTintColor = .systemOrange; return view }
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) { if newState == .ending, let coordinate = view.annotation?.coordinate { update(coordinate) } }
        private func update(_ coordinate: CLLocationCoordinate2D) { latitude.wrappedValue = coordinate.latitude; longitude.wrappedValue = coordinate.longitude }
    }
}
