// SPDX-License-Identifier: Apache-2.0
import Foundation
import CryptoKit
import CMeshCore

public struct ChatLine: Codable, Identifiable {
    public var id = UUID()
    public let local: Bool
    public let text: String
}
public struct AssistanceOffer: Codable, Identifiable {
    public let id: String
    public let name: String
    public let size: Int
    public let kind: String
    public let sha256: String
}
public struct AnnotationStroke: Codable {
    public let points: [[Double]]
    public static func valid(_ strokes: [AnnotationStroke]) -> Bool {
        !strokes.isEmpty && strokes.count <= 32 && strokes.reduce(0, { $0 + $1.points.count }) <= 512 &&
        strokes.allSatisfy { $0.points.count >= 2 && $0.points.allSatisfy {
            $0.count == 2 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) }
        }}
    }
}
public struct GuidedStep: Codable {
    public let id: String
    public let step: Int
    public let total: Int
    public let text: String
    public let captureID: String?
    public let capture: Data?
    public let strokes: [AnnotationStroke]
    public var status = "waiting"
}
public struct AssistanceTransfer: Codable {
    public enum State: String, Codable { case offered, transferring, completed, declined, cancelled, timedOut }
    public let id: String
    public let name: String
    public let total: Int
    public var completed: Int
    public var state: State
    public var fraction: Double { total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0 }
    public var label: String {
        switch state {
        case .offered: return "En attente d’acceptation"
        case .transferring: return "Transfert en cours — \(Int(fraction * 100)) %"
        case .completed: return "Réception confirmée, intégrité vérifiée"
        case .declined: return "Transfert refusé"
        case .cancelled: return "Transfert annulé"
        case .timedOut: return "Délai de transfert dépassé"
        }
    }
}
public struct AssistanceSnapshot: Codable {
    public var revision = UUID()
    public var commandID: UUID?
    public var chatAllowed = true
    public var documentsAllowed = true
    public var messages: [ChatLine] = []
    public var offer: AssistanceOffer?
    public var received: AssistanceOffer?
    public var document: Data?
    public var capture: Data?
    public var captureID: String?
    public var strokes: [AnnotationStroke] = []
    public var captureRequested = false
    public var transfer = ""
    public var sending: AssistanceTransfer?
    public var receiving: AssistanceTransfer?
    public var notice = ""
    public var guide: GuidedStep?
    public var capturePreview: Data?
}
public struct AssistanceCommand: Codable {
    public var id = UUID()
    public let action: String
    public var text: String? = nil
    public var transferID: String? = nil
    public var data: Data? = nil
    public var name: String? = nil
    public var step: Int? = nil
    public init(action: String, text: String? = nil, transferID: String? = nil, data: Data? = nil, name: String? = nil, step: Int? = nil) {
        self.action = action; self.text = text; self.transferID = transferID; self.data = data; self.name = name
        self.step = step
    }
}

