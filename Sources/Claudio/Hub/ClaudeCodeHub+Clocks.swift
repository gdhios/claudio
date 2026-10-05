import Foundation

/// The clocks the hub speaks to, one link each. Every command of the board
/// goes to every clock, each in its own device's line, side by side: a
/// clock out of reach holds no other back. The board hears what they made
/// of it once all have answered: a hold, or a dismissal, one clock took is
/// taken; one they all missed is missed. An indicator one of them missed
/// goes again with the next event, changed or not. A clock that joins while
/// the hub runs is shown the indicator at once; the alerts the others hold
/// can't follow it, the board keeping their names and not their texts.
extension ClaudeCodeHub {
    /// Where one clock stands, for Settings.
    enum ClockStatus: Equatable {
        /// Nothing heard from it yet.
        case pending
        /// It took its last call.
        case ready
        /// No answer at all: unplugged, another network, a wrong address.
        case unreachable(String)
        /// An answer, and a no, in the device's words.
        case rejected(String)
    }

    /// Pending for a clock the hub doesn't speak to.
    func clockStatus(of id: UUID) -> ClockStatus {
        links.first { $0.id == id }?.status ?? .pending
    }

    /// The last call queued for each device the hub speaks to, for a test
    /// to wait on.
    var sending: [Task<Void, Never>] {
        var seen = Set<URL>()
        return links.compactMap { seen.insert($0.address).inserted ? lines[$0.address] : nil }
    }

    // MARK: - The links

    /// Brings the links in line with `clocks`, the clocks with the flags: a
    /// clock gone or moved is let go, and one new or moved gets a link of
    /// its own, its button callback still to set. Every other goes on as it
    /// is, its queue and its callback with it.
    func relink(to clocks: [UlanziClock]) {
        let kept = links.filter { link in
            clocks.contains { $0.id == link.id && $0.address == link.address }
        }
        let dropped = links.filter { link in !kept.contains { $0 === link } }
        links = clocks.map { clock in kept.first { $0.id == clock.id } ?? makeLink(for: clock) }
        links.filter { link in !kept.contains { $0 === link } }.forEach(catchUp)
        for link in dropped {
            forget(link)
            if !links.contains(where: { $0.address == link.address }) { giveButtonBack(link) }
        }
    }

    /// A clock leaving while the door stays open is told to post its
    /// buttons nowhere, after whatever was still queued for it, which goes
    /// nowhere now: its middle button is its own again, not a press on the
    /// alerts of the clocks that stay. Only a clock Claudio told the door.
    /// A link that comes to the same device later goes after it, in the
    /// device's line: the door it tells is never cleared behind its back.
    private func giveButtonBack(_ link: ClaudeCodeClockLink) {
        guard link.doorSent else { return }
        let client = link.client
        chain(at: link.address) { try? await client.clearButtonCallback() }
    }

    /// A clock joining while the hub runs, or back from elsewhere, is
    /// shown the indicator the others were sent, at once: the next event
    /// may be long in coming while a session waits.
    private func catchUp(_ link: ClaudeCodeClockLink) {
        guard let indicator = board.catchUpIndicator else { return }
        send(indicator, to: [link])
    }

    private func makeLink(for clock: UlanziClock) -> ClaudeCodeClockLink {
        let id = clock.id
        let link = ClaudeCodeClockLink(id: id, address: clock.address, client: makeClient(clock.address))
        link.onStatusChange = { [weak self] in self?.onClockStatusChange?(id, $0) }
        onClockStatusChange?(id, link.status)
        return link
    }

    /// A clock let go: nothing more is heard from it, no command waits for
    /// it, and it is pending again.
    func forget(_ link: ClaudeCodeClockLink) {
        link.onStatusChange = nil
        report(deliveries.forget(ObjectIdentifier(link)))
        onClockStatusChange?(link.id, .pending)
    }

    /// Whether `link` is still one the current run speaks to.
    private func holds(_ link: ClaudeCodeClockLink, in run: Int) -> Bool {
        self.run == run && links.contains { $0 === link }
    }

    // MARK: - The button callback

