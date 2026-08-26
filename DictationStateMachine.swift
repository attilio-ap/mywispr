import Foundation

/// The hold-to-talk / lock-to-listen decision logic, with no AppKit in sight.
///
/// This lived inline in `AppDelegate`, tangled up with `Timer`, `Date()` and the
/// managers it drives, which made it the least testable part of the app — and,
/// not coincidentally, the part where most bugs turned up. Pulled out here it is
/// a pure function of (event, context) → actions, so every branch can be
/// exercised deterministically: timestamps are passed in rather than read from
/// the clock, and the caller performs the effects.
///
/// Two interaction modes share one hotkey:
///
/// **A — hold-to-talk.** Press and hold to record, release to stop and process.
///
/// **B — lock-to-listen.** Two quick presses keep the microphone open so the
/// user can speak hands-free for as long as they like. Everything said is
/// accumulated and pasted once, on exit — pauses do not end the dictation.
/// Exit by pressing the hotkey again or left-clicking anywhere.
struct DictationStateMachine {

    // MARK: - Timing

    /// Maximum gap between two presses to count as a double-press.
    static let doublePressWindow: TimeInterval = 0.35

    /// How long to wait after a release before committing to "this was a single
    /// press". Slightly shorter than `doublePressWindow` so the two cannot race.
    static let singlePressConfirmDelay: TimeInterval = 0.32

    /// A press shorter than this with nothing transcribed is treated as accidental.
    static let accidentalTapThreshold: TimeInterval = 0.25

    // MARK: - Input

    /// Something that happened, from the keyboard, the mouse or the recogniser.
    enum Event: Equatable {
        case keyDown(at: Date)
        case keyUp(at: Date)
        /// The delay armed by `.scheduleKeyUpConfirm` elapsed.
        case keyUpConfirmFired(keyUpAt: Date)
        case silence
        case finalTranscript(String)
        case leftMouseClick
    }

    /// The parts of the world the machine must consult but does not own.
    struct Context: Equatable {
        var hasPermissions: Bool
        var isRecording: Bool
        var hasPartialTranscript: Bool

        init(hasPermissions: Bool = true, isRecording: Bool = false, hasPartialTranscript: Bool = false) {
            self.hasPermissions = hasPermissions
            self.isRecording = isRecording
            self.hasPartialTranscript = hasPartialTranscript
        }
    }

    // MARK: - Output

    /// What the caller should do. Deliberately coarse: each case corresponds to
    /// one meaningful step, not to an individual property assignment.
    enum Action: Equatable {
        /// Permissions are missing — send the user to onboarding instead of recording.
        case showDashboard
        /// Clear transient state, mark recording, show the recording overlay, start the mic.
        case beginRecording
        /// A previous session was somehow still live; throw it away before starting.
        case discardStaleSession
        /// Enter hands-free mode. The session already running is kept.
        case enterLock
        /// Leave hands-free mode and stop the microphone.
        case exitLock
        /// Arm the single-press confirmation delay.
        case scheduleKeyUpConfirm(keyUpAt: Date)
        /// Disarm it, if armed.
        case cancelKeyUpConfirm
        /// The key was brushed and nothing was said: drop the audio silently.
        case cancelAsAccidentalTap
        /// A real utterance ended: stop the mic and wait for the transcript.
        case stopForProcessing
        /// Nothing was recognised: clear the transient state and collapse the overlay.
        case returnToIdle
        /// A transcript is ready: paste it, then go idle.
        case processTranscript(String)
    }

    // MARK: - State

    private(set) var isLocked = false
    private(set) var lastKeyDownTime: Date?

    init() {}

    // MARK: - Transition

    /// Advances the machine and returns the effects to perform, in order.
    mutating func handle(_ event: Event, context: Context) -> [Action] {
        switch event {
        case .keyDown(let at):
            return handleKeyDown(at: at, context: context)

        case .keyUp(let at):
            // While locked the release means nothing: the mic stays open.
            guard !isLocked else { return [] }
            return [.scheduleKeyUpConfirm(keyUpAt: at)]

        case .keyUpConfirmFired(let keyUpAt):
            return handleKeyUpConfirm(keyUpAt: keyUpAt, context: context)

        case .silence:
            // While locked, SpeechManager restarts the session by itself.
            guard !isLocked else { return [] }
            return [.cancelKeyUpConfirm, .returnToIdle]

        case .finalTranscript(let text):
            // Note there is no "locked" variant. Both ways out of hands-free mode
            // clear `isLocked` before stopping the microphone, and nothing else
            // delivers a transcript while it is set — task rotation restarts the
            // recogniser rather than finalising it. So by the time a transcript
            // arrives the session is always already unlocked.
            return [.cancelKeyUpConfirm, .processTranscript(text)]

        case .leftMouseClick:
            // A click anywhere is the escape hatch out of hands-free mode.
            guard isLocked else { return [] }
            isLocked = false
            return [.exitLock]
        }
    }

    private mutating func handleKeyDown(at now: Date, context: Context) -> [Action] {
        guard context.hasPermissions else { return [.showDashboard] }

        // Already locked? This press leaves hands-free mode.
        if isLocked {
            isLocked = false
            return [.exitLock]
        }

        let timeSinceLast = lastKeyDownTime.map { now.timeIntervalSince($0) } ?? .infinity
        lastKeyDownTime = now

        if timeSinceLast < Self.doublePressWindow {
            // Double press. Disarm the first press's confirmation so the running
            // session is not stopped out from under the user.
            isLocked = true
            return [.cancelKeyUpConfirm, .enterLock]
        }

        // First press: classic hold-to-talk.
        var actions: [Action] = []
        if context.isRecording {
            actions.append(.discardStaleSession)
        }
        actions.append(.beginRecording)
        return actions
    }

    private func handleKeyUpConfirm(keyUpAt: Date, context: Context) -> [Action] {
        // A double press may have arrived while the delay was running.
        guard !isLocked else { return [] }

        // Already finalised elsewhere (e.g. silence fired): avoid a second finalise.
        guard context.isRecording else { return [] }

        let holdDuration = lastKeyDownTime.map { keyUpAt.timeIntervalSince($0) } ?? 1.0

        if holdDuration < Self.accidentalTapThreshold && !context.hasPartialTranscript {
            return [.cancelAsAccidentalTap]
        }
        return [.stopForProcessing]
    }
}
