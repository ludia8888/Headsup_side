import Foundation

/// GPT-Live supplies timestamped transcript fragments, not completed utterances.
/// Keep a conservative local window before allowing any voice-triggered state change.
public struct LiveConsentTracker {
    public private(set) var question: ConsentGuard.Question = .other
    public private(set) var questionAt: Date?
    private var questionEndMS = -1
    private var outputText = ""
    private var outputEndMS = -1
    private var questionClosed = false
    private var inputText = ""
    private var inputStartMS = -1
    private var inputEndMS = -1
    private var inputFirstAt = Date.distantPast
    private var inputLastAt = Date.distantPast

    public init() {}

    public mutating func recordOutput(_ delta: String, startMS: Int, endMS: Int, now: Date) {
        guard startMS >= 0, endMS >= startMS, endMS >= outputEndMS else { return }
        if outputEndMS >= 0 && startMS - outputEndMS > 1_500 { outputText = ""; questionClosed = false }
        outputText = String((outputText + delta).suffix(300))
        outputEndMS = endMS
        let classified = ConsentGuard.classifyQuestion(outputText)
        if classified != .other {
            if !questionClosed || question != classified {
                question = classified
                questionAt = now
                questionEndMS = endMS
                // Any earlier answer, including speech overlapping the question, is stale.
                inputText = ""; inputStartMS = -1; inputEndMS = -1
                inputFirstAt = .distantPast; inputLastAt = .distantPast
            }
            if outputText.contains("?") || outputText.contains("？") { questionClosed = true }
        } else if outputText.contains("?") || outputText.contains("？") {
            question = .other; questionAt = nil; questionEndMS = -1
        }
    }

    public mutating func recordInput(_ delta: String, startMS: Int, endMS: Int, now: Date) {
        guard startMS >= 0, endMS >= startMS, endMS >= inputEndMS else { return }
        if inputEndMS < 0 || startMS - inputEndMS > 1_500 {
            inputText = ""; inputStartMS = startMS; inputFirstAt = now
        }
        inputText = String((inputText + delta).suffix(300))
        inputEndMS = endMS; inputLastAt = now
    }

    private func settled(_ now: Date) -> Bool {
        let quiet = now.timeIntervalSince(inputLastAt)
        return inputStartMS >= 0 && quiet >= 1.2 && quiet <= 30 && now.timeIntervalSince(inputFirstAt) <= 30
    }

    public func mayConfirmMemory(proposedAt: Date, now: Date) -> Bool {
        guard settled(now), question == .memory, let questionAt, questionAt >= proposedAt,
              now.timeIntervalSince(questionAt) <= 30,
              inputStartMS > questionEndMS, inputFirstAt > questionAt else { return false }
        // Fragments have no turn-final event. A bare "yes" is too easy to misattribute.
        let compact = inputText.replacingOccurrences(of: " ", with: "")
        return (compact.contains("기억해") || compact.contains("저장해")) && ConsentGuard.affirmative(inputText)
    }

    public func mayStartTogether(now: Date) -> Bool {
        guard settled(now), question == .accompany, let questionAt, now.timeIntervalSince(questionAt) <= 30,
              inputStartMS > questionEndMS, inputFirstAt > questionAt else { return false }
        return ConsentGuard.affirmative(inputText)
    }

    public func clearlyRequestsPause(now: Date) -> Bool {
        settled(now) && ConsentGuard.clearlyRequestsPause(inputText)
    }
}
