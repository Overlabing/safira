// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import Testing

/// #121: a page that loops dialogs is offered a way out from its second dialog, and stays quiet once stopped until it
/// loads another document.
@Suite struct PageDialogGateTests {
    @Test func theFirstDialogOffersNothingAndTheSecondOffersToStop() {
        var gate = PageDialogGate()

        let first = gate.dialog(.alert, message: "Saved", site: "mail.example")
        gate.answered(PageDialogResponse(isAccepted: true))
        let second = gate.dialog(.confirm, message: "Delete?", site: "mail.example")

        #expect(first == PageDialog(kind: .alert, message: "Saved", site: "mail.example", offersToStopDialogs: false))
        #expect(second == PageDialog(kind: .confirm, message: "Delete?", site: "mail.example", offersToStopDialogs: true))
    }

    @Test func theFirstDialogCannotStopTheNextOnes() {
        var gate = PageDialogGate()
        _ = gate.dialog(.alert, message: "1", site: nil)
        gate.answered(PageDialogResponse(isAccepted: true, stopsDialogs: true))

        #expect(gate.isStopped == false)
        #expect(gate.dialog(.alert, message: "2", site: nil)?.offersToStopDialogs == true)
    }

    @Test func stoppedDialogsAreDeclinedUntilANewDocument() {
        var gate = PageDialogGate()
        _ = gate.dialog(.alert, message: "1", site: nil)
        gate.answered(PageDialogResponse(isAccepted: true))
        _ = gate.dialog(.alert, message: "2", site: nil)
        gate.answered(PageDialogResponse(isAccepted: true, stopsDialogs: true))

        #expect(gate.dialog(.alert, message: "3", site: nil) == nil)
        #expect(gate.isStopped)

        gate.newDocument()
        #expect(gate.dialog(.prompt(defaultText: "x"), message: "4", site: nil)
            == PageDialog(kind: .prompt(defaultText: "x"), message: "4", site: nil, offersToStopDialogs: false))
    }
}
