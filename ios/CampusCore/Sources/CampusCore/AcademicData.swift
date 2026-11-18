import Foundation

public enum AcademicContent: Sendable, Codable {
    case schedule(AcademicSchedule)
    case grades(AcademicGrades)
    case exams(AcademicRecords)
    case plan(AcademicRecords)

    func checkSelection(_ fields: [String: String]?) throws {
        guard let fields else { return }
        switch self {
        case .schedule(let schedule):
            guard fields.allSatisfy({ schedule.fields[$0.key] == $0.value }) else {
                throw AcademicHTML.Error.unexpectedPage
            }
        case .grades(let grades):
            if let term = fields["kksj"], grades.selectedTerm != term {
                throw AcademicHTML.Error.unexpectedPage
            }
        case .exams, .plan:
            break
        }
    }

    init(endpoint: AcademicEndpoint, html: String) throws {
        switch endpoint {
        case .schedule: self = .schedule(try AcademicHTML.schedule(html))
        case .grades: self = .grades(try AcademicHTML.grades(html))
        case .exams: self = .exams(try AcademicHTML.exams(html))
        case .plan: self = .plan(try AcademicHTML.plan(html))
        }
    }
}

public struct AcademicDataResult: Sendable {
    public let content: AcademicContent
    public let updatedAt: Date
    public let isCached: Bool
    public let needsAuthorization: Bool

    public init(content: AcademicContent, updatedAt: Date, isCached: Bool, needsAuthorization: Bool = false) {
        self.content = content
        self.updatedAt = updatedAt
        self.isCached = isCached
        self.needsAuthorization = needsAuthorization
    }
}

public protocol AcademicSessionCoordinator: SessionCoordinator {
    func academicData(_ endpoint: AcademicEndpoint, fields: [String: String]?, bindingID: String?) async throws -> AcademicDataResult
}

protocol AcademicPageProvider: Provider {
    func page(_ endpoint: AcademicEndpoint, session: ProviderSession, fields: [String: String]?) async throws -> AcademicPage
}

extension AcademicProvider: AcademicPageProvider {}
