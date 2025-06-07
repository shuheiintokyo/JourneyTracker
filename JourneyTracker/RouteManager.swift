import Foundation
import CoreLocation
import MapKit

class RouteManager: ObservableObject {
    @Published var route: MKRoute?
    @Published var routeDistance: Double = 0.0
    @Published var isCalculatingRoute = false
    @Published var routeError: String?
    @Published var waypoints: [CLLocation] = []
    @Published var routeSegments: [MKRoute] = []
    
    // Speed tracking for dynamic arrival time
    @Published var averageSpeed: Double = 1.4 // Default walking speed: 1.4 m/s (5 km/h)
    @Published var currentSpeed: Double = 0.0
    @Published var estimatedArrivalTime: Date?
    @Published var remainingTime: TimeInterval = 0
    
    private var speedHistory: [Double] = []
    private var lastSpeedUpdate = Date()
    private var journeyStartTime: Date?
    
    func addWaypoint(_ location: CLLocation) {
        waypoints.append(location)
        // Recalculate route with new waypoint
        if waypoints.count >= 2 {
            calculateRouteWithWaypoints()
        }
    }
    
    func removeWaypoint(at index: Int) {
        guard index < waypoints.count else { return }
        waypoints.remove(at: index)
        if waypoints.count >= 2 {
            calculateRouteWithWaypoints()
        }
    }  
    func clearWaypoints() {
        waypoints.removeAll()
        routeSegments.removeAll()
        route = nil
        routeDistance = 0.0
    }
    
    func calculateRoute(from start: CLLocation, to destination: CLLocation, transportType: MKDirectionsTransportType = .walking) {
        // Clear any existing waypoints and calculate direct route
        waypoints = [start, destination]
        calculateRouteWithWaypoints(transportType: transportType)
    }
    
    func startJourney() {
        journeyStartTime = Date()
        updateEstimatedArrival()
    }
    
    func updateSpeed(currentLocation: CLLocation, previousLocation: CLLocation?, timeInterval: TimeInterval) {
        guard let previous = previousLocation, timeInterval > 0 else { return }
        
        let distance = currentLocation.distance(from: previous)
        let speed = distance / timeInterval
        
        // Filter out unrealistic speeds (GPS errors)
        if speed < 10.0 && speed > 0.1 { // Between 0.1 m/s and 10 m/s
            currentSpeed = speed
            speedHistory.append(speed)
            
            // Keep only last 10 speed measurements for rolling average
            if speedHistory.count > 10 {
                speedHistory.removeFirst()
            }
            
            // Update average speed
            averageSpeed = speedHistory.reduce(0, +) / Double(speedHistory.count)
            updateEstimatedArrival()
        }
    }
    
    private func calculateRouteWithWaypoints(transportType: MKDirectionsTransportType = .walking) {
        guard waypoints.count >= 2 else { return }
        
        isCalculatingRoute = true
        routeError = nil
        routeSegments.removeAll()
        
        let group = DispatchGroup()
        var calculatedSegments: [MKRoute] = []
        var hasError = false
        
        // Calculate route segments between consecutive waypoints
        for i in 0..<(waypoints.count - 1) {
            group.enter()
            
            let start = waypoints[i]
            let end = waypoints[i + 1]
            
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
            request.transportType = transportType
            request.requestsAlternateRoutes = false
            
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                defer { group.leave() }
                
                if let error = error {
                    hasError = true
                    DispatchQueue.main.async {
                        self.routeError = "Could not calculate route segment: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let route = response?.routes.first else {
                    hasError = true
                    DispatchQueue.main.async {
                        self.routeError = "No route found for segment"
                    }
                    return
                }
                
                calculatedSegments.append(route)
            }
        }
        
        group.notify(queue: .main) {
            self.isCalculatingRoute = false
            
            if !hasError && !calculatedSegments.isEmpty {
                self.routeSegments = calculatedSegments.sorted { segments1, segments2 in
                    // Sort by order in waypoints array
                    return true // They're already in order from the loop
                }
                
                // Combine segments into single route (use first segment as primary)
                self.route = calculatedSegments.first
                self.routeDistance = calculatedSegments.reduce(0) { $0 + $1.distance }
                self.updateEstimatedArrival()
            }
        }
    }
    
