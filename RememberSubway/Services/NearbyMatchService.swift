import CryptoKit
import Foundation
import Network

@MainActor
protocol NearbyMatchServing: AnyObject {
    var state: NearbyMatchService.State { get }
    var discoveredRooms: [DiscoveredRoom] { get }
    var messageHandler: ((UUID, MultiplayerEnvelope) -> Void)? { get set }
    var disconnectHandler: ((UUID) -> Void)? { get set }
    var connectionReadyHandler: ((UUID) -> Void)? { get set }
    var failureHandler: ((String) -> Void)? { get set }

    func startHosting(roomName: String, roomCode: String, contentVersion: String)
    func startBrowsing()
    func join(room: DiscoveredRoom, roomCode: String, contentVersion: String)
    func send(_ envelope: MultiplayerEnvelope, to connectionID: UUID?)
    func disconnect(connectionID: UUID)
    func stop()
}

@MainActor
final class NearbyMatchService: ObservableObject, NearbyMatchServing {
    enum State: Equatable {
        case idle
        case browsing
        case hosting(code: String)
        case joining
        case connected
        case failed(String)
    }

    static let serviceType = "_rsubway._tcp"
    private static let queue = DispatchQueue(label: "io.evolveark.remembersubway.nearby", qos: .userInitiated)

    @Published private(set) var state: State = .idle
    @Published private(set) var discoveredRooms: [DiscoveredRoom] = []
    var messageHandler: ((UUID, MultiplayerEnvelope) -> Void)?
    var disconnectHandler: ((UUID) -> Void)?
    var connectionReadyHandler: ((UUID) -> Void)?
    var failureHandler: ((String) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [UUID: SecurePeerConnection] = [:]
    private var roomCode = ""
    private var contentVersion = ""
    private var pendingJoinConnectionID: UUID?

    func startHosting(roomName: String, roomCode: String, contentVersion: String) {
        stop()
        self.roomCode = roomCode
        self.contentVersion = contentVersion
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            parameters.acceptLocalOnly = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: roomName, type: Self.serviceType)
            listener.newConnectionLimit = MultiplayerRoomConfiguration.defaultMaximumPlayers - 1
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in self?.handle(listenerState: newState, code: roomCode) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: Self.queue)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func startBrowsing() {
        stop()
        state = .browsing
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let rooms = results.compactMap(Self.room(from:))
            Task { @MainActor in self?.discoveredRooms = rooms.sorted { $0.name < $1.name } }
        }
        browser.stateUpdateHandler = { [weak self] newState in
            guard case .failed(let error) = newState else { return }
            Task { @MainActor in self?.fail(error.localizedDescription) }
        }
        self.browser = browser
        browser.start(queue: Self.queue)
    }

    func join(room: DiscoveredRoom, roomCode: String, contentVersion: String) {
        guard let endpoint = room.endpoint.base as? NWEndpoint else {
            fail("선택한 방에 연결할 수 없어요.")
            return
        }
        browser?.cancel()
        browser = nil
        state = .joining
        self.roomCode = roomCode
        self.contentVersion = contentVersion
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        let secureConnection = makeSecureConnection(connection, passcode: roomCode)
        pendingJoinConnectionID = secureConnection.id
        connections[secureConnection.id] = secureConnection
        secureConnection.start(queue: Self.queue)
    }

    func send(_ envelope: MultiplayerEnvelope, to connectionID: UUID? = nil) {
        if let connectionID {
            connections[connectionID]?.send(envelope)
        } else {
            for connection in connections.values { connection.send(envelope) }
        }
    }

    func disconnect(connectionID: UUID) {
        connections.removeValue(forKey: connectionID)?.cancel()
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        discoveredRooms = []
        pendingJoinConnectionID = nil
        state = .idle
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < MultiplayerRoomConfiguration.defaultMaximumPlayers - 1 else {
            connection.cancel()
            return
        }
        let secureConnection = makeSecureConnection(connection, passcode: roomCode)
        connections[secureConnection.id] = secureConnection
        secureConnection.start(queue: Self.queue)
    }

    private func makeSecureConnection(_ connection: NWConnection, passcode: String) -> SecurePeerConnection {
        let secureConnection = SecurePeerConnection(connection: connection, passcode: passcode)
        secureConnection.readyHandler = { [weak self, weak secureConnection] in
            guard let id = secureConnection?.id else { return }
            Task { @MainActor in
                guard let self else { return }
                if id == self.pendingJoinConnectionID { self.state = .connected }
                self.connectionReadyHandler?(id)
            }
        }
        secureConnection.messageHandler = { [weak self, weak secureConnection] envelope in
            guard let id = secureConnection?.id else { return }
            Task { @MainActor in self?.messageHandler?(id, envelope) }
        }
        secureConnection.failureHandler = { [weak self, weak secureConnection] error in
            guard let id = secureConnection?.id else { return }
            Task { @MainActor in
                guard let self else { return }
                self.connections.removeValue(forKey: id)
                self.disconnectHandler?(id)
                if id == self.pendingJoinConnectionID, let error {
                    self.fail(error)
                }
            }
        }
        return secureConnection
    }

    private func handle(listenerState: NWListener.State, code: String) {
        switch listenerState {
        case .ready: state = .hosting(code: code)
        case .failed(let error): fail(error.localizedDescription)
        default: break
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        failureHandler?(message)
    }

    nonisolated private static func room(from result: NWBrowser.Result) -> DiscoveredRoom? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        return DiscoveredRoom(id: result.endpoint.debugDescription, name: name, endpoint: AnyHashable(result.endpoint))
    }
}

