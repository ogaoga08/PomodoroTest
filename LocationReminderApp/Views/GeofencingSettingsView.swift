import SwiftUI
import MapKit
import CoreLocation
import Combine

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct GeofencingSettingsView: View {
    @State private var homeLocation: CLLocationCoordinate2D?
    @State private var homeAddress: String = "未設定"
    private let geofenceRadius: Double = 50 // 固定値（最小範囲）
    private let isAutoReconnectEnabled: Bool = true // 固定値（オン）
    @State private var isUWBConnected: Bool = false
    @State private var lastReconnectTime: Date?
    @State private var showingLocationPicker = false
    @State private var showingReconnectAlert = false
    @State private var reconnectMessage = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
    )
    @StateObject private var locationManager = LocationManager()
    @State private var hasInitializedMainLocation = false
    
    var body: some View {
        NavigationView {
            List {
                homeLocationSection
                informationSection
            }
            .navigationTitle("ジオフェンシング設定")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingLocationPicker) {
            HomeLocationPickerView(
                selectedLocation: $homeLocation,
                selectedAddress: $homeAddress,
                region: $region
            )
        }
        .alert("再接続結果", isPresented: $showingReconnectAlert) {
            Button("OK") { }
        } message: {
            Text(reconnectMessage)
        }
        .onAppear {
            loadSavedData()
            locationManager.requestPermission()
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            handleAuthorizationChange(status)
        }
        .onChange(of: locationManager.currentLocation) { currentLocation in
            handleLocationUpdate(currentLocation)
        }
        .onChange(of: homeLocation) { _ in saveHomeLocation() }
        .onChange(of: homeAddress) { _ in saveHomeAddress() }
    }
    
    @ViewBuilder
    private var homeLocationSection: some View {
        Section("自宅位置設定") {
            HStack {
                Image(systemName: "house.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("自宅住所")
                        .foregroundColor(.primary)
                    
                    Text(homeAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("変更") {
                    showingLocationPicker = true
                }
                .foregroundColor(.blue)
                .font(.caption)
            }
            
            if let homeLocation = homeLocation {
                Map(coordinateRegion: .constant(MKCoordinateRegion(
                    center: homeLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
                )), annotationItems: [HomeAnnotation(coordinate: homeLocation)]) { annotation in
                    MapPin(coordinate: annotation.coordinate, tint: .blue)
                }
                .frame(height: 200)
                .cornerRadius(12)
                .disabled(true)
            }
        }
    }
    
    @ViewBuilder
    private var informationSection: some View {
        Section("ジオフェンシングについて") {
            VStack(alignment: .leading, spacing: 12) {
                InfoRowView(
                    number: 1,
                    title: "自動再接続機能",
                    description: "自宅に帰宅したことを検知すると、自動的にUWBデバイスとの再接続を試みます"
                )
                
                InfoRowView(
                    number: 2,
                    title: "Secure Bubble機能",
                    description: "UWBデバイスとの接続が確立されると、Screen Time制限機能が再開されます"
                )
                
                InfoRowView(
                    number: 3,
                    title: "バッテリー使用量",
                    description: "位置監視により若干の電力を消費しますが、UWB機能の維持に必要です"
                )
            }
            .padding(.vertical, 8)
        }
    }
    
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        }
    }
    
    private func handleLocationUpdate(_ currentLocation: CLLocationCoordinate2D?) {
        if let currentLocation = currentLocation, homeLocation == nil, !hasInitializedMainLocation {
            withAnimation(.easeInOut(duration: 1.0)) {
                region = MKCoordinateRegion(
                    center: currentLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )
            }
            hasInitializedMainLocation = true
        }
    }
    
    private func performManualReconnect() {
        // UWB再接続の実装
        // 実際の実装では、NISessionの再開やUWBデバイスとの通信を行う
        lastReconnectTime = Date()
        
        // 模擬的な再接続処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isUWBConnected = Bool.random() // 実際の実装では成功/失敗の判定
            reconnectMessage = isUWBConnected ? "UWBデバイスに正常に接続しました" : "UWBデバイスへの接続に失敗しました"
            showingReconnectAlert = true
        }
    }
    
    private func testGeofenceEntry() {
        // ジオフェンス侵入のテスト
        reconnectMessage = "帰宅を検知しました。UWB再接続を開始します..."
        showingReconnectAlert = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            performManualReconnect()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func loadSavedData() {
        // 保存されたホーム位置を読み込み
        if let latitudeData = UserDefaults.standard.object(forKey: "homeLatitude") as? Double,
           let longitudeData = UserDefaults.standard.object(forKey: "homeLongitude") as? Double {
            homeLocation = CLLocationCoordinate2D(latitude: latitudeData, longitude: longitudeData)
            
            // 地図の中心のみ更新（ズームレベルは保持）
            withAnimation(.easeInOut(duration: 0.5)) {
                region = MKCoordinateRegion(
                    center: homeLocation!,
                    span: region.span // 現在のspanを保持
                )
            }
        }
        
        // 保存された住所を読み込み
        if let savedAddress = UserDefaults.standard.string(forKey: "homeAddress") {
            homeAddress = savedAddress
        }
    }
    
    private func saveHomeLocation() {
        guard let location = homeLocation else { return }
        UserDefaults.standard.set(location.latitude, forKey: "homeLatitude")
        UserDefaults.standard.set(location.longitude, forKey: "homeLongitude")
    }
    
    private func saveHomeAddress() {
        UserDefaults.standard.set(homeAddress, forKey: "homeAddress")
    }
}

