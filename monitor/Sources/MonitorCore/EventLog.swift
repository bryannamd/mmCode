import Foundation

/// `.mmcode/events.jsonl`을 처음부터 읽어 계획별 상태를 계산한다(orchestration-plan 4.1절).
/// 깨진 줄, 모르는 type, 필수 값이 빠진 줄은 건너뛴다. 쓰는 중인 마지막 줄이 깨져 있을 수 있기 때문이다.
public enum EventLog {
    public struct Result: Equatable, Sendable {
        /// 처음 나온 순서의 계획 목록.
        public var plans: [PlanState] = []
        /// 상태에 반영한 줄 수.
        public var processed = 0
        /// 반영하지 못한 줄 수(깨진 줄, 모르는 type, 필수 값 없음). 빈 줄은 세지 않는다.
        public var skipped = 0
    }

    /// 파일이 없거나 읽을 수 없으면 빈 결과를 돌려준다.
    public static func read(url: URL) -> Result {
        guard let data = try? Data(contentsOf: url) else { return Result() }
        // 바이트 0x0A로만 나눈다. U+2028 같은 글자는 사유 안에 그대로 들어올 수 있다.
        return reduce(lines: data.split(separator: 0x0A).map { String(decoding: $0, as: UTF8.self) })
    }

    public static func reduce(lines: [String]) -> Result {
        var r = Result()
        var order: [String] = []
        var plans: [String: PlanState] = [:]
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            guard let e = Event(line: text) else { r.skipped += 1; continue }
            // 꺼내서 고친 뒤 다시 넣는다. 사본을 만들면 이벤트마다 배열을 복사하게 된다.
            let isNew = plans[e.plan] == nil
            var p = plans.removeValue(forKey: e.plan) ?? PlanState(plan: e.plan)
            let ok = apply(e, to: &p)
            if ok || !isNew {
                plans[e.plan] = p
                if isNew { order.append(e.plan) }
            }
            if ok { r.processed += 1 } else { r.skipped += 1 }
        }
        r.plans = order.compactMap { id in
            guard var p = plans[id] else { return nil }
            p.units.sort { unitOrder($0.id) < unitOrder($1.id) }
            return p
        }
        return r
    }

    // MARK: 줄 하나

    private struct Event {
        let ts: Date
        let type: String
        let plan: String
        let unit: String?
        let actor: Actor?
        let data: [String: Any]

        init?(line: String) {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = obj["type"] as? String,
                  let plan = obj["plan"] as? String, !plan.isEmpty,
                  let ts = (obj["ts"] as? String).flatMap(ISO.parse) else { return nil }
            self.ts = ts
            self.type = type
            self.plan = plan
            self.unit = str(obj, "unit")
            self.data = obj["data"] as? [String: Any] ?? [:]
            if let a = obj["actor"] as? [String: Any] {
                let actor = Actor(terminal: str(a, "terminal"), harness: str(a, "harness").map(Harness.init(raw:)),
                                  model: str(a, "model"), effort: str(a, "effort"))
                self.actor = actor == Actor() ? nil : actor
            } else {
                self.actor = nil
            }
        }
    }

    /// 형식이 맞아 상태를 바꿨으면 true. false면 `p`는 바뀌지 않아야 한다(검사를 먼저, 변경은 나중).
    private static func apply(_ e: Event, to p: inout PlanState) -> Bool {
        let d = e.data
        switch e.type {
        case "unit.phase":
            guard let id = e.unit, let to = str(d, "to").flatMap(Phase.init(rawValue:)) else { return false }
            let i = unitIndex(id, &p)
            p.units[i].phase = to
            // 쓰는 쪽(phase.sh)과 같게: 검증에 다시 들어가면 지난 회차의 증거를, 구현에 다시 들어가면 커밋을 비운다.
            if to == .verify { p.units[i].evidence = [] }
            if to == .build { p.units[i].commit = nil }
            if let a = e.actor { p.units[i].owner = a }
            p.units[i].backReason = str(d, "reason")
            p.units[i].updated = e.ts

        case "check.result":
            guard let id = e.unit, let kind = str(d, "kind").flatMap(EvidenceKind.init(rawValue:)),
                  let pass = d["pass"] as? Bool else { return false }
            let i = unitIndex(id, &p)
            p.units[i].evidence.append(Evidence(kind: kind, pass: pass, command: str(d, "command"), exit: d["exit"] as? Int,
                                                reason: str(d, "reason"), path: str(d, "evidence"), ts: e.ts))

        case "unit.commit":
            guard let id = e.unit, let hash = str(d, "hash") else { return false }
            p.units[unitIndex(id, &p)].commit = hash

        case "unit.halt":
            guard let reason = str(d, "reason") else { return false }
            if Halt.isHalt(reason: reason) {
                let halt = Halt(reason: reason, unit: haltUnit(reason, e.unit), ts: e.ts)
                if let u = halt.unit {
                    p.units[unitIndex(u, &p)].halt = halt
                } else {
                    p.halts.removeAll { $0.reason == reason }
                    p.halts.append(halt)
                }
            }

        case "unit.resume":
            let reason = str(d, "reason")
            let target = reason.flatMap { haltUnit($0, nil) } ?? e.unit
            func matches(_ h: Halt) -> Bool { reason == nil || h.reason == reason }
            if let t = target, let i = p.units.firstIndex(where: { $0.id == t }), let h = p.units[i].halt, matches(h) {
                p.units[i].halt = nil
            }
            // 단위가 없거나 사유를 지정했으면 계획 전체의 멈춤도 푼다. 단위만 지정하고 사유가 없으면 그 단위만 푼다.
            if target == nil || reason != nil { p.halts.removeAll(where: matches) }
            if target == nil && reason != nil {
                for i in p.units.indices where p.units[i].halt.map(matches) == true { p.units[i].halt = nil }
            }

        // U4에서 형식이 정해지면 여기부터 "형식 미확정" 끝까지만 고친다. 지금은 제안 형식을 너그럽게 읽는다.
        // MARK: 형식 미확정
        case "decision.ask":
            guard let q = str(d, "question") else { return false }
            let id = str(d, "id") ?? "D\(p.decisions.count + 1)"
            let blocks = (d["blocks"] as? [String]) ?? str(d, "blocks").map { [$0] } ?? []
            let dec = Decision(id: id, question: q, recommendation: str(d, "recommendation"), impact: str(d, "impact"),
                               blocks: blocks, meanwhile: str(d, "meanwhile"), asker: e.actor, ts: e.ts)
            if let i = p.decisions.firstIndex(where: { $0.id == id }) { p.decisions[i] = dec } else { p.decisions.append(dec) }

        case "decision.answer":
            guard let answer = str(d, "answer") else { return false }
            // id가 없으면 가장 오래된 열린 요청을 닫는다.
            let i = str(d, "id").map { id in p.decisions.firstIndex { $0.id == id } } ?? p.decisions.firstIndex { $0.isOpen }
            guard let i else { return false }
            p.decisions[i].answer = answer

        case "directive.received":
            guard let kind = str(d, "kind").flatMap(DirectiveKind.init(rawValue:)) else { return false }
            let id = str(d, "id") ?? "R\(p.directives.count + 1)"
            let dir = Directive(id: id, kind: kind, text: str(d, "text"), status: .received, reason: nil, ts: e.ts)
            if let i = p.directives.firstIndex(where: { $0.id == id }) { p.directives[i] = dir } else { p.directives.append(dir) }

        case "directive.applied", "directive.rejected":
            let status: DirectiveStatus = e.type == "directive.applied" ? .applied : .rejected
            let kind = str(d, "kind").flatMap(DirectiveKind.init(rawValue:))
            // id가 없으면 같은 kind의 가장 오래된 접수 건에 적용한다.
            let i = str(d, "id").map { id in p.directives.firstIndex { $0.id == id } }
                ?? kind.flatMap { k in p.directives.firstIndex { $0.kind == k && $0.status == .received } }
            guard let i else { return false }
            p.directives[i].status = status
            p.directives[i].reason = str(d, "reason")

        case "plan.approve":
            // units: ["U1", …] 또는 [{id, title}]. 승인된 단위는 대기로 만든다.
            for raw in d["units"] as? [Any] ?? [] {
                let id = raw as? String ?? str(raw as? [String: Any] ?? [:], "id")
                guard let id, !id.isEmpty else { continue }
                let i = unitIndex(id, &p)
                if let title = str(raw as? [String: Any] ?? [:], "title") { p.units[i].title = title }
            }

        case "session.start", "session.stop":
            break  // 행위자 갱신만 한다(아래).
        // MARK: 형식 미확정 끝

        default:
            return false
        }

        if let a = e.actor, let t = a.terminal {
            var cur = p.actors[t] ?? Actor()
            cur.terminal = t
            cur.harness = a.harness ?? cur.harness
            cur.model = a.model ?? cur.model
            cur.effort = a.effort ?? cur.effort
            p.actors[t] = cur
        }
        p.updated = max(p.updated ?? e.ts, e.ts)
        return true
    }

    // MARK: 도우미

    private static func unitIndex(_ id: String, _ p: inout PlanState) -> Int {
        if let i = p.units.firstIndex(where: { $0.id == id }) { return i }
        p.units.append(UnitState(id: id))
        return p.units.count - 1
    }

    /// 멈춤이 걸리는 단위. `blocked:<단위>`는 사유가 가리키는 단위, 그 밖에는 이벤트의 단위.
    private static func haltUnit(_ reason: String, _ eventUnit: String?) -> String? {
        if reason.hasPrefix("blocked:") {
            let u = String(reason.dropFirst("blocked:".count))
            if !u.isEmpty { return u }
        }
        return eventUnit
    }

    /// 번호 순, 같은 번호의 `-fix<회차>`는 본 단위 뒤. 형식이 다른 ID는 맨 뒤에 글자 순.
    private static func unitOrder(_ id: String) -> (Int, Int, String) {
        let rest = id.dropFirst()
        let digits = rest.prefix { $0.isNumber }
        guard id.hasPrefix("U"), let n = Int(digits) else { return (Int.max, 0, id) }
        let fix = rest.dropFirst(digits.count).dropFirst("-fix".count)
        return (n, rest.dropFirst(digits.count).hasPrefix("-fix") ? Int(fix) ?? 1 : 0, id)
    }
}

/// 빈 문자열은 값이 없는 것으로 본다. 문자열이 아니면 nil.
private func str(_ d: [String: Any], _ key: String) -> String? {
    guard let s = d[key] as? String, !s.isEmpty else { return nil }
    return s
}

/// 시간대가 붙은 ISO 8601. 소수 초가 있어도 읽는다.
private enum ISO {
    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ s: String) -> Date? { plain.date(from: s) ?? fractional.date(from: s) }
}
