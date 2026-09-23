import AppKit

/// Owns the 15fps mascot/ring animation loop and its rendered frame.
///
/// Deliberately its OWN `ObservableObject`, held by `UsageStore` as a plain
/// `let` (never `@Published`) and observed only by `MenuBarLabel` (see
/// `ClaudeUsageTrackerApp.swift`). Previously the per-frame image lived on
/// `UsageStore` itself as `@Published var iconImage`, which is `@StateObject`-owned
/// by the App struct — every frame publish invalidated the App's `body`
/// (MenuBarExtra + Settings scenes together) and leaked one Observation
/// tracking registration per frame that was never torn down. Isolating
/// per-frame state here means only `MenuBarLabel`'s own
/// view body — an ordinary View, not a Scene — re-renders at 15fps, and
/// ordinary View re-renders tear down their tracking registration correctly.
@MainActor
final class MenuBarIconModel: ObservableObject {
    @Published var image: NSImage?

    private var animationTask: Task<Void, Never>?
    private var walkPhase = 0.0

    /// Starts the animation loop. `activity` (0...1) sets walk speed each
    /// frame; `render` composites the frame for the current phase. Both are
    /// plain closures (not bindings to `@Published` state) so calling them
    /// every frame never touches the store's own publisher.
    func start(activity: @escaping @MainActor () -> Double, render: @escaping @MainActor (Double) -> NSImage) {
        guard animationTask == nil else { return }
        animationTask = Task { [weak self] in
            let frame = 1.0 / 15.0
            while !Task.isCancelled {
                guard let self else { return }
                let cyclesPerSecond = 0.6 + activity() * 2.6   // gentle amble -> brisk march
                self.walkPhase = (self.walkPhase + cyclesPerSecond * frame).truncatingRemainder(dividingBy: 1)
                self.image = render(self.walkPhase)
                try? await Task.sleep(for: .seconds(frame))
            }
        }
    }

    func stop() {
        animationTask?.cancel()
        animationTask = nil
    }

    deinit {
        animationTask?.cancel()
    }
}
