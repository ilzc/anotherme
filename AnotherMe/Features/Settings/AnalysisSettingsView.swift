import SwiftUI

struct AnalysisSettingsView: View {
    @AppStorage("modeling.dailyHour") var dailyHour = 23
    @AppStorage("modeling.weeklyDay") var weeklyDay = 1
    @AppStorage("modeling.threshold") var threshold = 200
    @AppStorage("modeling.enabled") var enabled = true

    var body: some View {
        ScrollView {
            Form {
                Section("Auto Analysis") {
                    Toggle("Enable automatic modeling analysis", isOn: $enabled)
                }
                Section("Scheduled Trigger") {
                    Picker("Daily analysis time", selection: $dailyHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text("\(hour):00").tag(hour)
                        }
                    }
                    Picker("Weekly analysis day", selection: $weeklyDay) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }
                }
                Section("Threshold Trigger") {
                    Stepper("Trigger after \(threshold) new records", value: $threshold, in: 50...1000, step: 50)
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    AnalysisSettingsView()
}
