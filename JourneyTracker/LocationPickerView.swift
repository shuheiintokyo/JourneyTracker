import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerView: View {
    @Binding var selectedLocation: CLLocation?
    @Binding var isPresented: Bool
    let title: String
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503), // Tokyo default
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @StateObject private var localLocationManager = LocationManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with instruction
                VStack(spacing: 10) {
                    Text(title)
                        .font(.headline)
                        .padding(.top)
                    
                    Text("Hold for 3 seconds on map to place pin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .background(Color(UIColor.systemBackground))
                
                // Interactive Map with overlay
                ZStack {
                    Map(coordinateRegion: $region, interactionModes: .all, annotationItems: selectedCoordinate != nil ? [LocationPin(coordinate: selectedCoordinate!)] : []) { pin in
                        MapPin(coordinate: pin.coordinate, tint: .red)
                    }
                    .onLongPressGesture(minimumDuration: 3.0, maximumDistance: 50) {
                        // Long press to place pin - using center of current map view
                        selectedCoordinate = region.center
                    }
                    
                    // Map center crosshair indicator (centered on map)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white).frame(width: 35, height: 35))
                                    .shadow(radius: 2)
                                Text("Hold 3s")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(4)
                                    .shadow(radius: 1)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false) // Allow touches to pass through to map
                }
                
                // Selected location info
                if let coordinate = selectedCoordinate {
                    VStack(spacing: 5) {
                        Text("Selected Location:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                }
                
                // Quick action buttons
                HStack(spacing: 15) {
                    Button("Use Current Location") {
                        if let currentLocation = localLocationManager.currentLocation {
                            selectedCoordinate = currentLocation.coordinate
                            region.center = currentLocation.coordinate
                        }
                    }
                    .disabled(localLocationManager.currentLocation == nil)
                    .padding()
                    .background(localLocationManager.currentLocation != nil ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .foregroundColor(localLocationManager.currentLocation != nil ? .blue : .gray)
                    .cornerRadius(8)
                    
                    Button("Center Map") {
                        if let current = localLocationManager.currentLocation {
                            region.center = current.coordinate
                        }
                    }
                    .disabled(localLocationManager.currentLocation == nil)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(8)
                }
                .padding()
                
                // Action buttons
                HStack(spacing: 20) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                    
                    Button("Confirm") {
                        if let coordinate = selectedCoordinate {
                            selectedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        }
                        isPresented = false
                    }
                    .disabled(selectedCoordinate == nil)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedCoordinate != nil ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
            }
        }
        .onAppear {
            localLocationManager.requestLocationPermission()
            if let currentLocation = localLocationManager.currentLocation {
                region.center = currentLocation.coordinate
            }
        }
    }
}

struct LocationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    LocationPickerView(
        selectedLocation: .constant(nil),
        isPresented: .constant(true),
        title: "Select Start Location"
    )
}
