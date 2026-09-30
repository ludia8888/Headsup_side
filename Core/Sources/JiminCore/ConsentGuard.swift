import Foundation

public enum ConsentGuard {
    public enum Question { case memory, accompany, other }
    public static func classifyQuestion(_ text: String) -> Question {
        let memory = ["기억해도", "기억할까", "기억해둘까", "저장해도", "저장할까"].contains(where: text.contains)
        let accompany = (text.contains("20분") || text.contains("이십 분") || text.contains("같이 있을까")) &&
            ["같이", "함께", "시작"].contains(where: text.contains)
        if memory && accompany { return .other }
        if memory { return .memory }
        if accompany { return .accompany }
        return .other
    }
    public static func affirmative(_ text: String) -> Bool {
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { !ignored.contains($0) }))
        return ["응", "네", "예", "그래", "좋아", "맞아", "동의해", "응좋아", "응그래", "네좋아요",
                "기억해줘", "응기억해줘", "저장해줘", "응저장해줘", "같이하자", "응같이하자", "시작하자"].contains(cleaned)
    }
    public static func clearlyRequestsPause(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        let today = t.contains("오늘")
        let contact = t.contains("전화") || t.contains("연락")
        let stop = ["하지마", "그만", "멈춰", "쉬자", "쉬고싶", "안했으면", "안해줘", "하지말"].contains(where: t.contains)
        let negation = ["멈추지마", "그만하지마", "전화하지말라는게아니", "연락하지말라는게아니"].contains(where: t.contains)
        return today && contact && stop && !negation
    }
    public static func mayConfirmMemory(proposal: MemoryProposal, transcript: String,
                                        spokenAt: Date, question: Question,
                                        questionAt: Date?, now: Date) -> Bool {
        guard question == .memory, let questionAt,
              questionAt >= proposal.proposedAt, spokenAt > questionAt,
              now.timeIntervalSince(spokenAt) >= 0, now.timeIntervalSince(spokenAt) <= 30 else { return false }
        return affirmative(transcript)
    }
}
