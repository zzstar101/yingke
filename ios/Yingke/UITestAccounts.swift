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

    func academicData(_ endpoint: AcademicEndpoint, fields: [String: String]?, bindingID: String?, forceRefresh: Bool) throws -> AcademicDataResult {
        guard bindingID == "fixture-academic" else { throw SessionFailure.superseded }
        guard boundPlatforms.contains(.academic), endpoint == .semesterSchedule, fields?["zc"] == nil else {
            throw SessionFailure.unsupported
        }
        let term = fields?["xnxq01id"] ?? "synthetic-term"
        let nextTerm = term == "next-term"
        if term == "offline-term" { throw AcademicHTML.Error.unexpectedPage }
        let schedule = AcademicSchedule(
            terms: [
                .init(value: "synthetic-term", label: "示例学期"),
                .init(value: "next-term", label: "下一学期"),
                .init(value: "offline-term", label: "暂不可用学期")
            ],
            weeks: nextTerm ? [.init(value: "1", label: "第1周")] : [.init(value: "3", label: "第3周"), .init(value: "4", label: "第4周")],
            fields: ["xnxq01id": term],
            lessons: nextTerm ? [] : Self.sampleLessons,
            periods: Self.samplePeriods,
            currentTeachingWeek: nextTerm ? nil : 3
        )
        return AcademicDataResult(content: .schedule(schedule), updatedAt: .now, isCached: !forceRefresh)
    }

    private static let sampleLessons: [AcademicLesson] = [
        .init(courseName: "示例课程", weekday: 1, startPeriod: 1, endPeriod: 2, teacher: "陈老师", location: "教学楼 A302", weeks: [3, 5, 7]),
        .init(courseName: "数据结构", weekday: 3, startPeriod: 1, endPeriod: 2, location: "B204", weeks: [3]),
        .init(courseName: "大学英语", weekday: 5, startPeriod: 1, endPeriod: 2, location: "A205", weeks: [3]),
        .init(courseName: "视觉设计", weekday: 4, startPeriod: 2, endPeriod: 3, location: "艺设 308", weeks: [3]),
        .init(courseName: "高等数学", weekday: 1, startPeriod: 3, endPeriod: 4, location: "B302", weeks: [3]),
        .init(courseName: "实验课", weekday: 3, startPeriod: 3, endPeriod: 4, location: "实验楼 201", weeks: [3]),
        .init(courseName: "数字素养", weekday: 5, startPeriod: 4, endPeriod: 5, location: "C106", weeks: [3]),
        .init(courseName: "体育", weekday: 4, startPeriod: 5, endPeriod: 6, location: "田径场", weeks: [3]),
        .init(courseName: "写作研习", weekday: 1, startPeriod: 6, endPeriod: 7, location: "A406", weeks: [3]),
        .init(courseName: "摄影基础", weekday: 6, startPeriod: 6, endPeriod: 7, location: "艺设 209", weeks: [3]),
        .init(courseName: "创新工坊", weekday: 3, startPeriod: 7, endPeriod: 8, location: "实训楼 405", weeks: [3]),
        .init(courseName: "项目讨论", weekday: 3, startPeriod: 8, endPeriod: 8, location: "实训楼 402", weeks: [3])
    ]

    private static let samplePeriods: [AcademicPeriod] = [
        ("08:30", "09:15"), ("09:25", "10:10"), ("10:30", "11:15"), ("11:25", "12:10"),
        ("14:00", "14:45"), ("14:55", "15:40"), ("16:00", "16:45"), ("16:55", "17:40"),
        ("19:00", "19:45"), ("19:55", "20:40")
    ].enumerated().map { .init(number: $0.offset + 1, startTime: $0.element.0, endTime: $0.element.1) }

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
