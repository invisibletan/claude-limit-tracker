import Foundation
import Testing
@testable import UsageCore

@Suite struct PaceSelectionTests {
    @Test func showsPerStateCheckbox() {
        let sel = PaceSelection(slow: false, steady: true, fast: true)
        #expect(!sel.shows(.slow))
        #expect(sel.shows(.steady))
        #expect(sel.shows(.fast))
    }

    @Test func allAndNonePresets() {
        for state in [Pace.State.slow, .steady, .fast] {
            #expect(PaceSelection.all.shows(state))
            #expect(!PaceSelection.none.shows(state))
        }
    }

    @Test func groupHiddenWhenCurrentStateUnchecked() {
        // Unticking a state hides the whole window group while at that pace.
        let sel = PaceSelection(slow: false, steady: true, fast: true)
        #expect(!sel.showsGroup(for: .slow))
        #expect(sel.showsGroup(for: .steady))
        #expect(sel.showsGroup(for: .fast))
    }

    @Test func groupVisibleWhilePaceUnknown() {
        // Too early in a window to judge pace — never hide data on a guess.
        #expect(PaceSelection.none.showsGroup(for: nil))
        #expect(PaceSelection.all.showsGroup(for: nil))
    }
}

@Suite struct MenuBarConfigTests {
    @Test func defaultsMatchShippedLook() {
        let config = MenuBarConfig()
        #expect(config.showMascot)
        #expect(config.sessionRing)
        #expect(config.sessionPercent)
        #expect(config.sessionGlyph)
        #expect(config.sessionPace == .all)
        #expect(!config.weeklyRing)      // new element ships off — preserves the existing look
        #expect(config.weeklyPercent)
        #expect(config.weeklyGlyph)
        #expect(config.weeklyPace == .all)
    }
}

@Suite struct MenuBarLayoutTests {
    private func config(
        sessionRing: Bool = true, sessionPercent: Bool = true,
        weeklyRing: Bool = false, weeklyPercent: Bool = true
    ) -> MenuBarConfig {
        var c = MenuBarConfig()
        c.sessionRing = sessionRing
        c.sessionPercent = sessionPercent
        c.weeklyRing = weeklyRing
        c.weeklyPercent = weeklyPercent
        return c
    }

    @Test func defaultsPassThroughUnchanged() {
        let out = MenuBarLayout.effective(config(), mascotVisible: true)
        #expect(out.sessionRing)
        #expect(out.sessionPercent)
    }

    @Test func allStructuralOffWithMascotIsMascotOnly() {
        let out = MenuBarLayout.effective(
            config(sessionRing: false, sessionPercent: false, weeklyRing: false, weeklyPercent: false),
            mascotVisible: true
        )
        #expect(!out.sessionRing)
        #expect(!out.sessionPercent)
    }

    @Test func allStructuralOffWithoutMascotForcesSessionRing() {
        let out = MenuBarLayout.effective(
            config(sessionRing: false, sessionPercent: false, weeklyRing: false, weeklyPercent: false),
            mascotVisible: false
        )
        #expect(out.sessionRing)
    }

    @Test func anyStructuralElementIsASufficientAnchor() {
        // A weekly percent (or any ring/percent) keeps the item clickable — no forcing.
        let out = MenuBarLayout.effective(
            config(sessionRing: false, sessionPercent: false, weeklyRing: false, weeklyPercent: true),
            mascotVisible: false
        )
        #expect(!out.sessionRing)
        #expect(out.weeklyPercent)
    }

    @Test func mascotForcedWhenNoAccounts() {
        #expect(MenuBarLayout.showsMascot(preference: false, hasEntries: false))
        #expect(!MenuBarLayout.showsMascot(preference: false, hasEntries: true))
        #expect(MenuBarLayout.showsMascot(preference: true, hasEntries: true))
        #expect(MenuBarLayout.showsMascot(preference: true, hasEntries: false))
    }
}

@Suite struct PaceLegacyMigrationTests {
    @Test func legacyModesMapToSelections() {
        let all = PaceDisplay.migrateLegacy(rawValue: "all")
        #expect(all.selection == .all)
        #expect(all.glyphs)

        let hideSlow = PaceDisplay.migrateLegacy(rawValue: "hideSlow")
        #expect(hideSlow.selection == PaceSelection(slow: false, steady: true, fast: true))
        #expect(hideSlow.glyphs)

        let fireOnly = PaceDisplay.migrateLegacy(rawValue: "fireOnly")
        #expect(fireOnly.selection == PaceSelection(slow: false, steady: false, fast: true))
        #expect(fireOnly.glyphs)

        // Ring-color mode was removed — its stored value degrades to the default look.
        let ringTint = PaceDisplay.migrateLegacy(rawValue: "ringTint")
        #expect(ringTint.selection == .all)
        #expect(ringTint.glyphs)

        // Legacy "off" meant no pace GLYPHS — under the two-set model that is
        // glyph-element off, with no group filtering.
        let off = PaceDisplay.migrateLegacy(rawValue: "off")
        #expect(off.selection == .all)
        #expect(!off.glyphs)
    }

    @Test func unknownOrMissingFallsBackToAll() {
        #expect(PaceDisplay.migrateLegacy(rawValue: nil).selection == .all)
        #expect(PaceDisplay.migrateLegacy(rawValue: "bogus").selection == .all)
        #expect(PaceDisplay.migrateLegacy(rawValue: nil).glyphs)
    }
}
