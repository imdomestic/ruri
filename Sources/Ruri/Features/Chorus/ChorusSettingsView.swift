import SwiftUI
import RuriCore
import RuriLocalization

struct ChorusSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChorusPresentation.self) private var chorus
    @State private var url = ChorusSettings.defaultBaseURL
    @State private var token = ""
    @State private var result: String?
    @State private var checking = false
    var body: some View {
        Section(Messages.Chorus.title.localized) {
            TextField(Messages.Chorus.backendURL.localized, text: $url)
            SecureField(Messages.Chorus.token.localized, text: $token)
            HStack {
                Button(Messages.Servers.save.localized) { save() }
                Button(Messages.Chorus.testConnection.localized) { check() }.disabled(checking)
                if checking { ProgressView().controlSize(.small) }
            }
            if let result { Text(result).font(.caption).textSelection(.enabled) }
        }.task {
            do { url = try ChorusSettings.load(paths: model.basePaths).baseURL }
            catch { result = error.localizedDescription }
        }
    }
    private func save() {
        do {
            let settings = try ChorusSettings.configure(paths: model.basePaths, baseURL: url, token: token.isEmpty ? nil : token)
            url = settings.baseURL
            token = ""
            chorus.configurationRevision = UUID()
            result = Messages.Chorus.saved.localized
        } catch { result = error.localizedDescription }
    }
    private func check() {
        checking = true
        Task {
            defer { checking = false }
            do {
                let normalized = try ChorusSettings.normalizedURL(url)
                let client = try ChorusClient(baseURL: normalized, token: token.isEmpty ? ChorusTokenStore.load(baseURL: normalized) : token)
                struct Health: Decodable, Sendable { let status: String }
                let health = try await client.get(Health.self, "/v1/health")
                guard health.status == "ok" else { throw RuriError.message(Messages.Chorus.invalidResponse) }
                _ = try await client.meta()
                result = Messages.Chorus.connectionOK.localized
            } catch { result = error.localizedDescription }
        }
    }
}
