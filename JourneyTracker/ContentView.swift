import SwiftUI
import CoreLocation
import MapKit

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var routeManager = RouteManager()
    @State private var startLocation: CLLocation?
    @State private var destinationLocation: CLLocation?
    @State private var isTrackingJourney = false
    @State private var journeyProgress: Double = 0.0
    @State private var traveledDistance: Double = 0.0
    @State private var showingLocationPicker = false
    @State private var pickingDestination = false
    @State private var showingResetAlert = false
    @State private var mapType: MKMapType = .standard
    // REMOVED: showTraffic - No longer needed
    @State private var addingWaypoint = false
    @State private var previousLocation: CLLocation?
    
    // NEW: Location search functionality
    @State private var showingLocationSearch = false
    @State private var searchingForDestination = false
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    
    // Map region state
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7662), // Tokyo Station
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var mapAnnotations: [SimpleMapAnnotation] {
        var annotations: [SimpleMapAnnotation] = []
        
        if let start = startLocation {
            annotations.append(SimpleMapAnnotation(
                coordinate: start.coordinate,
                color: .green,
                title: "Start"
            ))
        }
        
        if let destination = destinationLocation {
            annotations.append(SimpleMapAnnotation(
                coordinate: destination.coordinate,
                color: .red,
                title: "Destination"
            ))
        }
        
        // Add waypoints
        for (index, waypoint) in routeManager.waypoints.dropFirst().dropLast().enumerated() {
            annotations.append(SimpleMapAnnotation(
                coordinate: waypoint.coordinate,
                color: .orange,
                title: "Stop \(index + 1)"
            ))
        }
        
        if let current = locationManager.currentLocation, isTrackingJourney {
            annotations.append(SimpleMapAnnotation(
                coordinate: current.coordinate,
                color: .blue,
                title: "Current"
            ))
        }
        
        // NEW: Add search result annotations
        for (index, result) in searchResults.enumerated() {
            annotations.append(SimpleMapAnnotation(
                coordinate: result.placemark.coordinate,
                color: .purple,
                title: "Result \(index + 1)"
            ))
        }
        
        return annotations
    }
    
    // MARK: - Computed properties for map features
    
    private var mapTypeIcon: String {
        switch mapType {
        case .standard:
            return "map"
        case .satellite:
            return "globe.americas.fill"
        case .hybrid:
            return "map.fill"
        default:
            return "map"
        }
    }
    
    private var mapTypeName: String {
        switch mapType {
        case .standard:
            return "Standard"
        case .satellite:
            return "Satellite"
        case .hybrid:
            return "Hybrid"
        default:
            return "Standard"
        }
    }
    
    private func getMapStyle() -> MapStyle {
        switch mapType {
        case .standard:
            return .standard
        case .satellite:
            return .imagery
        case .hybrid:
            return .hybrid
        default:
            return .standard
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            headerSection
            
            // Map View
            mapSection
            
            // Progress Section at Bottom
            progressSection
        }
        .sheet(isPresented: $showingLocationPicker) {
            if addingWaypoint {
                WaypointPickerView(
                    routeManager: routeManager,
                    isPresented: $showingLocationPicker,
                    addingWaypoint: $addingWaypoint
                )
            } else {
                LocationPickerView(
                    selectedLocation: pickingDestination ? $destinationLocation : $startLocation,
                    isPresented: $showingLocationPicker,
                    title: pickingDestination ? "Select Destination" : "Select Start Location"
                )
            }
        }
        // NEW: Location search sheet
        .sheet(isPresented: $showingLocationSearch) {
            LocationSearchView(
                searchText: $searchText,
                searchResults: $searchResults,
                isSearching: $isSearching,
                isPresented: $showingLocationSearch,
                searchingForDestination: searchingForDestination,
                onLocationSelected: { location, isDestination in
                    if isDestination {
                        destinationLocation = location
                    } else {
                        startLocation = location
                    }
                    // Clear search results after selection
                    searchResults.removeAll()
                    searchText = ""
                }
            )
        }
        .alert("Reset Journey", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetJourney()
            }
        } message: {
            Text("This will clear all locations and stop tracking. Are you sure?")
        }
        .onAppear {
            locationManager.requestLocationPermission()
            if let currentLocation = locationManager.currentLocation {
                mapRegion.center = currentLocation.coordinate
            } else {
                mapRegion.center = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7662)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            if let location = newLocation {
                if !isTrackingJourney {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        mapRegion.center = location.coordinate
                    }
                }
                updateProgressIfTracking(currentLocation: location)
            }
        }
        .onChange(of: startLocation) { _, _ in
            updateMapRegion()
            calculateRouteIfReady()
        }
        .onChange(of: destinationLocation) { _, _ in
            updateMapRegion()
            calculateRouteIfReady()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Title
            Text("Journey Tracker")
                .font(.title2)
                .fontWeight(.bold)
            
            // Route calculation status
            if routeManager.isCalculatingRoute {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Calculating route...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let error = routeManager.routeError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if !isTrackingJourney {
                // UPDATED: Location setup buttons with search functionality
                HStack(spacing: 8) {
                    // Start location options
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            // Manual pin selection
                            Button(action: {
                                pickingDestination = false
                                showingLocationPicker = true
                            }) {
                                Image(systemName: startLocation != nil ? "checkmark.circle.fill" : "location.circle")
                                    .font(.title3)
                                    .foregroundColor(startLocation != nil ? .green : .blue)
                            }
                            
                            // NEW: Search for start location
                            Button(action: {
                                searchingForDestination = false
                                showingLocationSearch = true
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                            }
                        }
                        Text("Start")
                            .font(.caption)
                    }
                    .frame(width: 70, height: 60)
                    .background(startLocation != nil ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .cornerRadius(10)
                    
                    Button(action: {
                        if let currentLocation = locationManager.currentLocation {
                            startLocation = currentLocation
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.title3)
                            Text("Current")
                                .font(.caption)
                        }
                        .frame(width: 70, height: 60)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                    }
                    .disabled(locationManager.currentLocation == nil)
                    
                    // Destination location options
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            // Manual pin selection
                            Button(action: {
                                pickingDestination = true
                                showingLocationPicker = true
                            }) {
                                Image(systemName: destinationLocation != nil ? "checkmark.circle.fill" : "flag.circle")
                                    .font(.title3)
                                    .foregroundColor(destinationLocation != nil ? .green : .red)
                            }
                            
                            // NEW: Search for destination
                            Button(action: {
                                searchingForDestination = true
                                showingLocationSearch = true
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .foregroundColor(.red)
                            }
                        }
                        Text("Destination")
                            .font(.caption)
                    }
                    .frame(width: 80, height: 60)
                    .background(destinationLocation != nil ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .cornerRadius(10)
                    
                    Button(action: {
                        showingResetAlert = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                            Text("Reset")
                                .font(.caption)
                        }
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.gray)
                        .cornerRadius(10)
                    }
                    
                    // Add Waypoint Button
                    if startLocation != nil && destinationLocation != nil {
                        Button(action: {
                            addingWaypoint = true
                            showingLocationPicker = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                Text("Waypoint")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 60)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(10)
                        }
                    }
                }
                
                // Route info with dynamic timing
                if let route = routeManager.route {
                    VStack(spacing: 4) {
                        Text("Walking Route: \(String(format: "%.1f km", route.distance / 1000))")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        if routeManager.waypoints.count > 2 {
                            Text("Via \(routeManager.waypoints.count - 2) stops")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        HStack(spacing: 15) {
                            VStack {
                                Text("Apple Estimate")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatTime(route.expectedTravelTime))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            if isTrackingJourney {
                                VStack {
                                    Text("Dynamic ETA")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(routeManager.getFormattedArrivalTime())
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                }
                
                // UPDATED: Map settings section (removed traffic, added search)
                if routeManager.route != nil {
                    mapSettingsSection
                }
                
                // Start journey button
                if canStartJourney {
                    Button(action: startJourney) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Journey")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .fontWeight(.semibold)
                    }
                    .padding(.horizontal)
                }
            } else {
                // Journey in progress controls
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journey in Progress")
                            .font(.headline)
                            .foregroundColor(.blue)
                        if let route = routeManager.route {
                            Text("Walking Route: \(String(format: "%.1f km", route.distance / 1000))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 10) {
                                Text("Speed: \(routeManager.getFormattedSpeed())")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("ETA: \(routeManager.getFormattedArrivalTime())")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button(action: stopJourney) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Finish")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            showingResetAlert = true
                        }) {
                            Image(systemName: "xmark")
                                .padding(8)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - UPDATED: Map Settings Section (removed traffic, simplified)
    private var mapSettingsSection: some View {
        VStack(spacing: 8) {
            Text("Map Settings")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 30) {
                // Map Type Cycle
                VStack(spacing: 4) {
                    Button(action: cycleMapType) {
                        Image(systemName: mapTypeIcon)
                            .font(.title3)
                            .foregroundColor(.purple)
                            .frame(width: 30, height: 30)
                    }
                    Text(mapTypeName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // NEW: Quick Search
                VStack(spacing: 4) {
                    Button(action: {
                        searchingForDestination = true // Default to searching for destination
                        showingLocationSearch = true
                    }) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                    }
                    Text("Search")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Zoom In
                VStack(spacing: 4) {
                    Button(action: zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                    }
                    Text("Zoom In")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Zoom Out
                VStack(spacing: 4) {
                    Button(action: zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 30, height: 30)
                    }
                    Text("Zoom Out")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    // MARK: - UPDATED: Map Section (removed traffic overlay)
    private var mapSection: some View {
        ZStack {
            // Base map
            Map(
                coordinateRegion: $mapRegion,
                interactionModes: .all,
                showsUserLocation: true,
                userTrackingMode: .none,
                annotationItems: mapAnnotations
            ) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    Circle()
                        .fill(annotation.color)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
            }
            .mapStyle(getMapStyle())
            // REMOVED: Traffic overlay
            
            // Simple route line overlay
            if let route = routeManager.route {
                SimpleRouteOverlay(route: route, mapRegion: mapRegion)
            }
            
            // UPDATED: Map controls (removed traffic button)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        // User Location Button
                        Button(action: centerOnUserLocation) {
                            Image(systemName: "location.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Circle())
                        }
                        
                        // Fit Route Button
                        if routeManager.route != nil {
                            Button(action: fitRouteInView) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.green.opacity(0.8))
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Map Type Button
                        Button(action: cycleMapType) {
                            Image(systemName: mapTypeIcon)
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.purple.opacity(0.8))
                                .clipShape(Circle())
                        }
                        
                        // NEW: Search Button
                        Button(action: {
                            searchingForDestination = true
                            showingLocationSearch = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.orange.opacity(0.8))
                                .clipShape(Circle())
                        }
                        
                        // REMOVED: Traffic button
                    }
                    .padding(.trailing, 15)
                }
                Spacer()
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var progressSection: some View {
        VStack(spacing: 15) {
            // Progress Gauge
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: 180, height: 180)
                
                // Progress arc
                Circle()
                    .trim(from: 0, to: journeyProgress * 0.75)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .green]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))
                    .frame(width: 180, height: 180)
                    .animation(.easeInOut(duration: 0.5), value: journeyProgress)
                
                // Progress text
                VStack(spacing: 2) {
                    Text("\(Int(journeyProgress * 100))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("%")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress Bar
            VStack(spacing: 8) {
                HStack {
                    Text("0%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("50%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("100%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: journeyProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
            .padding(.horizontal, 20)
            
            // Distance Information
            if isTrackingJourney, let route = routeManager.route {
                HStack(spacing: 20) {
                    VStack {
                        Text(String(format: "%.1f", route.distance / 1000))
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("Route km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack {
                        Text(String(format: "%.1f", traveledDistance / 1000))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text("Completed km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack {
                        Text(String(format: "%.1f", (route.distance - traveledDistance) / 1000))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text("Remaining km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .frame(height: isTrackingJourney ? 340 : 280)
    }
    
    // MARK: - Helper Properties and Functions
    
    private var canStartJourney: Bool {
        startLocation != nil && destinationLocation != nil && routeManager.route != nil
    }
    
    private func calculateRouteIfReady() {
        guard let start = startLocation,
              let destination = destinationLocation else { return }
        
        routeManager.calculateRoute(from: start, to: destination, transportType: .walking)
    }
    
    private func updateMapRegion() {
        var coordinates: [CLLocationCoordinate2D] = []
        
        if let start = startLocation {
            coordinates.append(start.coordinate)
        }
        
        if let destination = destinationLocation {
            coordinates.append(destination.coordinate)
        }
        
        if let current = locationManager.currentLocation {
            coordinates.append(current.coordinate)
        }
        
        // Include search results in map region calculation
        for result in searchResults {
            coordinates.append(result.placemark.coordinate)
        }
        
        if !coordinates.isEmpty {
            let minLat = coordinates.map(\.latitude).min()!
            let maxLat = coordinates.map(\.latitude).max()!
            let minLon = coordinates.map(\.longitude).min()!
            let maxLon = coordinates.map(\.longitude).max()!
            
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            
            let span = MKCoordinateSpan(
                latitudeDelta: max(maxLat - minLat, 0.005) * 1.3,
                longitudeDelta: max(maxLon - minLon, 0.005) * 1.3
            )
            
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
    }
    
    private func startJourney() {
        guard let start = startLocation,
              let destination = destinationLocation,
              let route = routeManager.route else { return }
        
        isTrackingJourney = true
        routeManager.startJourney()
        locationManager.startTracking()
        
        locationManager.onLocationUpdate = { currentLocation in
            updateProgressIfTracking(currentLocation: currentLocation)
        }
    }
    
    private func updateProgressIfTracking(currentLocation: CLLocation) {
        guard isTrackingJourney else { return }
        
        journeyProgress = routeManager.updateProgressAndSpeed(
            currentLocation: currentLocation,
            previousLocation: previousLocation
        )
        traveledDistance = journeyProgress * routeManager.routeDistance
        
        previousLocation = currentLocation
        
        if let destination = destinationLocation {
            let distanceToDestination = currentLocation.distance(from: destination)
            if distanceToDestination < 50 {
                journeyProgress = 1.0
                traveledDistance = routeManager.routeDistance
            }
        }
    }
    
    private func stopJourney() {
        isTrackingJourney = false
        journeyProgress = 1.0
    }
    
    private func resetJourney() {
        isTrackingJourney = false
        journeyProgress = 0.0
        traveledDistance = 0.0
        startLocation = nil
        destinationLocation = nil
        previousLocation = nil
        locationManager.stopTracking()
        routeManager.clearRoute()
        // Clear search results
        searchResults.removeAll()
        searchText = ""
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func centerOnUserLocation() {
        if let currentLocation = locationManager.currentLocation {
            withAnimation(.easeInOut(duration: 1.0)) {
                mapRegion.center = currentLocation.coordinate
                mapRegion.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            }
        }
    }
    
    private func fitRouteInView() {
        guard let route = routeManager.route else { return }
        
        let routeRect = route.polyline.boundingMapRect
        let region = MKCoordinateRegion(routeRect)
        
        withAnimation(.easeInOut(duration: 1.0)) {
            mapRegion = MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(
                    latitudeDelta: region.span.latitudeDelta * 1.2,
                    longitudeDelta: region.span.longitudeDelta * 1.2
                )
            )
        }
    }
    
    // MARK: - Map feature functions
    
    private func cycleMapType() {
        withAnimation(.easeInOut(duration: 0.5)) {
            switch mapType {
            case .standard:
                mapType = .satellite
            case .satellite:
                mapType = .hybrid
            default:
                mapType = .standard
            }
        }
        
        let typeName = mapTypeName
        print("Map switched to: \(typeName)")
    }
    
    // REMOVED: toggleTraffic function - no longer needed
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.3)) {
            mapRegion.span = MKCoordinateSpan(
                latitudeDelta: max(mapRegion.span.latitudeDelta * 0.5, 0.001),
                longitudeDelta: max(mapRegion.span.longitudeDelta * 0.5, 0.001)
            )
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.3)) {
            mapRegion.span = MKCoordinateSpan(
                latitudeDelta: min(mapRegion.span.latitudeDelta * 2.0, 1.0),
                longitudeDelta: max(mapRegion.span.longitudeDelta * 2.0, 1.0)
            )
        }
    }
    
    struct LocationSearchView: View {
        @Binding var searchText: String
        @Binding var searchResults: [MKMapItem]
        @Binding var isSearching: Bool
        @Binding var isPresented: Bool
        let searchingForDestination: Bool
        let onLocationSelected: (CLLocation, Bool) -> Void
        
        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // Search bar
                    VStack(spacing: 10) {
                        Text(searchingForDestination ? "Search Destination" : "Search Start Location")
                            .font(.headline)
                            .padding(.top)
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField("Enter location name...", text: $searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    performSearch()
                                }
                            
                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                    .background(Color(UIColor.systemBackground))
                    
                    // Search results
                    if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                        VStack(spacing: 20) {
                            Image(systemName: "location.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No locations found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Try different keywords")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchResults, id: \.self) { mapItem in
                            Button(action: {
                                let location = CLLocation(
                                    latitude: mapItem.placemark.coordinate.latitude,
                                    longitude: mapItem.placemark.coordinate.longitude
                                )
                                onLocationSelected(location, searchingForDestination)
                                isPresented = false
                            }) {
                                VStack(alignment: .leading) {
                                    Text(mapItem.name ?? "Unknown Location")
                                        .font(.headline)
                                    if let address = mapItem.placemark.title {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                if !newValue.isEmpty && newValue.count >= 3 {
                    performSearch()
                }
            }
        }
        
        private func performSearch() {
            guard !searchText.isEmpty else { return }
            
            isSearching = true
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchText
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7662),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                DispatchQueue.main.async {
                    isSearching = false
                    searchResults = response?.mapItems ?? []
                }
            }
        }
    }
    
    // MARK: - Supporting Types
    struct SimpleMapAnnotation: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let color: Color
        let title: String
    }
    
    struct LocationPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }
    
    // MARK: - Add other missing views (simplified versions)
    struct WaypointPickerView: View {
        @ObservedObject var routeManager: RouteManager
        @Binding var isPresented: Bool
        @Binding var addingWaypoint: Bool
        
        var body: some View {
            Text("Waypoint Picker - TODO")
            Button("Cancel") {
                isPresented = false
            }
        }
    }
    
    struct LocationPickerView: View {
        @Binding var selectedLocation: CLLocation?
        @Binding var isPresented: Bool
        let title: String
        
        var body: some View {
            Text("Location Picker - TODO")
            Button("Cancel") {
                isPresented = false
            }
        }
    }
    
    struct SimpleRouteOverlay: View {
        let route: MKRoute
        let mapRegion: MKCoordinateRegion
        
        var body: some View {
            EmptyView() // Simplified for now
        }
    }
    
    // MARK: - Preview
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
        
        
        // MARK: - Supporting Views
        
        // MARK: - Waypoint Picker View
        struct WaypointPickerView: View {
            @ObservedObject var routeManager: RouteManager
            @Binding var isPresented: Bool
            @Binding var addingWaypoint: Bool
            
            @State private var region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7662),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            @State private var selectedCoordinate: CLLocationCoordinate2D?
            @StateObject private var localLocationManager = LocationManager()
            
            var body: some View {
                NavigationView {
                    VStack(spacing: 0) {
                        // Header with instruction
                        VStack(spacing: 10) {
                            Text("Add Waypoint")
                                .font(.headline)
                                .padding(.top)
                            
                            Text("Hold for 3 seconds on map to add a stop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .background(Color(UIColor.systemBackground))
                        
                        // Interactive Map with overlay
                        ZStack {
                            Map(coordinateRegion: $region, interactionModes: .all, annotationItems: selectedCoordinate != nil ? [LocationPin(coordinate: selectedCoordinate!)] : []) { pin in
                                MapPin(coordinate: pin.coordinate, tint: .orange)
                            }
                            .onLongPressGesture(minimumDuration: 3.0, maximumDistance: 50) {
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
                                            .foregroundColor(.orange)
                                            .background(Circle().fill(Color.white).frame(width: 35, height: 35))
                                            .shadow(radius: 2)
                                        Text("Hold 3s")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange)
                                            .cornerRadius(4)
                                            .shadow(radius: 1)
                                    }
                                    Spacer()
                                }
                                Spacer()
                            }
                            .allowsHitTesting(false)
                        }
                        
                        // Selected location info
                        if let coordinate = selectedCoordinate {
                            VStack(spacing: 5) {
                                Text("Selected Waypoint:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding()
                            .background(Color(UIColor.systemGray6))
                        }
                        
                        // Existing waypoints list
                        if !routeManager.waypoints.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Route:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(routeManager.waypoints.enumerated()), id: \.offset) { index, waypoint in
                                            WaypointCard(
                                                waypoint: waypoint,
                                                index: index,
                                                isFirst: index == 0,
                                                isLast: index == routeManager.waypoints.count - 1,
                                                onRemove: {
                                                    if index > 0 && index < routeManager.waypoints.count - 1 {
                                                        routeManager.removeWaypoint(at: index)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
                        
                        Spacer()
                        
                        // Action buttons
                        HStack(spacing: 20) {
                            Button("Cancel") {
                                addingWaypoint = false
                                isPresented = false
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                            
                            Button("Add Waypoint") {
                                if let coordinate = selectedCoordinate {
                                    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                                    routeManager.addWaypoint(location)
                                }
                                addingWaypoint = false
                                isPresented = false
                            }
                            .disabled(selectedCoordinate == nil)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedCoordinate != nil ? Color.orange : Color.gray)
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
                    } else {
                        region.center = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7662)
                    }
                }
            }
        }
        
        // MARK: - Waypoint Card View
        struct WaypointCard: View {
            let waypoint: CLLocation
            let index: Int
            let isFirst: Bool
            let isLast: Bool
            let onRemove: () -> Void
            
            var body: some View {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: isFirst ? "play.fill" : isLast ? "flag.fill" : "mappin")
                            .foregroundColor(isFirst ? .green : isLast ? .red : .orange)
                        
                        if !isFirst && !isLast {
                            Button(action: onRemove) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Text(isFirst ? "Start" : isLast ? "End" : "Stop \(index)")
                        .font(.caption2)
                        .fontWeight(.medium)
                    
                    Text(String(format: "%.3f, %.3f", waypoint.coordinate.latitude, waypoint.coordinate.longitude))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .frame(width: 80)
            }
        }
        
        // MARK: - Location Pin for Map (Shared)
        //struct LocationPin: Identifiable {
        //    let id = UUID()
        //    let coordinate: CLLocationCoordinate2D
        //}
        
        // MARK: - Supporting Types
        struct SimpleMapAnnotation: Identifiable {
            let id = UUID()
            let coordinate: CLLocationCoordinate2D
            let color: Color
            let title: String
        }
        
        // MARK: - Simple Route Overlay
        struct SimpleRouteOverlay: View {
            let route: MKRoute
            let mapRegion: MKCoordinateRegion
            
            var body: some View {
                GeometryReader { geometry in
                    Path { path in
                        let points = route.polyline.points()
                        let pointCount = route.polyline.pointCount
                        
                        guard pointCount > 0 else { return }
                        
                        // Convert route coordinates to screen points
                        var screenPoints: [CGPoint] = []
                        
                        for i in 0..<pointCount {
                            let coordinate = points[i].coordinate
                            let screenPoint = coordinateToScreenPoint(
                                coordinate: coordinate,
                                mapRegion: mapRegion,
                                frameSize: geometry.size
                            )
                            screenPoints.append(screenPoint)
                        }
                        
                        // Draw path
                        if let firstPoint = screenPoints.first {
                            path.move(to: firstPoint)
                            
                            for point in screenPoints.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                }
                .allowsHitTesting(false)
            }
            
            private func coordinateToScreenPoint(coordinate: CLLocationCoordinate2D, mapRegion: MKCoordinateRegion, frameSize: CGSize) -> CGPoint {
                // Calculate relative position within the map region
                let latRange = mapRegion.span.latitudeDelta
                let lonRange = mapRegion.span.longitudeDelta
                
                let relativeX = (coordinate.longitude - (mapRegion.center.longitude - lonRange / 2)) / lonRange
                let relativeY = ((mapRegion.center.latitude + latRange / 2) - coordinate.latitude) / latRange
                
                // Convert to screen coordinates
                let screenX = relativeX * frameSize.width
                let screenY = relativeY * frameSize.height
                
                return CGPoint(x: screenX, y: screenY)
            }
        }
        
        // MARK: - Preview
        #Preview {
            ContentView()
        }
    }
}