    /// The Mac's address, the port and the token, for every clock to post
    /// its buttons to, the same for all: sent to a clock while still to
    /// set, and again once the Mac's address has changed, a press going
    /// nowhere otherwise. Without an address, nothing yet: it is looked for
    /// again at the next hook event.
    func setButtonCallbackIfNeeded() {
        guard let port, let token, let host = localAddress(),
              let url = URL(string: "http://\(host):\(port)/ulanzi/button/\(token)") else { return }
        for link in links where link.callbackHost != host {
            link.callbackHost = host
            attempt({ try await $0.setButtonCallback(url) }, on: link,
                    going: { [weak link] in link?.doorSent = true }) { [weak link] failure in
                if failure != nil { link?.callbackHost = nil }
            }
        }
    }

    // MARK: - Sending

    /// Sends `command` to every clock, each behind the calls queued for it
    /// before. What they made of it goes to the board once all have
    /// answered.
    func enqueue(_ command: UlanziCommand) {
        send(command, to: links)
    }

    /// Sends `command` to `recipients` only, the same way.
    private func send(_ command: UlanziCommand, to recipients: [ClaudeCodeClockLink]) {
        guard !recipients.isEmpty else { return }
        let number = deliveries.send(command, to: recipients.map(ObjectIdentifier.init))
        for link in recipients {
            let recipient = ObjectIdentifier(link)
            attempt({ try await $0.perform(command) }, on: link) { [weak self] failure in
                guard let self else { return }
                report(deliveries.answer(number, from: recipient, taken: failure == nil))
            }
        }
    }

    /// Runs `call` in the line of `link`'s device, and hands on what came
    /// of it: nil when the clock took it. The clock's status says it too.
    /// `going` is told when the call does go out.
    ///
    /// A clock out of reach costs one try per event, not 2.5 s per call:
    /// the calls queued behind the one that found nobody fail at once,
    /// without the network, and the board hears of each all the same.
    /// Nothing comes back from a run stopped since, or a link let go.
    private func attempt(_ call: @escaping @Sendable (UlanziClient) async throws -> Void,
                         on link: ClaudeCodeClockLink,
                         going: (@MainActor () -> Void)? = nil,
                         then outcome: @escaping @MainActor (UlanziClient.Failure?) -> Void) {
        let run = self.run
        let event = events
        chain(at: link.address) { [weak self, weak link] in
            guard let self, let link, holds(link, in: run) else { return }
            if let outOfReach = link.outOfReach, event <= outOfReach.through {
                return outcome(.unreachable(outOfReach.reason))
            }
            going?()
            let failure: UlanziClient.Failure?
            do {
                try await call(link.client)
                failure = nil
            } catch {
                failure = error as? UlanziClient.Failure ?? .unreachable(error.localizedDescription)
            }
            guard holds(link, in: run) else { return }
            if case .unreachable(let reason)? = failure {
                link.outOfReach = (through: events, reason: reason)
            }
            link.update(ClockStatus(failure))
            outcome(failure)
        }
    }

    /// Runs `work` once every call queued before it for the device at
    /// `address` is done, whichever link queued them.
    private func chain(at address: URL, _ work: @escaping @MainActor () async -> Void) {
        let previous = lines[address]
        lines[address] = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// What the clocks made of the board's commands, in the order sent. A
    /// hold or a dismissal is taken when one clock took it; an indicator
    /// one of them missed goes again with the next event; a hold they all
    /// missed may change the indicator, and the new one goes at once.
    private func report(_ outcomes: [ClaudeCodeDeliveries<ObjectIdentifier>.Outcome]) {
        guard !outcomes.isEmpty else { return }
        for outcome in outcomes {
            switch outcome.command {
            case .dismiss(let name):
                if outcome.taken {
                    board.dismissLanded(name: name)
                } else {
                    board.dismissFailed(name: name)
                }
            case .notify(let notification):
                guard let name = notification.name else { continue }
                if outcome.taken {
                    board.notifyLanded(name: name)
                } else {
                    board.notifyFailed(name: name, now: now()).forEach(enqueue)
                }
            case .indicator:
                if outcome.missed { board.indicatorFailed() }
            }
        }
        saveBoard()
    }
}

private extension ClaudeCodeHub.ClockStatus {
    /// After a call: ready when it was taken, and otherwise why not.
    init(_ failure: UlanziClient.Failure?) {
        switch failure {
        case nil: self = .ready
        case .unreachable(let reason)?: self = .unreachable(reason)
        case let failure?: self = .rejected(failure.localizedDescription)
        }
    }
}
