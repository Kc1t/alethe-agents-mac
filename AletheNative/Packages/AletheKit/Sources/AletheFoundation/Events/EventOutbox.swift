import Foundation

@MainActor
public final class EventOutbox {
    public static let defaultLimit = 64

    public let limit: Int
    public private(set) var bus: EventBus?
    public private(set) var pending: [BusEvent] = []
    private var tail: Task<Void, Never>?

    public init(bus: EventBus? = nil, limit: Int = defaultLimit) {
        self.bus = bus
        self.limit = max(1, limit)
    }

    public func attach(_ bus: EventBus) {
        guard self.bus !== bus else { return }
        self.bus = bus
        let held = pending
        pending.removeAll()
        held.forEach(deliver)
    }

    public func publish(_ event: BusEvent) {
        guard bus != nil else {
            pending.append(event)
            if pending.count > limit { pending.removeFirst(pending.count - limit) }
            return
        }
        deliver(event)
    }

    public func publish(_ events: [BusEvent]) {
        events.forEach(publish)
    }

    public func drained() async {
        await tail?.value
    }

    private func deliver(_ event: BusEvent) {
        guard let bus else { return }
        let previous = tail
        tail = Task {
            await previous?.value
            await bus.publish(event)
        }
    }
}
