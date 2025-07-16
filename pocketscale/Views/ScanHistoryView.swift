//
//  ScanHistoryView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/16/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Scan Data Model
struct Scan: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    let userId: String
    let timestamp: Timestamp
    let imageUrl: String
    let overall_food_item: String
    let constituent_food_items: [ConstituentFoodItem]
    let total_weight_grams: Int
    let confidence_percentage: Int

    static func == (lhs: Scan, rhs: Scan) -> Bool {
        lhs.id == rhs.id
    }
}


// MARK: - Scan History View Model
@MainActor
class ScanHistoryViewModel: ObservableObject {
    @Published var scans = [Scan]()
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func fetchScans() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not logged in."
            return
        }

        isLoading = true

        // Listen for real-time updates to the user's scans
        listener = db.collection("users").document(userId).collection("userScans")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] (querySnapshot, error) in
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.errorMessage = "Error fetching scans: \(error.localizedDescription)"
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    self.scans = []
                    return
                }

                // Decode documents into Scan objects
                self.scans = documents.compactMap { doc -> Scan? in
                    try? doc.data(as: Scan.self)
                }
            }
    }

    func stopListening() {
        listener?.remove()
    }
}


// MARK: - Main Scan History View
struct ScanHistoryView: View {
    @StateObject private var viewModel = ScanHistoryViewModel()
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            ZStack {
                // Consistent gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color.accentColor.opacity(0.15),
                        Color(.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack {
                    if viewModel.isLoading {
                        ProgressView("Loading History...")
                    } else if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    } else if viewModel.scans.isEmpty {
                        Text("No Scan History")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(viewModel.scans) { scan in
                                    ScanHistoryCard(scan: scan)
                                }
                            }
                            .padding()
                        }
                    }
                }
                .navigationTitle("Scan History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                }
            }
            .onAppear {
                viewModel.fetchScans()
            }
            .onDisappear {
                viewModel.stopListening()
            }
        }
    }
}


// MARK: - Scan History Card View
struct ScanHistoryCard: View {
    let scan: Scan

    var body: some View {
        VStack(spacing: 16) {
            // Asynchronously load the image from the URL
            AsyncImageView(url: URL(string: scan.imageUrl))
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    VStack {
                        Spacer()
                        HStack {
                            Text(scan.timestamp.dateValue(), style: .date)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                            Spacer()
                        }
                    }
                    .padding(8)
                )

            // Re-using the weight results display logic
            weightResultsContent
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }

    private var weightResultsContent: some View {
        VStack(spacing: 16) {
             HStack(alignment: .bottom, spacing: 8) {
                Text("\(String(format: "%.1f", Double(scan.total_weight_grams) * 0.035274))")
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundColor(.primary)
                    .kerning(-1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("oz")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("(\(scan.total_weight_grams)g)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .offset(y: -8)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ITEM")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Text(scan.overall_food_item)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("CONFIDENCE")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Text("\(scan.confidence_percentage)%")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(confidenceColor(scan.confidence_percentage))
                }
            }
        }
    }

    private func confidenceColor(_ confidence: Int) -> Color {
        if confidence >= 80 { return .green }
        if confidence >= 60 { return .orange }
        return .red
    }
}

// MARK: - Asynchronous Image Loading View
struct AsyncImageView: View {
    let url: URL?
    @State private var image: UIImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else if isLoading {
                ZStack {
                    Color.gray.opacity(0.1)
                    ProgressView()
                }
            } else {
                Color.gray.opacity(0.1) // Placeholder
            }
        }
        .onAppear(perform: loadImage)
    }

    private func loadImage() {
        guard let url = url, image == nil else { return }
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let loadedImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                    self.isLoading = false
                }
            }
        }.resume()
    }
}