    private func updateEstimatedArrival() {
        guard routeDistance > 0, averageSpeed > 0 else { return }
        
        remainingTime = routeDistance / averageSpeed
        
        if let startTime = journeyStartTime {
            estimatedArrivalTime = startTime.addingTimeInterval(remainingTime)
        } else {
            estimatedArrivalTime = Date().addingTimeInterval(remainingTime)
        }
    }
    
    func calculateProgressOnRoute(currentLocation: CLLocation) -> Double {
        guard let route = route else { return 0.0 }
        
        // Find the closest point on the route to current location
        let polyline = route.polyline
        let closestPoint = findClosestPointOnRoute(currentLocation: currentLocation, polyline: polyline)
        
        return closestPoint.distanceFromStart / routeDistance
    }
    
    func updateProgressAndSpeed(currentLocation: CLLocation, previousLocation: CLLocation?) -> Double {
        // Update speed tracking
        if let previous = previousLocation {
            let timeInterval = Date().timeIntervalSince(lastSpeedUpdate)
            if timeInterval >= 2.0 { // Update every 2 seconds
                updateSpeed(currentLocation: currentLocation, previousLocation: previous, timeInterval: timeInterval)
                lastSpeedUpdate = Date()
            }
        }
        
        // Calculate progress
        let progress = calculateProgressOnRoute(currentLocation: currentLocation)
        
        // Update remaining distance and time
        let remainingDistance = routeDistance * (1.0 - progress)
        remainingTime = remainingDistance / averageSpeed
        
        if let startTime = journeyStartTime {
            estimatedArrivalTime = Date().addingTimeInterval(remainingTime)
        }
        
        return progress
    }
    
    private func findClosestPointOnRoute(currentLocation: CLLocation, polyline: MKPolyline) -> (distanceFromStart: Double, closestDistance: Double) {
        let points = polyline.points()
        let pointCount = polyline.pointCount
        
        var closestDistance = Double.infinity
        var distanceFromStart = 0.0
        var currentRouteDistance = 0.0
        
        // Check each segment of the route
        for i in 0..<pointCount {
            let routePoint = points[i]
            let routeLocation = CLLocation(
                latitude: routePoint.coordinate.latitude,
                longitude: routePoint.coordinate.longitude
            )
            
            let distanceToPoint = currentLocation.distance(from: routeLocation)
            
            if distanceToPoint < closestDistance {
                closestDistance = distanceToPoint
                distanceFromStart = currentRouteDistance
            }
            
            // Calculate distance along route to this point
            if i > 0 {
                let previousPoint = points[i - 1]
                let previousLocation = CLLocation(
                    latitude: previousPoint.coordinate.latitude,
                    longitude: previousPoint.coordinate.longitude
                )
                currentRouteDistance += routeLocation.distance(from: previousLocation)
            }
        }
        
        return (distanceFromStart, closestDistance)
    }
    
    func getFormattedSpeed() -> String {
        let kmh = currentSpeed * 3.6 // Convert m/s to km/h
        return String(format: "%.1f km/h", kmh)
    }
    
    func getFormattedArrivalTime() -> String {
        guard let arrivalTime = estimatedArrivalTime else { return "Calculating..." }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalTime)
    }
    
    func getFormattedRemainingTime() -> String {
        let hours = Int(remainingTime) / 3600
        let minutes = Int(remainingTime) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func clearRoute() {
        route = nil
        routeDistance = 0.0
        routeError = nil
        waypoints.removeAll()
        routeSegments.removeAll()
        speedHistory.removeAll()
        currentSpeed = 0.0
        averageSpeed = 1.4
        estimatedArrivalTime = nil
        remainingTime = 0
        journeyStartTime = nil
    }
}
