import SwiftUI
import AppKit

struct MagicSheet: View {
    let project: Project
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var state: State = .scanning
    @State private var picked: Set<UUID> = []

    private enum State {
        case scanning
        case done(Magic.Answer)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.tint(project.tint))
                Text("What does \(project.name) run?")
                    .font(.system(size: 15, weight: .semibold))
            }

            switch state {
            case .scanning:
                scanning
            case .done(let answer):
                results(answer)
            case .failed(let message):
                failure(message)
            }

            HStack {
                Button("Copy prompt") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Magic.prompt(for: project), forType: .string)
                }
                .controlSize(.small)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if case .done = state {
                    Button("Add \(picked.count)") { add() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(picked.isEmpty)
                }
            }
        }
        .padding(18)
        .frame(width: 520)
        .task { await scan() }
    }

    private var scanning: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude is reading the project…")
                    .font(.system(size: 12))
                Text("Read, Glob and Grep only — it cannot change anything, and nothing is added until you say so.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }

    private func results(_ answer: Magic.Answer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if answer.services.isEmpty {
                Text("Claude found nothing that keeps running in this folder.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(answer.services) { suggestion in
                        Toggle(isOn: Binding(
                            get: { picked.contains(suggestion.id) },
                            set: { on in
                                if on { picked.insert(suggestion.id) } else { picked.remove(suggestion.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(suggestion.name)
                                        .font(.system(size: 12, weight: .semibold))
                                    if let dir = suggestion.dir, !dir.isEmpty {
                                        Text(dir)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Theme.separator.opacity(0.4)))
                                    }
                                    if let health = suggestion.health, !health.isEmpty {
                                        Text(health)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.secondary)
                                    }
                                }
                                Text(suggestion.command)
                                    .font(.system(size: 11, design: .monospaced))
                                if let why = suggestion.why, !why.isEmpty {
                                    Text(why)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            if let notes = answer.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Before these will start")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    ForEach(notes, id: \.self) { note in
                        Text("· \(note)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(ServiceStatus.failed(nil).color)
                .fixedSize(horizontal: false, vertical: true)
            Text("Copy the prompt and run it in a Claude session yourself — the answer is JSON you can turn into services by hand.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scan() async {
        let target = project
        let outcome: Result<Magic.Answer, Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try Magic.scan(target)) } catch { return .failure(error) }
        }.value

        switch outcome {
        case .success(let answer):
            picked = Set(answer.services.map(\.id))
            state = .done(answer)
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    private func add() {
        guard case .done(let answer) = state else { return }
        var copy = project
        copy.services.append(contentsOf: answer.services.filter { picked.contains($0.id) }.map(\.service))
        store.update(copy)
        dismiss()
    }
}
