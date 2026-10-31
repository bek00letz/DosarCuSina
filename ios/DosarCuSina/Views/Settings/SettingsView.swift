import SwiftUI

public struct SettingsView: View {
    @State private var apiKeyInput: String = ""
    @State private var isKeySaved: Bool = false
    @State private var showingSaveAlert: Bool = false
    @State private var showingDeleteAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section: Gemini AI API Key (BYOK)
                Section {
                    SecureField("Cheie Gemini API (AI Studio)", text: $apiKeyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    HStack {
                        Button("Salvează în Keychain") {
                            saveKey()
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Spacer()
                        
                        if isKeySaved {
                            Button("Șterge Cheia", role: .destructive) {
                                deleteKey()
                            }
                        }
                    }
                } header: {
                    Text("Inteligență Artificială (Scanare Avansată)")
                } footer: {
                    Text("Aplicația folosește implicit scanare locală (on-device) prin Apple Vision. Pentru extragerea completă a facturilor complexe poți adăuga opțional o cheie gratuită de pe Google AI Studio. Cheia este stocată securizat în iOS Keychain.")
                }
                
                // Section: Cloud & Confidențialitate
                Section("Sincronizare & Securitate") {
                    HStack {
                        Label("Sincronizare iCloud", systemImage: "icloud.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("Activă (CloudKit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Stocare Date", systemImage: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Local-First (Pe dispozitiv)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Section: Despre Aplicație
                Section("Despre") {
                    HStack {
                        Text("Aplicație")
                        Spacer()
                        Text("Dosar cu Șină")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Versiune")
                        Spacer()
                        Text("1.0.0 (Alpha)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Arhitectură")
                        Spacer()
                        Text("SwiftUI + SwiftData")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Setări")
            .onAppear {
                checkKeyStatus()
            }
            .alert("Cheie Salvată", isPresented: $showingSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cheia Gemini API a fost salvată în Keychain-ul dispozitivului.")
            }
            .alert("Cheie Ștearsă", isPresented: $showingDeleteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Cheia Gemini API a fost eliminată.")
            }
        }
    }
    
    private func checkKeyStatus() {
        if let key = KeychainManager.getGeminiAPIKey(), !key.isEmpty {
            isKeySaved = true
            apiKeyInput = key
        } else {
            isKeySaved = false
            apiKeyInput = ""
        }
    }
    
    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeychainManager.saveGeminiAPIKey(trimmed) {
            isKeySaved = true
            showingSaveAlert = true
        }
    }
    
    private func deleteKey() {
        if KeychainManager.deleteGeminiAPIKey() {
            isKeySaved = false
            apiKeyInput = ""
            showingDeleteAlert = true
        }
    }
}
