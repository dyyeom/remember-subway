import Foundation

struct MultiplayerEnvelope: Codable, Sendable {
    static let currentProtocolVersion = 1

    let protocolVersion: Int
    let contentVersion: String
    let matchID: UUID?
    let sequenceNumber: UInt64
    let message: MultiplayerMessage

    init(
        contentVersion: String,
        matchID: UUID? = nil,
        sequenceNumber: UInt64,
        message: MultiplayerMessage
    ) {
        protocolVersion = Self.currentProtocolVersion
        self.contentVersion = contentVersion
        self.matchID = matchID
        self.sequenceNumber = sequenceNumber
        self.message = message
    }
}

enum MultiplayerMessage: Codable, Sendable {
    case hello
    case joinRequest(JoinRequest)
    case joinResponse(JoinResponse)
    case lobbySnapshot(LobbySnapshot)
    case playerRemoved(UUID)
    case matchStart(MatchStart)
    case roundStart(RoundStart)
    case answerSubmission(AnswerSubmission)
    case hintUsed(UUID)
    case answerResult(AnswerResult)
    case roundResult(RoundResult)
    case matchResult(MatchResult)
    case heartbeat(Date)
    case reconnectRequest(playerID: UUID, nickname: String)
    case rematchRequest(UUID)
    case matchCancelled(String)
}

struct JoinRequest: Codable, Sendable {
    let playerID: UUID
    let nickname: String
}

struct JoinResponse: Codable, Sendable {
    let accepted: Bool
    let reason: String?
    let player: NearbyPlayer?
}

struct LobbySnapshot: Codable, Sendable {
    let roomCode: String?
    let configuration: MultiplayerRoomConfiguration
    let players: [NearbyPlayer]
}

struct MatchStart: Codable, Sendable {
    let configuration: MultiplayerRoomConfiguration
    let questions: [MultiplayerQuestion]
    let players: [PlayerMatchState]
    let countdownStartedAt: Date
}

struct RoundStart: Codable, Sendable {
    let roundIndex: Int
    let question: MultiplayerQuestion
    let startsAt: Date
    let deadline: Date
}

struct AnswerSubmission: Codable, Sendable {
    let playerID: UUID
    let answer: String
    let elapsed: TimeInterval
    let hintUsed: Bool
}

struct AnswerResult: Codable, Sendable {
    let isCorrect: Bool
    let wrongAttempts: Int
    let isLocked: Bool
}

struct RoundResult: Codable, Sendable {
    let roundIndex: Int
    let targetStationName: String
    let players: [PlayerMatchState]
}

struct MatchResult: Codable, Sendable {
    let players: [PlayerMatchState]
}

struct DiscoveredRoom: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let name: String
    let endpoint: AnyHashable

    static func == (lhs: DiscoveredRoom, rhs: DiscoveredRoom) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