private final class SecurePeerConnection: @unchecked Sendable {
    let id = UUID()
    var readyHandler: (() -> Void)?
    var messageHandler: ((MultiplayerEnvelope) -> Void)?
    var failureHandler: ((String?) -> Void)?

    private let connection: NWConnection
    private let passcode: String
    private let privateKey = P256.KeyAgreement.PrivateKey()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var symmetricKey: SymmetricKey?
    private var isCancelled = false

    init(connection: NWConnection, passcode: String) {
        self.connection = connection
        self.passcode = passcode
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendFrame(payload: self.privateKey.publicKey.rawRepresentation, encrypted: false)
                self.receiveHeader()
            case .failed(let error): self.finish(error.localizedDescription)
            case .cancelled: self.finish(nil)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ envelope: MultiplayerEnvelope) {
        guard let symmetricKey,
              let encoded = try? encoder.encode(envelope),
              let sealed = try? AES.GCM.seal(encoded, using: symmetricKey),
              let combined = sealed.combined else { return }
        sendFrame(payload: combined, encrypted: true)
    }

    func cancel() {
        isCancelled = true
        connection.cancel()
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let error { self.finish(error.localizedDescription); return }
            guard let data, data.count == 4 else {
                if complete { self.finish(nil) } else { self.receiveHeader() }
                return
            }
            let length = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 1, length <= 65_536 else { self.finish("잘못된 네트워크 메시지예요."); return }
            self.receiveBody(length: Int(length))
        }
    }

    private func receiveBody(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.finish(error.localizedDescription); return }
            guard let data, data.count == length, let flag = data.first else { self.finish("메시지가 완전하지 않아요."); return }
            self.handle(payload: data.dropFirst(), encrypted: flag == 1)
            self.receiveHeader()
        }
    }

    private func handle(payload: Data.SubSequence, encrypted: Bool) {
        if !encrypted {
            guard symmetricKey == nil,
                  let remoteKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: Data(payload)),
                  let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: remoteKey) else {
                finish("보안 연결을 만들지 못했어요.")
                return
            }
            symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(passcode.utf8),
                sharedInfo: Data("rsubway-v1".utf8),
                outputByteCount: 32
            )
            readyHandler?()
            return
        }

        guard let symmetricKey,
              let box = try? AES.GCM.SealedBox(combined: Data(payload)),
              let opened = try? AES.GCM.open(box, using: symmetricKey),
              let envelope = try? decoder.decode(MultiplayerEnvelope.self, from: opened) else {
            finish("참가 코드를 확인해 주세요.")
            return
        }
        messageHandler?(envelope)
    }

    private func sendFrame(payload: Data, encrypted: Bool) {
        var body = Data([encrypted ? 1 : 0])
        body.append(payload)
        var length = UInt32(body.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        connection.send(content: header + body, completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(error.localizedDescription) }
        })
    }

    private func finish(_ error: String?) {
        guard !isCancelled else { return }
        isCancelled = true
        failureHandler?(error)
        connection.cancel()
    }
}
