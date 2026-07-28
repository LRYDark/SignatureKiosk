import Foundation

struct AutocompleteEmail: Codable {
    let address: String
    let timestamp: Date
}

class EmailAutocompleteManager: ObservableObject {
    @Published var suggestions: [String] = []
    
    private let storeKey = "SavedSignerEmails"
    private let maxAge: TimeInterval = 120 * 24 * 60 * 60 // 2 semaines en secondes

    func updateSuggestions(for query: String) {
        guard query.count >= 4 else {
            suggestions = []
            return
        }
        
        let validEmails = getValidEmails()
        suggestions = validEmails
            .map { $0.address }
            .filter { $0.lowercased().contains(query.lowercased()) }
    }

    func save(_ email: String) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty else { return }
        
        var emails = getValidEmails()
        
        // Retire l'email s'il existe déjà pour rafraîchir son timestamp
        emails.removeAll { $0.address.lowercased() == cleanEmail.lowercased() }
        emails.append(AutocompleteEmail(address: cleanEmail, timestamp: Date()))
        
        if let data = try? JSONEncoder().encode(emails) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func getValidEmails() -> [AutocompleteEmail] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let emails = try? JSONDecoder().decode([AutocompleteEmail].self, from: data) else {
            return []
        }
        
        // Purge automatique des emails de plus de 2 semaines
        let validEmails = emails.filter { Date().timeIntervalSince($0.timestamp) <= maxAge }
        
        // Sauvegarder la liste purgée pour nettoyer UserDefaults si des emails ont expiré
        if validEmails.count != emails.count, let updatedData = try? JSONEncoder().encode(validEmails) {
            UserDefaults.standard.set(updatedData, forKey: storeKey)
        }
        
        return validEmails
    }
}
