import SwiftUI

/// Permission check view shown on first launch.
/// Blocks entry to the main interface until both Screen Recording
/// and Accessibility permissions are granted.
struct PermissionCheckView: View {
    let permissionManager: PermissionManager
    var onAllGranted: () -> Void

    @State private var isWaiting = false

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("System Permissions Required")
                    .font(.largeTitle.bold())

                Text("AnotherMe needs the following permissions to work properly.\nPlease grant each one to continue.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Permission rows
            VStack(spacing: 16) {
                permissionRow(
                    title: "Screen Recording",
                    description: "Used to capture screen content and analyze your activity",
                    status: permissionManager.screenRecordingStatus,
                    action: { permissionManager.openScreenRecordingSettings() }
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Used to monitor window switches and keyboard/mouse activity",
                    status: permissionManager.accessibilityStatus,
                    action: { permissionManager.requestAccessibility() }
                )
            }
            .padding(.horizontal, 24)

            // Status / action area
            if permissionManager.allPermissionsGranted {
                Button(action: onAllGranted) {
                    Label("Get Started", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if isWaiting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for permissions...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Check Permissions") {
                    startWaiting()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(48)
        .frame(width: 520, height: 480)
        .task {
            // Auto-start polling on appear
            startWaiting()
        }
        .onChange(of: permissionManager.allPermissionsGranted) { _, granted in
            if granted {
                isWaiting = false
                onAllGranted()
            }
        }
    }

    // MARK: - Permission Row

    private func permissionRow(
        title: String,
        description: String,
        status: PermissionStatus,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            // Status icon
            statusIcon(for: status)
                .frame(width: 32, height: 32)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action button
            if status != .granted {
                Button("Open Settings") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status == .granted ? Color.green.opacity(0.08) : Color.red.opacity(0.06))
        )
    }

    @ViewBuilder
    private func statusIcon(for status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        case .notDetermined:
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Polling

    private func startWaiting() {
        guard !isWaiting, !permissionManager.allPermissionsGranted else { return }
        isWaiting = true
        Task {
            await permissionManager.waitForPermissions()
            // waitForPermissions returns when both are granted
        }
    }
}

#Preview {
    PermissionCheckView(
        permissionManager: PermissionManager(),
        onAllGranted: {}
    )
}
