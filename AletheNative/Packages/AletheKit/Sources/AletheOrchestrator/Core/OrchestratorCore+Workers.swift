import Darwin
import Foundation
import AletheFoundation
import AletheGit
import AletheModel
import AletheIntegrations

extension OrchestratorCore {
    func spawnWorker(_ jobID: String) {
        guard var job = jobs[jobID] else { return }
        job.status = .running
        job.startedAt = Self.nowMs()
        job.endedAt = nil
        let rules = (try? workerRulesBlock(named: job.rulesName)) ?? ((try? workerRulesBlock(named: nil)) ?? "")
        let firstTurn = rules + (job.inbox.isEmpty ? job.spec : job.inbox.removeFirst())
        jobs[jobID] = job
        slots.insert(jobID)

        let launcher: Launcher
        do {
            launcher = try launchers.launcher(for: job.agent)
        } catch {
            finishTurn(jobID, status: .failed, outcome: "failed", text: error.description, terminal: true)
            return
        }

        generationCounter += 1
        let generation = generationCounter
        spawning[jobID] = generation
        var arguments = launcher.arguments(resuming: job.agent == WorkerAgent.claude ? job.threadID : nil)
        if job.agent == WorkerAgent.claude {
            if let model = job.model { arguments += ["--model", model] }
            if let effort = job.effort { arguments += ["--effort", effort] }
        }
        let environment = configuration.environment(launcher)
        let directory = URL(filePath: job.cwd, directoryHint: .isDirectory)
        let registry = configuration.registry
        let grace = configuration.terminationGrace
        spawnTasks[generation] = Task.detached { [weak self] in
            let result: Result<WorkerProcess, WorkerProcessError>
            do throws(WorkerProcessError) {
                result = .success(try WorkerProcess.spawn(
                    launcher, in: directory, arguments: arguments, environment: environment,
                    jobID: jobID, registry: registry, grace: grace))
            } catch {
                result = .failure(error)
            }
            if let self {
                await self.attach(jobID, generation: generation, firstTurn: firstTurn, result: result)
            } else if case .success(let process) = result {
                await process.terminate()
            }
        }
        notify()
    }

