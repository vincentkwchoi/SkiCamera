import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Header
                    Text("Controls & Cues")
                        .font(.title)
                        .bold()
                        .padding(.top)
                    
                    // Intro
                    Text("Operate without taking off your gloves. Here's how")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // Controls Table
                    VStack(spacing: 0) {
                        // Header Row
                        HStack(alignment: .top) {
                            Text("Action")
                                .bold()
                                .frame(width: 80, alignment: .leading)
                            Text("Physical")
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Voice")
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 14))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        
                        // Rows
                        Group {
                            HelpRow(action: "Record", physical: "Dbl-Click Vol", voice: "'Start'")
                            HelpRow(action: "Stop", physical: "Dbl-Click Vol", voice: "'Stop'")
                            HelpRow(action: "Zoom In", physical: "Hold Vol Up", voice: "'Zoom In'")
                            HelpRow(action: "Zoom Out", physical: "Hold Vol Down", voice: "'Zoom Out'")
                            HelpRow(action: "Stop Zoom", physical: "Release Btn", voice: "'Hold'")
                            HelpRow(action: "Auto Zoom", physical: "Press Both", voice: "'Auto'")
                            HelpRow(action: "Photo", physical: "-", voice: "'Photo'")
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HelpRow: View {
    let action: String
    let physical: String
    let voice: String
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Text(action)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 80, alignment: .leading)
                
                Text(physical)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
                
                Text(voice)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
                .padding(.leading, 16)
        }
    }
}


#Preview {
    HelpView()
}
