import Foundation

// The hold-to-talk / lock-to-listen state machine: the most intricate logic in
// the app, and the part that produced the most bugs while it was untestable.
//
// Timestamps are supplied rather than read from the clock, so every timing
// branch — double-press, accidental tap, the confirmation delay — is exercised
// deterministically instead of by sleeping.

typealias M = DictationStateMachine

let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

/// Compares a list of actions, which reads better than comparing descriptions.
func expect(_ label: String, _ got: [M.Action], _ want: [M.Action]) {
    T.equal(label, "\(got)", "\(want)")
}

let recording = M.Context(isRecording: true)
let idle = M.Context(isRecording: false)

// ---------------------------------------------------------------------------
T.section("hold-to-talk: the ordinary path")

var m = M()
expect("press starts recording",
       m.handle(.keyDown(at: at(0)), context: idle),
       [.beginRecording])
expect("release arms the confirmation",
       m.handle(.keyUp(at: at(1.5)), context: recording),
       [.scheduleKeyUpConfirm(keyUpAt: at(1.5))])
expect("a 1.5s hold is a real utterance",
       m.handle(.keyUpConfirmFired(keyUpAt: at(1.5)), context: recording),
       [.stopForProcessing])
expect("the transcript is pasted and we go idle",
       m.handle(.finalTranscript("ciao"), context: idle),
       [.cancelKeyUpConfirm, .processTranscriptHoldToTalk("ciao")])

// ---------------------------------------------------------------------------
T.section("accidental tap")

m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
_ = m.handle(.keyUp(at: at(0.2)), context: recording)
expect("a 0.2s brush with nothing said is discarded",
       m.handle(.keyUpConfirmFired(keyUpAt: at(0.2)), context: recording),
       [.cancelAsAccidentalTap])

// The same brief press is NOT accidental if words were already recognised.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
expect("a brief press with speech is still processed",
       m.handle(.keyUpConfirmFired(keyUpAt: at(0.2)),
                context: M.Context(isRecording: true, hasPartialTranscript: true)),
       [.stopForProcessing])

// Boundary: exactly at the threshold counts as a real hold.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
expect("exactly at the threshold is a hold, not a tap",
       m.handle(.keyUpConfirmFired(keyUpAt: at(M.accidentalTapThreshold)), context: recording),
       [.stopForProcessing])

// ---------------------------------------------------------------------------
T.section("lock-to-listen: entering")

m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
_ = m.handle(.keyUp(at: at(0.1)), context: recording)
expect("a second quick press locks and disarms the pending stop",
       m.handle(.keyDown(at: at(0.2)), context: recording),
       [.cancelKeyUpConfirm, .enterLock])
T.equal("machine reports locked", "\(m.isLocked)", "true")

// A slow second press is a new hold-to-talk, not a lock.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
expect("a slow second press does not lock",
       m.handle(.keyDown(at: at(1.0)), context: idle),
       [.beginRecording])
T.equal("still unlocked", "\(m.isLocked)", "false")

// Boundary: exactly at the window is NOT a double press.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
_ = m.handle(.keyDown(at: at(M.doublePressWindow)), context: idle)
T.equal("exactly at the window does not lock", "\(m.isLocked)", "false")

// ---------------------------------------------------------------------------
T.section("lock-to-listen: while locked")

func locked() -> M {
    var m = M()
    _ = m.handle(.keyDown(at: at(0)), context: idle)
    _ = m.handle(.keyDown(at: at(0.2)), context: recording)
    return m
}

m = locked()
expect("key release is ignored", m.handle(.keyUp(at: at(1)), context: recording), [])
expect("a stale confirmation cannot stop it",
       m.handle(.keyUpConfirmFired(keyUpAt: at(0.1)), context: recording), [])
expect("silence is ignored: the recogniser restarts itself",
       m.handle(.silence, context: recording), [])
expect("a chunk is pasted and listening resumes",
       m.handle(.finalTranscript("primo pezzo"), context: recording),
       [.processTranscriptLocked("primo pezzo")])
T.equal("still locked after a chunk", "\(m.isLocked)", "true")

// ---------------------------------------------------------------------------
T.section("lock-to-listen: leaving")

m = locked()
expect("pressing the hotkey again exits", m.handle(.keyDown(at: at(5)), context: recording), [.exitLock])
T.equal("unlocked after hotkey", "\(m.isLocked)", "false")

m = locked()
expect("a left click exits", m.handle(.leftMouseClick, context: recording), [.exitLock])
T.equal("unlocked after click", "\(m.isLocked)", "false")

// A click when not locked must not disturb an ordinary dictation.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
expect("a click during hold-to-talk does nothing",
       m.handle(.leftMouseClick, context: recording), [])

// ---------------------------------------------------------------------------
T.section("permissions")

m = M()
expect("without permissions we onboard instead of recording",
       m.handle(.keyDown(at: at(0)), context: M.Context(hasPermissions: false)),
       [.showDashboard])
T.equal("no press was registered", "\(m.lastKeyDownTime == nil)", "true")

// Regression guard: a denied press must not count towards a double press, or
// granting permission mid-way could drop the user straight into lock mode.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: M.Context(hasPermissions: false))
expect("the next allowed press is a normal start",
       m.handle(.keyDown(at: at(0.1)), context: idle),
       [.beginRecording])
T.equal("did not lock", "\(m.isLocked)", "false")

// ---------------------------------------------------------------------------
T.section("races and stale events")

// Silence beat the confirmation delay: the delay must not finalise again.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
_ = m.handle(.keyUp(at: at(1)), context: recording)
_ = m.handle(.silence, context: recording)
expect("a confirmation after silence is a no-op",
       m.handle(.keyUpConfirmFired(keyUpAt: at(1)), context: idle),
       [])

// A press arriving while a session is somehow still live discards it first.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
expect("a stale session is discarded before restarting",
       m.handle(.keyDown(at: at(10)), context: recording),
       [.discardStaleSession, .beginRecording])

// Silence in hold-to-talk clears the pending confirmation as well.
m = M()
_ = m.handle(.keyDown(at: at(0)), context: idle)
expect("silence disarms and resets",
       m.handle(.silence, context: recording),
       [.cancelKeyUpConfirm, .returnToIdle])

// ---------------------------------------------------------------------------
T.section("timing constants stay coherent")

// The confirmation must fire no later than the double-press window closes,
// otherwise a genuine double press could be preceded by a stop.
T.equal("confirm delay < double-press window",
        "\(M.singlePressConfirmDelay < M.doublePressWindow)", "true")
T.equal("accidental threshold < confirm delay",
        "\(M.accidentalTapThreshold < M.singlePressConfirmDelay)", "true")

T.finish("DictationStateMachine")
