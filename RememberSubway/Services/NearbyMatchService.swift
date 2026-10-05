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
            fail(AppLocalization.text("network.error.cannotConnectRoom"))
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
        secureConnection.start()
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
        secureConnection.start()
    }

    private func makeSecureConnection(_ connection: NWConnection, passcode: String) -> SecurePeerConnection {
        SecurePeerConnection(
            connection: connection,
            passcode: passcode,
            queue: Self.queue,
            readyHandler: { [weak self] id in
                Task { @MainActor in
                    guard let self else { return }
                    if id == self.pendingJoinConnectionID { self.state = .connected }
                    self.connectionReadyHandler?(id)
                }
            },
            messageHandler: { [weak self] id, envelope in
                Task { @MainActor in self?.messageHandler?(id, envelope) }
            },
            failureHandler: { [weak self] id, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.connections.removeValue(forKey: id)
                    self.disconnectHandler?(id)
                    if id == self.pendingJoinConnectionID, let error {
                        self.fail(error)
                    }
                }
            }
        )
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

/// 가변 상태(대칭키·취소 여부·인코더)는 모두 `queue`에서만 읽고 쓴다.
/// 메인 액터에서 호출되는 `send`·`cancel`도 이 큐로 넘겨 직렬화하므로 별도 락 없이 안전하다.
private final class SecurePeerConnection: @unchecked Sendable {
    let id = UUID()

    private let connection: NWConnection
    private let passcode: String
    private let queue: DispatchQueue
    private let readyHandler: @Sendable (UUID) -> Void
    private let messageHandler: @Sendable (UUID, MultiplayerEnvelope) -> Void
    private let failureHandler: @Sendable (UUID, String?) -> Void
    private let privateKey = P256.KeyAgreement.PrivateKey()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var symmetricKey: SymmetricKey?
    private var isCancelled = false

    init(
        connection: NWConnection,
        passcode: String,
        queue: DispatchQueue,
        readyHandler: @escaping @Sendable (UUID) -> Void,
        messageHandler: @escaping @Sendable (UUID, MultiplayerEnvelope) -> Void,
        failureHandler: @escaping @Sendable (UUID, String?) -> Void
    ) {
        self.connection = connection
        self.passcode = passcode
        self.queue = queue
        self.readyHandler = readyHandler
        self.messageHandler = messageHandler
        self.failureHandler = failureHandler
    }

    func start() {
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
        queue.async { [weak self] in
            guard let self,
                  let symmetricKey = self.symmetricKey,
                  let encoded = try? self.encoder.encode(envelope),
                  let sealed = try? AES.GCM.seal(encoded, using: symmetricKey),
                  let combined = sealed.combined else { return }
            self.sendFrame(payload: combined, encrypted: true)
        }
    }

    func cancel() {
        queue.async { [self] in
            isCancelled = true
            connection.cancel()
        }
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
            guard length > 1, length <= 65_536 else {
                self.finish(AppLocalization.text("network.error.invalidMessage"))
                return
            }
            self.receiveBody(length: Int(length))
        }
    }

    private func receiveBody(length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { self.finish(error.localizedDescription); return }
            guard let data, data.count == length, let flag = data.first else {
                self.finish(AppLocalization.text("network.error.incompleteMessage"))
                return
            }
            self.handle(payload: data.dropFirst(), encrypted: flag == 1)
            self.receiveHeader()
        }
    }

    private func handle(payload: Data.SubSequence, encrypted: Bool) {
        if !encrypted {
            guard symmetricKey == nil,
                  let remoteKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: Data(payload)),
                  let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: remoteKey) else {
                finish(AppLocalization.text("network.error.secureConnection"))
                return
            }
            symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(passcode.utf8),
                sharedInfo: Data("rsubway-v1".utf8),
                outputByteCount: 32
            )
            readyHandler(id)
            return
        }

        guard let symmetricKey,
              let box = try? AES.GCM.SealedBox(combined: Data(payload)),
              let opened = try? AES.GCM.open(box, using: symmetricKey),
              let envelope = try? decoder.decode(MultiplayerEnvelope.self, from: opened) else {
            finish(AppLocalization.text("network.error.checkJoinCode"))
            return
        }
        messageHandler(id, envelope)
    }

    private func sendFrame(payload: Data, encrypted: Bool) {
        var body = Data([encrypted ? 1 : 0])
        body.append(payload)
        var length = UInt32(body.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        connection.send(content: header + body, completion: .contentProcessed { [weak self] error in
            // 완료 콜백은 연결의 큐(`queue`)에서 호출된다.
            if let error { self?.finish(error.localizedDescription) }
        })
    }

    private func finish(_ error: String?) {
        guard !isCancelled else { return }
        isCancelled = true
        failureHandler(id, error)
        connection.cancel()
    }
}
