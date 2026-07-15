import XCTest

@MainActor
final class CueMeMemoryE2ETests: XCTestCase {
    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CUEME_UI_TESTING"] = "1"
        for (key, value) in environment { app.launchEnvironment[key] = value }
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        return app
    }

    func testSearchOpensEvidenceBackedMemory() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let search = app.textFields["memory.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        // No lexical token exists in the fixture: this result must come from sqlite-vec.
        search.typeText("carro sustentável")

        let session = app.buttons["session.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()

        let decision = app.textFields["review.item.30000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        XCTAssertEqual(decision.value as? String, "Adotar veículos elétricos no próximo trimestre")
        let evidence = app.buttons["evidence.30000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(evidence.exists)
        XCTAssertEqual(evidence.value as? String, "00:42")
        evidence.click()
        XCTAssertTrue(app.buttons["memory.ask"].exists)
    }

    func testGlobalMemoryAnswerIncludesGroundedSource() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let search = app.textFields["memory.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("carro sustentável")
        let ask = app.buttons["memory.ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.click()
        let answer = app.staticTexts["memory.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let rawAnswer = [answer.value as? String, answer.label]
            .compactMap { $0 }
            .joined(separator: " ")
        XCTAssertTrue(rawAnswer.contains("[S1]"))
        XCTAssertTrue(rawAnswer.contains("Estratégia de frota elétrica"))
    }

    func testEditingMemoryReindexesSearchFromTheUI() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let session = app.buttons["session.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        let decision = app.textFields["review.item.30000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        decision.click()
        decision.typeKey("a", modifierFlags: .command)
        decision.typeText("Contrato solar aprovado")
        decision.typeKey(.return, modifierFlags: [])

        let search = app.textFields["memory.search"]
        search.click()
        search.typeText("Contrato solar")
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        XCTAssertEqual(decision.value as? String, "Contrato solar aprovado")
    }

    func testProjectPopoverShowsLongitudinalTimeline() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let session = app.buttons["session.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        let project = app.buttons["session.project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.click()

        XCTAssertTrue(app.staticTexts["TIMELINE"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["timeline.meeting-20000000-0000-0000-0000-000000000001"].exists)
        XCTAssertTrue(app.buttons["timeline.meeting-20000000-0000-0000-0000-000000000002"].exists)
    }

    func testLiveSessionRecordsTranscriptNoteAndCreatesDurableHistory() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let primary = app.buttons["session.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.click()
        XCTAssertEqual(primary.label, "Parar")

        let noteButton = app.buttons["live.note"]
        XCTAssertTrue(noteButton.waitForExistence(timeout: 5))
        noteButton.click()
        let note = app.textFields["live.note.input"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()
        note.typeText("Validar entrega final")
        app.buttons["live.note.submit"].click()

        primary.click()
        XCTAssertTrue(app.staticTexts["Biblioteca"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Áudio local"].exists)
        app.buttons["session.tab.transcript"].click()
        XCTAssertTrue(app.staticTexts["Como vamos reduzir o risco da entrega?"].waitForExistence(timeout: 3))
        app.buttons["session.tab.notes"].click()
        let savedNote = app.textFields["memory.note"]
        XCTAssertTrue(savedNote.waitForExistence(timeout: 3))
        XCTAssertEqual(savedNote.value as? String, "Validar entrega final")
    }

    func testSessionRecordsMicrophoneWhenSystemCapturePermissionIsUnavailable() {
        continueAfterFailure = false
        let app = launchApp(environment: ["CUEME_UI_TEST_SYSTEM_CAPTURE_DENIED": "1"])
        defer { app.terminate() }

        let primary = app.buttons["session.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.click()
        XCTAssertEqual(primary.label, "Parar")

        let microphone = app.buttons["capture.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 3))
        XCTAssertEqual(microphone.value as? String, "active")
        let system = app.buttons["capture.system"]
        XCTAssertTrue(system.exists)
        XCTAssertEqual(system.value as? String, "unavailable")
        let alert = app.buttons["capture.alert"]
        XCTAssertTrue(alert.exists)
        XCTAssertTrue(alert.label.contains("ÁUDIO EXTERNO OFF"))

        primary.click()
        XCTAssertTrue(app.staticTexts["Biblioteca"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Áudio local"].exists)
    }

    func testLiveCoachSuggestionSurvivesIntoSessionHistory() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }
        let primary = app.buttons["session.primary"]
        primary.click()
        let guide = app.staticTexts["coach.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        XCTAssertEqual(guide.value as? String, "Explique mitigação e prazo")
        XCTAssertTrue(app.staticTexts["Vamos dividir a entrega em marcos semanais."].exists)

        primary.click()
        XCTAssertTrue(app.staticTexts["Biblioteca"].waitForExistence(timeout: 5))
        app.buttons["session.tab.coach"].click()
        XCTAssertTrue(app.staticTexts["Explique mitigação e prazo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Vamos dividir a entrega em marcos semanais."].exists)
    }

    func testHomeSurfacesProfilesAndSecondBrainEntryPoints() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Sua memória, viva e organizada."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.new-note"].exists)
        XCTAssertTrue(app.buttons["home.journal"].exists)
        XCTAssertTrue(app.buttons["home.record"].exists)
        XCTAssertTrue(app.buttons["home.profile.interview"].exists)
        XCTAssertTrue(app.buttons["home.profile.sales"].exists)
    }

    func testCreatesRenamesLabelsAndEditsAMarkdownNote() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let newNote = app.buttons["home.new-note"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        newNote.click()

        let rename = app.buttons["note.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.click()
        let title = app.textFields["note.title.input"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Mapa da minha jornada")
        app.buttons["note.title.save"].click()

        let editor = app.textViews["note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.click()
        editor.typeText("# Aprendizados\n\nCoragem também é memória disponível na hora certa.")

        app.buttons["note.labels"].click()
        let label = app.textFields["note.label.input"]
        XCTAssertTrue(label.waitForExistence(timeout: 3))
        label.click()
        label.typeText("crescimento")
        app.buttons["note.label.add"].click()
        XCTAssertTrue(app.buttons["note.label.crescimento"].waitForExistence(timeout: 3))

        app.buttons["note.editor.preview"].click()
        XCTAssertTrue(app.staticTexts["Aprendizados"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coragem também é memória disponível na hora certa."].exists)
        XCTAssertTrue(app.staticTexts["Mapa da minha jornada"].exists)
    }

    func testSavedSessionReceivesASignificantGeneratedTitle() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let primary = app.buttons["session.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.click()
        primary.click()

        let title = app.buttons["note.rename"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Plano de mitigação da entrega"))
    }

    func testThemePreferenceCanBePinnedFromTheMainWindow() {
        continueAfterFailure = false
        let app = launchApp()
        defer { app.terminate() }

        let theme = app.menuButtons["theme.preference"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        theme.click()
        let light = app.menuItems["Claro"]
        XCTAssertTrue(light.waitForExistence(timeout: 3))
        light.click()
        XCTAssertEqual(theme.value as? String, "light")
    }
}
