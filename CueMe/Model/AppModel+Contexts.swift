import Foundation

extension AppModel {
    var selectedMeetingContexts: [MeetingContext] {
        contexts.filter { selectedContextIDs.contains($0.id) }
    }

    func addMeetingContext() -> UUID {
        let context = MeetingContext(name: "Novo contexto")
        contexts.append(context)
        selectedContextIDs.insert(context.id)
        return context.id
    }

    func deleteMeetingContext(_ id: UUID) {
        guard !isSessionBusy else { return }
        contexts.removeAll { $0.id == id }
        selectedContextIDs.remove(id)
    }

    func toggleMeetingContext(_ id: UUID) {
        guard !isSessionBusy else { return }
        if selectedContextIDs.contains(id) {
            selectedContextIDs.remove(id)
        } else {
            selectedContextIDs.insert(id)
        }
    }

    func generateContextGlossary(force: Bool = true) async {
        let selected = selectedMeetingContexts.filter {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !selected.isEmpty else {
            generatedContextKeyterms = []
            glossaryGenerationState = .idle
            return
        }

        let signature = ContextGlossaryRequest.signature(
            contexts: selected,
            brief: brief,
            model: glossaryModel
        )
        if !force, let cache = MeetingContextStore.loadCache(), cache.signature == signature {
            generatedContextKeyterms = GlossaryTermPolicy.sanitized(cache.terms)
            glossaryGenerationState = .ready(generatedContextKeyterms.count)
            return
        }

        glossaryGenerationState = .generating
        do {
            let terms = try await ContextGlossaryGenerator.generate(
                contexts: selected,
                brief: brief,
                model: glossaryModel
            )
            generatedContextKeyterms = terms
            glossaryGenerationState = .ready(terms.count)
            MeetingContextStore.saveCache(.init(
                signature: signature,
                model: glossaryModel,
                terms: terms,
                generatedAt: Date()
            ))
        } catch {
            generatedContextKeyterms = []
            glossaryGenerationState = .failed(error.localizedDescription)
        }
    }

    func invalidateContextGlossary() {
        generatedContextKeyterms = []
        glossaryGenerationState = .idle
    }

    func sessionVocabulary(participantNames: [Speaker: String]? = nil) -> CustomVocabulary {
        vocabulary.merged(
            keyterms: brief.keyterms + generatedContextKeyterms,
            participantNames: participantNames ?? self.participantNames
        )
    }

    func prepareContextGlossaryForStart() async {
        var preparedBrief = brief
        let selected = selectedMeetingContexts
        preparedBrief.contexts = selected.isEmpty ? nil : selected
        brief = preparedBrief

        guard sttSource == .deepgram, !selected.isEmpty else { return }
        await generateContextGlossary(force: false)
    }
}