    private func attach(_ jobID: String, generation: UInt64, firstTurn: String,
                        result: Result<WorkerProcess, WorkerProcessError>) {
        spawnTasks[generation] = nil
        let current = spawning[jobID] == generation
        if current { spawning[jobID] = nil }
        let process: WorkerProcess
        if case .failure(let error) = result {
            if current {
                finishTurn(jobID, status: .failed, outcome: "failed", text: error.description, terminal: true)
            }
            return
        } else {
            guard case .success(let spawned) = result else {
                preconditionFailure("Invalid enum case")
            }
            process = spawned
        }
        guard current, var job = jobs[jobID], !job.settled else {
            terminate(process)
            return
        }

        var handle = WorkerHandle(process: process, generation: generation)
        if job.agent == WorkerAgent.claude {
            process.writer.send(ClaudeWorkerProtocol.userTurn(firstTurn))
        } else {
            let session = CodexWorkerSession(job: job, firstTurn: firstTurn, disabledPlugins: orchestrationSettings.workerDisabledPlugins)
            for message in session.handshake() { process.writer.send(message) }
            handle.codex = session
        }
        if let timeoutMs = job.timeoutMs {
            handle.watchdog = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(timeoutMs))
                guard !Task.isCancelled else { return }
                await self?.watchdogFired(jobID, generation: generation, timeoutMs: timeoutMs)
            }
        }
        handle.pump = Task.detached { [weak self] in
            for await message in process.lines {
                guard let self else { return }
                await self.receive(message, jobID: jobID, generation: generation)
            }
            await self?.workerExited(jobID, generation: generation)
        }
        workers[jobID] = handle
        job.nextRequestID = handle.codex?.nextRequestID ?? job.nextRequestID
        jobs[jobID] = job
        notify()
    }

    private func receive(_ message: OrderedJSON, jobID: String, generation: UInt64) async {
        guard let handle = workers[jobID], handle.generation == generation, jobs[jobID] != nil else { return }
        if let limit = QueueLimit.workerMessage(message) {
            finishTurn(jobID, status: .failed, outcome: "failed", text: limit, terminal: true)
            return
        }
        if handle.codex != nil {
            receiveCodex(message, jobID: jobID, handle: handle)
        } else {
            await receiveClaude(message, jobID: jobID, generation: generation)
        }
    }

    private func receiveCodex(_ message: OrderedJSON, jobID: String, handle: WorkerHandle) {
        guard var session = handle.codex, var job = jobs[jobID] else { return }
        let step = session.receive(message)
        var changed = false
        var asked = false
        var ended: (succeeded: Bool, summary: String)?
        for event in step.events {
            job.apply(event)
            if case .replyDelta = event {
            } else if case .requestFailed = event {
            } else if case .approvalRequested = event {
                asked = true
                changed = true
            } else if case .turnEnded(let succeeded, let summary) = event {
                ended = (succeeded, summary)
            } else {
                changed = true
            }
        }
        job.nextRequestID = session.nextRequestID
        jobs[jobID] = job
        workers[jobID]?.codex = session
        for outgoing in step.outgoing { handle.process.writer.send(outgoing) }

        if let ended {
            finishTurn(jobID, status: ended.succeeded ? .done : .failed,
                       outcome: ended.succeeded ? "succeeded" : "failed", text: ended.summary, terminal: false)
        } else if changed {
            notify()
        }
        if asked { signal() }
    }

    private func receiveClaude(_ message: OrderedJSON, jobID: String, generation: UInt64) async {
        guard var job = jobs[jobID] else { return }
        let event = ClaudeWorkerProtocol.handle(message, job: &job)
        jobs[jobID] = job
        if case .ignored = event {
            return
        } else if case .updated = event {
            notify()
        } else {
            guard case .turnEnded(let end) = event else {
                preconditionFailure("Invalid enum case")
            }
            let diff = await configuration.uncommittedDiff(job.cwd)
            guard workers[jobID]?.generation == generation else { return }
            if let diff { jobs[jobID]?.diff = diff }
            finishTurn(jobID, status: end.status, outcome: end.outcome, text: end.text,
                       terminal: false, announce: end.announce)
        }
    }

    private func workerExited(_ jobID: String, generation: UInt64) {
        guard workers[jobID]?.generation == generation else { return }
        if let job = jobs[jobID], !job.settled {
            finishTurn(jobID, status: .failed, outcome: "failed", text: "worker connection closed", terminal: true)
        } else {
            teardownWorker(jobID)
            notify()
        }
    }

    private func watchdogFired(_ jobID: String, generation: UInt64, timeoutMs: UInt64) {
        guard workers[jobID]?.generation == generation, let job = jobs[jobID], !job.settled else { return }
        if let interrupt = workers[jobID]?.codex?.interrupt() {
            writeToWorker(jobID, interrupt)
            syncRequestID(jobID)
        }
        finishTurn(jobID, status: .failed, outcome: "timeout",
                   text: "worker passed its \(timeoutMs / 1000)s budget and was stopped", terminal: true)
    }

    func writeToWorker(_ jobID: String, _ message: OrderedJSON) {
        workers[jobID]?.process.writer.send(message)
    }

    func syncRequestID(_ jobID: String) {
        if let next = workers[jobID]?.codex?.nextRequestID { jobs[jobID]?.nextRequestID = next }
    }

    var parkedJobIDs: [String] {
        order.filter { id in workers[id] != nil && jobs[id]?.settled == true }
    }

    func teardownWorker(_ jobID: String) {
        spawning[jobID] = nil
        guard let handle = workers.removeValue(forKey: jobID) else { return }
        handle.watchdog?.cancel()
        handle.pump?.cancel()
        terminate(handle.process)
    }

    func terminate(_ process: WorkerProcess) {
        terminationCounter += 1
        let id = terminationCounter
        terminations[id] = Task.detached { [weak self] in
            await process.terminate()
            await self?.terminationFinished(id)
        }
    }

    private func terminationFinished(_ id: UInt64) {
        terminations[id] = nil
    }
}
