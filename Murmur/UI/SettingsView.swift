import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Engine and behavior settings arrive with M1 and M2.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 160)
    }
}