/// Queue-confined, one upload and one download, explicit receipt before bytes.
/// No paths received from the network are ever opened. All content is transient.
final class AssistanceEngine {
    private final class GuideGate {
        let handle: UnsafeMutableRawPointer
        init?(total: Int) {
            guard (1...20).contains(total), let handle = mc_guide_new(UInt32(total)) else { return nil }
            self.handle = handle
        }
        deinit { mc_guide_free(handle) }
        func present(_ step: Int) -> Bool {
            (1...20).contains(step) && mc_guide_present(handle, UInt32(step)) == 0
        }
        func respond(_ step: Int, _ response: UInt32) -> Bool {
            (1...20).contains(step) && mc_guide_respond(handle, UInt32(step), response) == 0
        }
    }
    private struct GuideRequest: Decodable {
        let id: String
        let step: Int
        let total: Int
        let text: String
        let captureID: String?
        let strokes: [AnnotationStroke]?
    }
    private final class DocumentGate {
        let handle: UnsafeMutableRawPointer
        init?(size: Int) {
            guard let handle = mc_transfer_new(UInt32(size)) else { return nil }
            self.handle = handle
        }
        deinit { mc_transfer_free(handle) }
        func approve() -> Bool { mc_transfer_approve(handle) == 0 }
        func append(offset: Int, size: Int) -> Bool {
            guard offset >= 0, offset <= AssistanceEngine.maximum, size >= 0, size <= 8192 else { return false }
            return mc_transfer_chunk(handle, UInt32(offset), UInt32(size)) >= 0
        }
    }
    static let maximum = 2 * 1024 * 1024
    var snapshot = AssistanceSnapshot()
    var changed: ((AssistanceSnapshot) -> Void)?
    var send: (([String: Any]) -> Void)?
    private var download = Data()
    private var documentGate: DocumentGate?
    private var accepted = false
    private var upload: (offer: AssistanceOffer, bytes: Data, next: Int, awaiting: Int)?
    private var uploadAt = 0.0, downloadAt = 0.0
    private var lastChat = 0.0, lastCaptureRequest = 0.0
    private var lastAnnotation = 0.0
    private var lastProgress = 0.0
    private var guideGate: GuideGate?
    private var seenGuides = Set<String>()
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    init(chatAllowed: Bool = true, documentsAllowed: Bool = true) {
        snapshot.chatAllowed = chatAllowed; snapshot.documentsAllowed = documentsAllowed
    }
    private func publish() { snapshot.revision = UUID(); changed?(snapshot) }
    private func emit(_ action: String, _ fields: [String: Any] = [:]) {
        var value = fields; value["action"] = action; value["v"] = 1; value["type"] = "iosAssist"; value["ctrlChannel"] = "102938"
        send?(value)
    }
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 128 && name != "." && name != ".." &&
        !name.contains("/") && !name.contains("\\") && name.rangeOfCharacter(from: .controlCharacters) == nil
    }
    private func chat(_ text: String, local: Bool) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 1024 else { return }
        snapshot.messages.append(ChatLine(local: local, text: text))
        snapshot.messages = Array(snapshot.messages.suffix(40)); publish()
    }
    func local(_ command: AssistanceCommand, capture: Data?) {
        defer { snapshot.commandID = command.id; publish() }
        switch command.action {
        case "guideDone", "guideHelp", "guideStop":
            guard snapshot.chatAllowed, let guide = snapshot.guide,
                  guide.id == command.transferID,
                  command.action == "guideStop" || guide.step == command.step else { return }
            let code: UInt32 = command.action == "guideDone" ? 1 : (command.action == "guideHelp" ? 2 : 3)
            guard guideGate?.respond(guide.step, code) == true else { return }
            snapshot.guide?.status = code == 1 ? "done" : (code == 2 ? "help" : "stopped")
            if code == 3 { releaseGuideImage() }
            let response = code == 1 ? "Étape terminée." : (code == 2 ? "J’ai besoin d’aide. Répondez dans le chat." : "Guidage arrêté.")
            chat("Étape \(guide.step)/\(guide.total) : " + response, local: true)
            guideStatus()
        case "chat":
            guard snapshot.chatAllowed else { return }
            if let text = command.text, text.utf8.count <= 1024, !text.isEmpty {
                chat(text, local: true); emit("chat", ["text": text])
            }
        case "accept":
            guard let offer = snapshot.offer, offer.id == command.transferID, !accepted, documentGate?.approve() == true else { return }
            accepted = true; download = Data(); downloadAt = now
            snapshot.receiving?.state = .transferring
            snapshot.transfer = "Réception de " + offer.name; publish()
            emit("ack", ["id": offer.id, "offset": 0])
        case "reject":
            guard let offer = snapshot.offer, offer.id == command.transferID else { return }
            emit("cancel", ["id": offer.id, "reason": "rejected"]); cancelDownload(state: .declined)
        case "document":
            guard snapshot.documentsAllowed else { return }
            if let data = command.data, let name = command.name { offer(data, name: name, kind: "document") }
        case "capture":
            let chosen = snapshot.captureRequested ? snapshot.capturePreview : capture
            guard let capture = chosen, !capture.isEmpty, capture.count <= 524288 else { snapshot.notice = "Aucune image disponible. Demandez une nouvelle capture après l’affichage de l’écran."; return }
            guard upload == nil else { snapshot.transfer = "Attendez la fin de l’envoi en cours."; return }
            snapshot.notice = ""
            snapshot.captureRequested = false
            snapshot.capturePreview = nil
            offer(capture, name: "capture.jpg", kind: "capture")
        case "declineCapture":
            snapshot.captureRequested = false; snapshot.capturePreview = nil
            emit("captureDeclined")
        case "discard":
            snapshot.document = nil; snapshot.received = nil; publish()
        case "cancel":
            if let item = upload { emit("cancel", ["id": item.offer.id]); upload = nil; snapshot.sending?.state = .cancelled }
            if let item = snapshot.offer { emit("cancel", ["id": item.id]); cancelDownload() }
            snapshot.transfer = "Transferts annulés."
        case "clear":
            if let item = upload { emit("cancel", ["id": item.offer.id]); upload = nil }
            if let item = snapshot.offer { emit("cancel", ["id": item.id]); cancelDownload() }
            snapshot.sending = nil; snapshot.receiving = nil; snapshot.transfer = ""
            stopGuide(); snapshot.guide = nil
            snapshot.messages = []; snapshot.strokes = []; snapshot.capture = nil; snapshot.captureID = nil
            snapshot.captureRequested = false; snapshot.capturePreview = nil; snapshot.notice = ""
            snapshot.document = nil; snapshot.received = nil; publish()
        default: break
        }
    }
    func hideScreen() {
        if snapshot.captureRequested { emit("captureDeclined") }
        snapshot.captureRequested = false; snapshot.capturePreview = nil
        if let item = upload, item.offer.kind == "capture" {
            emit("cancel", ["id": item.offer.id])
            upload = nil; snapshot.sending?.state = .cancelled
            snapshot.transfer = "Envoi de la capture annulé."
        }
        publish()
    }

    private func offer(_ data: Data, name: String, kind: String) {
        guard upload == nil else { snapshot.transfer = "Un envoi est déjà en cours. Attendez ou annulez-le."; return }
        guard !data.isEmpty, data.count <= Self.maximum, Self.validName(name) else { return }
        let item = AssistanceOffer(id: UUID().uuidString, name: name, size: data.count, kind: kind,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        upload = (item, data, 0, 0); uploadAt = now
        snapshot.sending = AssistanceTransfer(id: item.id, name: name, total: data.count, completed: 0, state: .offered)
        if kind == "capture" { snapshot.capture = data; snapshot.captureID = item.id; snapshot.strokes = [] }
        snapshot.transfer = "En attente du destinataire : " + name; publish()
        emit("offer", ["id": item.id, "name": name, "size": data.count, "kind": kind, "sha256": item.sha256])
    }
    func receive(_ object: [String: Any], capture: Data? = nil) throws {
        guard object["v"] as? Int == 1, let action = object["action"] as? String else { throw AgentError.protocolViolation }
        switch action {
        case "guideStep":
            guard snapshot.chatAllowed else { throw AgentError.protocolViolation }
            try receiveGuide(object)
        case "guideStop":
            guard snapshot.chatAllowed, let id = object["id"] as? String, UUID(uuidString: id) != nil else { throw AgentError.protocolViolation }
            if id == snapshot.guide?.id { stopGuide(); publish() }
        case "chat":
            guard snapshot.chatAllowed else { throw AgentError.protocolViolation }
            guard let text = object["text"] as? String, text.utf8.count <= 1024 else { throw AgentError.protocolViolation }
            guard now - lastChat >= 0.2 else { return }; lastChat = now; chat(text, local: false)
        case "captureRequest":
            guard now - lastCaptureRequest >= 5 else { return }; lastCaptureRequest = now
            // Keep the frame from Settings while the person returns to our app.
            // A pending preview is immutable until explicitly sent or declined.
            guard !snapshot.captureRequested else { return }
            snapshot.capturePreview = capture.flatMap { !$0.isEmpty && $0.count <= 524288 ? $0 : nil }
            snapshot.captureRequested = true; publish()
        case "annotations":
            guard now - lastAnnotation >= 0.2 else { return }; lastAnnotation = now
            guard let id = object["id"] as? String, id == snapshot.captureID,
                  let data = try? JSONSerialization.data(withJSONObject: object["strokes"] ?? []),
                  let strokes = try? JSONDecoder().decode([AnnotationStroke].self, from: data),
                  AnnotationStroke.valid(strokes) else { throw AgentError.protocolViolation }
            snapshot.strokes = strokes; publish()
        case "offer":
            guard snapshot.documentsAllowed else { throw AgentError.protocolViolation }
            guard let id = object["id"] as? String, UUID(uuidString: id) != nil,
                  let name = object["name"] as? String, Self.validName(name),
                  let size = object["size"] as? Int, (1...Self.maximum).contains(size),
                  object["kind"] as? String == "document",
                  let hash = object["sha256"] as? String, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else {
                throw AgentError.protocolViolation
            }
            guard snapshot.offer == nil, snapshot.document == nil else { emit("cancel", ["id": id]); return }
            guard let gate = DocumentGate(size: size) else { throw AgentError.configuration }
            documentGate = gate
            snapshot.offer = AssistanceOffer(id: id, name: name, size: size, kind: "document", sha256: hash.lowercased())
            snapshot.receiving = AssistanceTransfer(id: id, name: name, total: size, completed: 0, state: .offered)
            downloadAt = now; accepted = false; publish()
        case "chunk":
            guard let item = snapshot.offer, accepted, object["id"] as? String == item.id,
                  let offset = object["offset"] as? Int, offset == download.count,
                  let encoded = object["data"] as? String, encoded.utf8.count <= 10924,
                  let bytes = Data(base64Encoded: encoded),
                  documentGate?.append(offset: offset, size: bytes.count) == true else {
                throw AgentError.protocolViolation
            }
            download.append(bytes); downloadAt = now
            snapshot.receiving?.completed = download.count
            if download.count == item.size {
                let hash = SHA256.hash(data: download).map { String(format: "%02x", $0) }.joined()
                guard hash == item.sha256 else { throw AgentError.protocolViolation }
                snapshot.received = item; snapshot.document = download
                snapshot.offer = nil; accepted = false; download = Data()
                documentGate = nil
                snapshot.receiving?.state = .completed
                snapshot.transfer = "Document reçu. Enregistrez-le ou supprimez-le."; publish()
                emit("ack", ["id": item.id, "offset": item.size])
            } else {
                emit("ack", ["id": item.id, "offset": download.count])
                if now - lastProgress >= 0.5 { lastProgress = now; publish() }
            }
        case "ack":
            guard var item = upload, object["id"] as? String == item.offer.id,
                  let offset = object["offset"] as? Int, offset == item.awaiting else { return }
            uploadAt = now
            snapshot.sending?.completed = offset; snapshot.sending?.state = .transferring
            if offset == item.bytes.count {
                snapshot.sending?.state = .completed
                upload = nil; snapshot.transfer = "Envoi terminé : " + item.offer.name; publish(); return
            }
            let end = min(item.bytes.count, offset + 8192)
            item.next = end; item.awaiting = end; upload = item
            if offset == 0 || now - lastProgress >= 0.5 { lastProgress = now; publish() }
            emit("chunk", ["id": item.offer.id, "offset": offset, "data": item.bytes.subdata(in: offset..<end).base64EncodedString()])
        case "cancel":
            guard let id = object["id"] as? String, UUID(uuidString: id) != nil else { throw AgentError.protocolViolation }
            if id == upload?.offer.id {
                upload = nil
                let reason = object["reason"] as? String
                snapshot.sending?.state = reason == "rejected" ? .declined : (reason == "timeout" ? .timedOut : .cancelled)
                snapshot.transfer = "Envoi refusé ou annulé par le destinataire."; publish()
            }
            if id == snapshot.offer?.id { cancelDownload() }
        default: break
        }
    }
    private func receiveGuide(_ object: [String: Any]) throws {
        let bytes = try JSONSerialization.data(withJSONObject: object)
        guard bytes.count <= 16384, let request = try? JSONDecoder().decode(GuideRequest.self, from: bytes),
              UUID(uuidString: request.id) != nil, (1...20).contains(request.total),
              (1...request.total).contains(request.step), request.text.utf8.count <= 800,
              !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentError.protocolViolation }
        let marks = request.strokes ?? []
        guard marks.isEmpty || AnnotationStroke.valid(marks) else { throw AgentError.protocolViolation }
        func reject(_ reason: String) { emit("guideError", ["id": request.id, "step": request.step, "reason": reason]) }
        if let id = request.captureID {
            guard UUID(uuidString: id) != nil else { throw AgentError.protocolViolation }
            guard id == snapshot.captureID, snapshot.capture != nil else { reject("captureUnavailable"); return }
        } else if !marks.isEmpty { throw AgentError.protocolViolation }
        if request.id != snapshot.guide?.id {
            if let current = snapshot.guide, current.status != "stopped" && !(current.status == "done" && current.step == current.total) {
                reject("guideActive"); return
            }
            guard request.step == 1, !seenGuides.contains(request.id.lowercased()), seenGuides.count < 32,
                  let gate = GuideGate(total: request.total) else { reject("staleGuide"); return }
            guideGate = gate; seenGuides.insert(request.id.lowercased())
        } else if request.total != snapshot.guide?.total { reject("staleStep"); return }
        guard guideGate?.present(request.step) == true else { reject("staleStep"); return }
        snapshot.guide = GuidedStep(id: request.id, step: request.step, total: request.total, text: request.text,
            captureID: request.captureID, capture: request.captureID == nil ? nil : snapshot.capture, strokes: marks)
        chat("Étape \(request.step)/\(request.total)\n" + request.text, local: false)
        guideStatus(); publish()
    }
    private func guideStatus() {
        guard let guide = snapshot.guide else { return }
        emit("guideStatus", ["id": guide.id, "step": guide.step, "total": guide.total, "status": guide.status])
    }
    private func releaseGuideImage() {
        guard let guide = snapshot.guide else { return }
        snapshot.guide = GuidedStep(id: guide.id, step: guide.step, total: guide.total, text: guide.text,
            captureID: nil, capture: nil, strokes: [], status: guide.status)
    }
    private func stopGuide() {
        guard let guide = snapshot.guide, guide.status != "stopped" else { return }
        snapshot.guide?.status = "stopped"; guideGate = nil; releaseGuideImage()
        chat("Guidage arrêté à l’étape \(guide.step)/\(guide.total).", local: false); guideStatus()
    }
    private func cancelDownload(state: AssistanceTransfer.State = .cancelled) {
        snapshot.receiving?.state = state
        documentGate = nil
        snapshot.offer = nil; download = Data(); accepted = false
        snapshot.transfer = state == .declined ? "Document refusé." : (state == .timedOut ? "Délai de réception dépassé." : "Réception annulée.")
        publish()
    }
    func tick() {
        if let item = upload, now - uploadAt > 60 {
            emit("cancel", ["id": item.offer.id, "reason": "timeout"]); upload = nil; snapshot.sending?.state = .timedOut; snapshot.transfer = "Délai d’envoi dépassé."; publish()
        }
        if let item = snapshot.offer, now - downloadAt > 60 { emit("cancel", ["id": item.id, "reason": "timeout"]); cancelDownload(state: .timedOut) }
    }
    func clear() {
        guideGate = nil; seenGuides = []
        documentGate = nil
        upload = nil; download = Data(); accepted = false; snapshot = AssistanceSnapshot(); publish()
    }
}
