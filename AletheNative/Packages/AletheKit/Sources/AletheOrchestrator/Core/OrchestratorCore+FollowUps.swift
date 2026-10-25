import AletheIntegrations
import Foundation

extension OrchestratorCore {
    func followUpTool(name: String, arguments: OrderedJSONObject) throws(OrchestratorToolError) -> OrderedJSON {
        if case "alethe_steer" = name {
            return try steer(job: Self.requiredArgument(arguments, "jobId"), message: Self.requiredArgument(arguments, "message"))
        } else if case "alethe_send" = name {
            return try send(job: Self.requiredArgument(arguments, "jobId"), message: Self.requiredArgument(arguments, "message"))
        } else if case "alethe_answer" = name {
            return try answer(job: Self.requiredArgument(arguments, "jobId"), decision: Self.requiredArgument(arguments, "decision"))
        } else if case "alethe_diff" = name {
            let jobID = try Self.requiredArgument(arguments, "jobId")
            return ["jobId": .string(jobID), "diff": .string(try jobDiff(jobID))]
        } else {
            throw OrchestratorToolError("unknown tool \(name)")
        }
    }

    static func requiredArgument(_ arguments: OrderedJSONObject, _ key: String) throws(OrchestratorToolError) -> String {
        guard let value = arguments[key]?.stringValue else { throw OrchestratorToolError("\(key) is required") }
        return value
    }

    func existingJob(_ jobID: String) throws(OrchestratorToolError) -> Job {
        guard let job = jobs[jobID] else { throw OrchestratorToolError("unknown job \(jobID)") }
        return job
    }

    public func steer(job jobID: String, message: String) throws(OrchestratorToolError) -> OrderedJSON {
        var job = try existingJob(jobID)
        guard job.threadID != nil else { throw OrchestratorToolError("job \(jobID) has no thread yet") }
        if job.agent == WorkerAgent.claude {
            let steer = ClaudeWorkerProtocol.steer(&job, message: message, workerIsLive: workers[jobID] != nil)
            jobs[jobID] = job
            if case .interrupt(_, let request) = steer { writeToWorker(jobID, request) }
            notify()
            return steer.result
        }
        guard let turnID = job.activeTurnID else {
            throw OrchestratorToolError("job \(jobID) has no running turn to steer")
        }
        guard var session = workers[jobID]?.codex else { throw OrchestratorToolError("job \(jobID) has no live worker") }
        let request = try session.steer(message)
        workers[jobID]?.codex = session
        syncRequestID(jobID)
        writeToWorker(jobID, request)
        return ["steered": .string(jobID), "turnId": .string(turnID)]
    }

    public func send(job jobID: String, message: String) throws(OrchestratorToolError) -> OrderedJSON {
        var job = try existingJob(jobID)
        guard let threadID = job.threadID else { throw OrchestratorToolError("job \(jobID) has no thread") }

        let live = workers[jobID] != nil || spawning[jobID] != nil
        if (live && !job.settled) || job.status == .queued {
            job.inbox.append(message)
            jobs[jobID] = job
            notify()
            return ["queued": .string(jobID), "waiting": .integer(job.inbox.count)]
        }

        guard live else {
            job.inbox.append(message)
            job.status = .queued
            jobs[jobID] = job
            queue.append(jobID)
            notify()
            persist()
            drainQueue()
            return ["revived": .string(jobID), "resumedThread": .string(threadID), "queued": true]
        }

        guard slots.count < concurrencyLimit else {
            throw OrchestratorToolError("concurrency limit \(concurrencyLimit) reached, call alethe_check first")
        }
        let turn: OrderedJSON
        if job.agent == WorkerAgent.claude {
            turn = ClaudeWorkerProtocol.userTurn(message)
        } else {
            guard var session = workers[jobID]?.codex else { throw OrchestratorToolError("job \(jobID) has no live worker") }
            turn = try session.startTurn(message)
            workers[jobID]?.codex = session
            job.nextRequestID = session.nextRequestID
        }
        job.status = .running
        job.outcome = nil
        job.endedAt = nil
        job.reply = ""
        job.report = ""
        jobs[jobID] = job
        slots.insert(jobID)
        writeToWorker(jobID, turn)
        notify()
        persist()
        return ["sent": .string(jobID)]
    }

    public func answer(job jobID: String, decision: CodexApprovalDecision) throws(OrchestratorToolError) -> OrderedJSON {
        var job = try existingJob(jobID)
        guard job.pending != nil else { throw OrchestratorToolError("job \(jobID) is not waiting on anything") }
        guard var session = workers[jobID]?.codex else { throw OrchestratorToolError("job \(jobID) has no live worker") }
        let reply = try session.answer(decision)
        workers[jobID]?.codex = session
        job.pending = nil
        job.status = .running
        jobs[jobID] = job
        writeToWorker(jobID, reply)
        notify()
        persist()
        return ["answered": .string(jobID), "decision": .string(decision.rawValue)]
    }

    public func answer(job jobID: String, decision: String) throws(OrchestratorToolError) -> OrderedJSON {
        guard let parsed = CodexApprovalDecision(rawValue: decision) else {
            let names = CodexApprovalDecision.allCases.map(\.rawValue).joined(separator: ", ")
            throw OrchestratorToolError("decision must be one of \(names)")
        }
        return try answer(job: jobID, decision: parsed)
    }

    public func jobDiff(_ jobID: String) throws(OrchestratorToolError) -> String {
        try existingJob(jobID).diff ?? ""
    }
}
