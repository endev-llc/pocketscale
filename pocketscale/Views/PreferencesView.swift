//
//  PreferencesView.swift
//  pocketscale
//
//  Created by Jake Adams on 7/28/25.
//

import SwiftUI

struct PreferencesView: View {
    @Binding var isPresented: Bool
    @AppStorage("unitPreference") private var unitPreference: UnitPreference = .grams

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Measurement Units")) {
                    Picker("Preferred Units", selection: $unitPreference) {
                        ForEach(UnitPreference.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

enum UnitPreference: String, CaseIterable, Identifiable {
    case grams = "Grams"
    case ounces = "Ounces"

    var id: String { self.rawValue }
}
