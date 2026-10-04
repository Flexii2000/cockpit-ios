import SwiftUI

/// Die Fragen festlegen: schreiben, umbenennen, umsortieren, entfernen.
///
/// Uebernommen wird beim Schliessen - egal ob ueber „Fertig“ oder per Wischen;
/// ein Abbrechen gibt es nicht. Umbenennen behaelt den Verlauf, Entfernen
/// blendet ihn nur aus (siehe `EvaluationData`).
struct EvaluationQuestionsSheet: View {

    let onClose: ([EvaluationQuestion]) -> Void

    @State private var draft: [EvaluationQuestion]
    @FocusState private var focused: UUID?
    @Environment(\.dismiss) private var dismiss

    init(questions: [EvaluationQuestion], onClose: @escaping ([EvaluationQuestion]) -> Void) {
        self.onClose = onClose
        _draft = State(initialValue: questions)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($draft) { $question in
                    TextField("Frage", text: $question.text, axis: .vertical)
                        .focused($focused, equals: question.id)
                }
                .onDelete { draft.remove(atOffsets: $0) }
                .onMove { draft.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    add()
                } label: {
                    Label("Frage hinzufügen", systemImage: "plus")
                }
            }
            .navigationTitle("Fragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .onAppear {
            if draft.isEmpty { add() }
        }
        .onDisappear { onClose(draft) }
    }

    private func add() {
        let question = EvaluationQuestion(text: "")
        draft.append(question)
        focused = question.id
    }
}
