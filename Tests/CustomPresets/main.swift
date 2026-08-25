import Foundation

// Custom presets used to be activated by *copying* their prompt into a free-text
// field. Nothing recorded which preset was active, so the UI could not show it,
// and editing one had no effect on the copy already in use. Activation now
// stores a reference; these cover what that has to guarantee.

let state = AppState()
state.customPresets = []
state.activeCustomPresetId = nil
state.customPrompt = ""
state.aiPreset = .standard

let slack = state.addCustomPreset(name: "Slack reply", icon: "message.fill",
                                  prompt: "Rewrite as a short Slack message.", temp: 0.4)
let legal = state.addCustomPreset(name: "Legal", icon: "briefcase.fill",
                                  prompt: "Rewrite in formal legal register.", temp: 0.2)

T.section("activation points at the preset")
state.activateCustomPreset(id: slack.id)
T.equal("preset marked custom", "\(state.aiPreset)", "custom")
T.equal("the active one is recorded", "\(state.activeCustomPresetId == slack.id)", "true")
T.equal("its temperature is applied", state.temperature, 0.4)
T.equal("its prompt is what gets sent", state.effectiveCustomPrompt, "Rewrite as a short Slack message.")

T.section("switching between custom presets")
state.activateCustomPreset(id: legal.id)
T.equal("the new one is active", "\(state.activeCustomPresetId == legal.id)", "true")
T.equal("its prompt is sent", state.effectiveCustomPrompt, "Rewrite in formal legal register.")
T.equal("its temperature follows", state.temperature, 0.2)

T.section("editing the active preset takes effect at once")
// The whole point of referencing instead of copying.
state.updateCustomPreset(id: legal.id, name: "Legal v2", icon: "briefcase.fill",
                         prompt: "Rewrite in plain legal English.", temp: 0.6)
T.equal("the edited prompt is used immediately",
        state.effectiveCustomPrompt, "Rewrite in plain legal English.")
T.equal("the edited temperature is applied", state.temperature, 0.6)
T.equal("the rename is stored", state.customPresets.first { $0.id == legal.id }?.name ?? "", "Legal v2")

T.section("editing an inactive preset does not disturb the active one")
state.updateCustomPreset(id: slack.id, name: "Slack", icon: "message.fill",
                         prompt: "Something else entirely.", temp: 0.9)
T.equal("still using the active preset",
        state.effectiveCustomPrompt, "Rewrite in plain legal English.")
T.equal("temperature untouched", state.temperature, 0.6)

T.section("the notch shows the preset's own name")
T.equal("custom name, not the generic label", state.presetDisplayName(L10n(.italian)), "Legal v2")
state.aiPreset = .standard
state.activeCustomPresetId = nil
T.equal("built-in falls back to the localised label",
        state.presetDisplayName(L10n(.italian)), "Standard (Correzione)")

T.section("deleting the active preset leaves nothing dangling")
state.activateCustomPreset(id: legal.id)
state.removeCustomPreset(id: legal.id)
T.equal("reference cleared", "\(state.activeCustomPresetId == nil)", "true")
// Otherwise .custom would stay selected with an empty instruction behind it.
T.equal("falls back to a working preset", "\(state.aiPreset)", "standard")
T.equal("no prompt left over", state.effectiveCustomPrompt, "")

T.section("deleting an inactive preset leaves the active one alone")
let a = state.addCustomPreset(name: "A", icon: "gear", prompt: "AAA", temp: 0.1)
let b = state.addCustomPreset(name: "B", icon: "gear", prompt: "BBB", temp: 0.1)
state.activateCustomPreset(id: a.id)
state.removeCustomPreset(id: b.id)
T.equal("still active", "\(state.activeCustomPresetId == a.id)", "true")
T.equal("still sending its prompt", state.effectiveCustomPrompt, "AAA")

T.section("the legacy free-text prompt still works")
// Saved before named presets existed: it must not be silently dropped.
state.activeCustomPresetId = nil
state.customPrompt = "Vecchia istruzione libera"
T.equal("falls back to the legacy prompt", state.effectiveCustomPrompt, "Vecchia istruzione libera")
// And a preset takes precedence over it once chosen.
state.activateCustomPreset(id: a.id)
T.equal("the preset wins over the legacy prompt", state.effectiveCustomPrompt, "AAA")

T.section("unknown ids are ignored")
state.activateCustomPreset(id: UUID())
T.equal("activation of a missing preset is a no-op", "\(state.activeCustomPresetId == a.id)", "true")
state.updateCustomPreset(id: UUID(), name: "x", icon: "gear", prompt: "x", temp: 0.5)
T.equal("editing a missing preset is a no-op", state.effectiveCustomPrompt, "AAA")

T.section("deactivating returns to standard")

let z = state.addCustomPreset(name: "Z", icon: "gear", prompt: "ZZZ", temp: 0.7)
state.activateCustomPreset(id: z.id)
T.equal("active before", "\(state.aiPreset)", "custom")

state.deactivateCustomPreset()
T.equal("back to standard", "\(state.aiPreset)", "standard")
T.equal("reference cleared", "\(state.activeCustomPresetId == nil)", "true")
// The preset itself must survive: deactivating is not deleting.
T.equal("the preset is still saved", "\(state.customPresets.contains { $0.id == z.id })", "true")
// Temperature is deliberately left alone rather than silently moved back.
T.equal("temperature untouched", state.temperature, 0.7)

T.section("deactivating twice is harmless")
state.deactivateCustomPreset()
T.equal("still standard", "\(state.aiPreset)", "standard")

T.section("reactivating after deactivating")
state.activateCustomPreset(id: z.id)
T.equal("active again", "\(state.activeCustomPresetId == z.id)", "true")
T.equal("its prompt is sent again", state.effectiveCustomPrompt, "ZZZ")

T.finish("CustomPresets")
