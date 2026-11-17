import Observation

/// 持续观察 @Observable 属性：`track` 内读取的属性变化时执行 `perform`（并自动重新订阅）。
@MainActor
public func observeContinuously(track: @escaping @MainActor () -> Void, perform: @escaping @MainActor () -> Void) {
    withObservationTracking {
        track()
    } onChange: {
        Task { @MainActor in
            perform()
            observeContinuously(track: track, perform: perform)
        }
    }
}
