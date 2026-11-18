#if DEBUG
import CampusCore

/// Supplies synthetic account state for the UI flow. Core tests exercise persistent cleanup separately.
actor UITestAccounts: AcademicSessionCoordinator {
    private var boundPlatforms: Set<CampusPlatform> = [.academic, .chaoxing]

    func snapshot() -> [ConnectionSnapshot] {
        CampusPlatform.allCases.map { platform in
            let isBound = boundPlatforms.contains(platform)
            return ConnectionSnapshot(
                platform: platform,
                status: isBound ? .connected : .unbound,
                canConnect: false,
                canDisconnect: isBound,
                bindingID: isBound ? "fixture-\(platform.rawValue)" : nil
            )
        }
    }

    func academicData(_ endpoint: AcademicEndpoint, fields: [String: String]?, bindingID: String?) throws -> AcademicDataResult {
        guard bindingID == "fixture-academic" else { throw SessionFailure.superseded }
        guard boundPlatforms.contains(.academic), endpoint == .schedule else { throw SessionFailure.unsupported }
        let term = fields?["xnxq01id"] ?? "synthetic-term"
        let nextTerm = term == "next-term"
        if nextTerm, fields?["zc"] != nil { throw AcademicHTML.Error.unexpectedPage }
        let week = fields?["zc"] ?? (nextTerm ? "1" : "3")
        let schedule = AcademicSchedule(
            terms: [.init(value: "synthetic-term", label: "示例学期"), .init(value: "next-term", label: "下一学期")],
            weeks: nextTerm ? [.init(value: "1", label: "第1周")] : [.init(value: "3", label: "第3周"), .init(value: "4", label: "第4周")],
            fields: ["xnxq01id": term, "zc": week],
            lessons: week == "3" ? [.init(courseName: "示例课程", weekday: 1, startPeriod: 1, endPeriod: 2, weeks: [3])] : [],
            periods: []
        )
        return AcademicDataResult(content: .schedule(schedule), updatedAt: .now, isCached: week == "4")
    }

    func disconnect(_ platform: CampusPlatform) {
        boundPlatforms.remove(platform)
    }

    func connect(_ platform: CampusPlatform, using authorization: any ProviderAuthorization, persistence: CredentialPersistence) throws {
        throw SessionFailure.unsupported
    }

    func probe(_ platform: CampusPlatform) throws -> ConnectionStatus {
        throw SessionFailure.unsupported
    }

    func refresh(_ platform: CampusPlatform) throws -> ConnectionStatus {
        throw SessionFailure.unsupported
    }
}
#endif
