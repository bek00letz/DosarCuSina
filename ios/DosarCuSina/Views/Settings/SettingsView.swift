import SwiftUI

public struct SettingsView: View {
    @State private var apiKeyInput: String = ""
    @State private var isKeySaved: Bool = false
    @State private var isValidatingKey: Bool = false
    @State private var validationSuccess: Bool? = nil
    @State private var showingSaveAlert: Bool = false
    @State private var showingDeleteAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section: Status Banner
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: isKeySaved ? "sparkles" : "bolt.shield.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isKeySaved ? .purple : .blue)
                            .frame(width: 48, height: 48)
                            .background((isKeySaved ? Color.purple : Color.blue).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isKeySaved ? "Modul Inteligent AI Activ" : "Modul Standard (On-Device)")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                            
                            Text(isKeySaved ? "Extragere automată avansată cu Gemini 2.0 Flash." : "Scanare 100% locală prin Apple Vision. Fără internet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Section: Gemini AI API Key (BYOK)
                Section {
                    SecureField(isKeySaved ? "Cheie configurată (••••••••)" : "Introdu cheia API Gemini", text: $apiKeyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    if let success = validationSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(success ? .green : .red)
                            Text(success ? "Cheia este validă și funcțională!" : "Cheia nu a putut fi verificată. Verifică caracterele.")
                                .font(.caption)
                                .foregroundStyle(success ? .green : .red)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            Task { await validateAndSaveKey() }
                        } label: {
                            HStack(spacing: 6) {
                                if isValidatingKey {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text("Salvează & Verifică")
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
                        
                        Spacer()
                        
                        if isKeySaved {
                            Button("Șterge", role: .destructive) {
                                deleteKey()
                            }
                            .font(.subheadline)
                        }
                    }
                    
                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        HStack {
                            Text("Obține o cheie gratuită pe Google AI Studio")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(.purple)
                    }
                } header: {
                    Text("Configurare Cheie Gemini API (BYOK)")
                } footer: {
                    Text("Aplicația este 100% gratuită. Nu plătești nimic dezvoltatorului. Cheia ta este stocată exclusiv pe telefonul tău în iOS Keychain și apelurile merg direct către Google fără servere intermediare.")
                }
                
                // Section: Comparativ Funcționalități
                Section("Ce oferă fiecare mod") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .font(.caption.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scanare Standard (Gratuită, Fără Cheie)")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                Text("Decupare unghiuri cameră, OCR local, detectare date și sume de bază.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                                .font(.caption.weight(.bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scanare Pro AI (Cu Cheia Ta Gemini)")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                Text("Identificare automată furnizor, scadență, sumă exactă, rezumat servicii și alocare automată pe activ.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Section: Sincronizare & Securitate
                Section("Confidențialitate & Stocare") {
                    HStack {
                        Label("Sincronizare iCloud", systemImage: "icloud.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("CloudKit Privat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Stocare Date", systemImage: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("100% Pe Dispozitiv")
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
                        Text("Model de Distribuție")
                        Spacer()
                        Text("Free & Open Source")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Versiune")
                        Spacer()
                        Text("1.0.0 (Alpha)")
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
                Text("Cheia Gemini API este activă și securizată în Keychain.")
            }
            .alert("Cheie Eliminată", isPresented: $showingDeleteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Aplicația a revenit la modul de scanare exclusiv local (Apple Vision).")
            }
        }
    }
    
    private func checkKeyStatus() {
        if let key = KeychainManager.getGeminiAPIKey(), !key.isEmpty {
            isKeySaved = true
            apiKeyInput = "" // Keep raw secret out of view state and text field
        } else {
            isKeySaved = false
            apiKeyInput = ""
        }
    }
    
    private func validateAndSaveKey() async {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isValidatingKey = true
        validationSuccess = nil
        
        let isValid = await GeminiService.shared.validateAPIKey(trimmed)
        isValidatingKey = false
        validationSuccess = isValid
        
        if isValid {
            if KeychainManager.saveGeminiAPIKey(trimmed) {
                isKeySaved = true
                apiKeyInput = "" // Clear plaintext from view state upon successful save
                showingSaveAlert = true
            }
        }
    }
    
    private func deleteKey() {
        if KeychainManager.deleteGeminiAPIKey() {
            isKeySaved = false
            apiKeyInput = ""
            validationSuccess = nil
            showingDeleteAlert = true
        }
    }
}