struct HomeAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    
    init(coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)) {
        self.coordinate = coordinate
    }
}

struct HomeLocationPickerView: View {
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var selectedAddress: String
    @Binding var region: MKCoordinateRegion
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @StateObject private var locationManager = LocationManager()
    @State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
    )
    
    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                searchBarSection
                currentLocationButtonSection
                searchResultsSection
                mapSection
                selectLocationButtonSection
            }
            .navigationTitle("自宅位置を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarItems
            }
        }
        .onAppear {
            setupView()
        }
        .onChange(of: locationManager.currentLocation) { currentLocation in
            handleLocationChange(currentLocation)
        }
    }
    
    @ViewBuilder
    private var searchBarSection: some View {
        SearchBar(text: $searchText, onSearchButtonClicked: performSearch)
            .padding(.horizontal)
    }
    
    @ViewBuilder
    private var currentLocationButtonSection: some View {
        HStack {
            Button(action: useCurrentLocation) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.white)
                    Text("現在地を使用")
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(locationManager.currentLocation == nil)
            
            Spacer()
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var searchResultsSection: some View {
        if !searchResults.isEmpty {
            List(searchResults, id: \.self) { item in
                VStack(alignment: .leading) {
                    Text(item.name ?? "")
                        .font(.headline)
                    
                    if let address = item.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onTapGesture {
                    selectLocation(item)
                }
            }
            .frame(maxHeight: 150)
        }
    }
    
    @ViewBuilder
    private var mapSection: some View {
        ZStack {
            Map(coordinateRegion: $mapRegion, annotationItems: selectedLocation != nil ? [LocationAnnotation(coordinate: selectedLocation!)] : []) { annotation in
                MapPin(coordinate: annotation.coordinate, tint: .blue)
            }
            .frame(height: 350)
            .cornerRadius(12)
            
            if selectedLocation == nil {
                VStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                        .background(Circle().fill(Color.white))
                        .shadow(radius: 3)
                    
                    Text("地図を移動して位置を調整")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .offset(y: 10)
                }
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var selectLocationButtonSection: some View {
        Button(action: {
            selectedLocation = mapRegion.center
            reverseGeocode(coordinate: mapRegion.center)
        }) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.white)
                Text("この位置を選択")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("キャンセル") {
                dismiss()
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("完了") {
                dismiss()
            }
            .disabled(selectedLocation == nil)
        }
    }
    
    private func setupView() {
        mapRegion = region
        locationManager.requestPermission()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if locationManager.authorizationStatus == .authorizedWhenInUse || 
               locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation()
            }
        }
    }
    
    private func handleLocationChange(_ currentLocation: CLLocationCoordinate2D?) {
        guard let currentLocation = currentLocation else { return }
        
        withAnimation(.easeInOut(duration: 1.0)) {
            mapRegion = MKCoordinateRegion(
                center: currentLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        }
    }
    
    private func performSearch() {
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = mapRegion
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                isSearching = false
                if let response = response {
                    searchResults = response.mapItems
                }
            }
        }
    }
    
    private func selectLocation(_ mapItem: MKMapItem) {
        selectedLocation = mapItem.placemark.coordinate
        selectedAddress = mapItem.placemark.title ?? "選択された住所"
        
        // 現在のズームレベルを完全に保持しながら中心位置のみ変更
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(
                center: mapItem.placemark.coordinate,
                span: mapRegion.span // 現在のズームレベルを保持
            )
        }
        
        searchResults = []
        searchText = ""
    }
    
    private func useCurrentLocation() {
        guard let currentLocation = locationManager.currentLocation else { return }
        
        selectedLocation = currentLocation
        reverseGeocode(coordinate: currentLocation)
        
        // 現在地に移動（ズームレベルは完全に維持）
        withAnimation(.easeInOut(duration: 0.5)) {
            mapRegion = MKCoordinateRegion(
                center: currentLocation,
                span: mapRegion.span // 現在のズームレベルを保持
            )
        }
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let placemark = placemarks?.first {
                DispatchQueue.main.async {
                    selectedAddress = placemark.name ?? placemark.thoroughfare ?? "選択された住所"
                }
            }
        }
    }
}

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    var onSearchButtonClicked: () -> Void
    
    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.delegate = context.coordinator
        searchBar.placeholder = "住所を検索..."
        searchBar.searchBarStyle = .minimal
        return searchBar
    }
    
    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UISearchBarDelegate {
        let parent: SearchBar
        
        init(_ parent: SearchBar) {
            self.parent = parent
        }
        
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }
        
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.onSearchButtonClicked()
            searchBar.resignFirstResponder()
        }
    }
}

struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct InfoRowView: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(number).circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestPermission() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // 既に拒否されている場合は何もしない
            break
        case .authorizedWhenInUse, .authorizedAlways:
            // 既に許可されている場合は位置を取得
            requestLocation()
        @unknown default:
            manager.requestWhenInUseAuthorization()
        }
    }
    
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        manager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async {
            self.currentLocation = locations.last?.coordinate
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.requestLocation()
            }
        }
    }
}

#Preview {
    GeofencingSettingsView()
}

