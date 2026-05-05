import SwiftUI
import CallKit

struct ContentView: View {
    @State private var entries: [LabeledNumber] = []
    @State private var newNumberInput: String = ""
    @State private var newLabel: String = "Spam"
    @State private var statusMessage: String?
    @State private var extensionEnabled: Bool?

    private let extensionId = "com.thomashart.SpamShield.CallDirectory"

    var body: some View {
        NavigationStack {
            List {
                Section("Add number") {
                    TextField("Phone number (e.g. +1 801 793 5456)", text: $newNumberInput)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                    TextField("Label", text: $newLabel)
                    Button("Block this number", action: addBlocked)
                        .disabled(newNumberInput.isEmpty)
                }

                Section("Blocked (\(entries.count))") {
                    if entries.isEmpty {
                        Text("Nothing yet. Add a number above.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries, id: \.number) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatE164(entry.number))
                                    .font(.body.monospaced())
                                Text(entry.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: removeBlocked)
                    }
                }

                Section("Extension") {
                    Button("Reload extension", action: reloadExtension)
                    if let extensionEnabled {
                        Text(extensionEnabled
                             ? "Enabled in iOS Settings ✓"
                             : "Not enabled — Settings → Phone → Call Blocking & Identification → toggle SpamShield on.")
                            .font(.footnote)
                            .foregroundStyle(extensionEnabled ? Color.secondary : Color.red)
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("SpamShield")
            .toolbar {
                EditButton()
            }
            .onAppear {
                load()
                checkExtensionStatus()
            }
        }
    }

    private func load() {
        let blocked = Set(BlocklistStore.shared.blockedNumbers())
        let labeledByNumber = Dictionary(
            BlocklistStore.shared.labeledNumbers().map { ($0.number, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )
        entries = blocked
            .sorted()
            .map { LabeledNumber(number: $0, label: labeledByNumber[$0] ?? "Spam") }
    }

    private func addBlocked() {
        guard let parsed = parseE164(newNumberInput) else {
            statusMessage = "Couldn't parse number. Use full international format (+1 then 10 digits for US)."
            return
        }
        var blocked = BlocklistStore.shared.blockedNumbers()
        guard !blocked.contains(parsed) else {
            statusMessage = "\(formatE164(parsed)) is already blocked."
            return
        }
        blocked.append(parsed)
        blocked.sort()
        BlocklistStore.shared.setBlockedNumbers(blocked)

        var labeled = BlocklistStore.shared.labeledNumbers()
        labeled.removeAll { $0.number == parsed }
        labeled.append(LabeledNumber(number: parsed, label: newLabel.isEmpty ? "Spam" : newLabel))
        BlocklistStore.shared.setLabeledNumbers(labeled)

        newNumberInput = ""
        load()
        reloadExtension()
    }

    private func removeBlocked(at offsets: IndexSet) {
        let removing = offsets.map { entries[$0].number }
        var blocked = BlocklistStore.shared.blockedNumbers()
        blocked.removeAll { removing.contains($0) }
        BlocklistStore.shared.setBlockedNumbers(blocked)

        var labeled = BlocklistStore.shared.labeledNumbers()
        labeled.removeAll { removing.contains($0.number) }
        BlocklistStore.shared.setLabeledNumbers(labeled)

        load()
        reloadExtension()
    }

    private func reloadExtension() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: extensionId) { error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    statusMessage = "Reload failed: \(error.localizedDescription)"
                } else {
                    statusMessage = "Reloaded \(entries.count) blocked numbers into iOS."
                }
            }
        }
    }

    private func checkExtensionStatus() {
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: extensionId) { status, _ in
            DispatchQueue.main.async {
                extensionEnabled = (status == .enabled)
            }
        }
    }

    private func parseE164(_ raw: String) -> Int64? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 10 else { return nil }
        return Int64(digits)
    }

    private func formatE164(_ n: Int64) -> String {
        let s = String(n)
        if s.count == 11, s.hasPrefix("1") {
            let area = s.index(s.startIndex, offsetBy: 1)..<s.index(s.startIndex, offsetBy: 4)
            let mid = s.index(s.startIndex, offsetBy: 4)..<s.index(s.startIndex, offsetBy: 7)
            let last = s.index(s.startIndex, offsetBy: 7)..<s.endIndex
            return "+1 (\(s[area])) \(s[mid])-\(s[last])"
        }
        return "+\(s)"
    }
}

#Preview {
    ContentView()
}
