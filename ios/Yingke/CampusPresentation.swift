import CampusCore
import SwiftUI
import UIKit

extension CampusPlatform {
    var name: String {
        switch self {
        case .academic: "强智教务"
        case .chaoxing: "学习通"
        case .campusSSO: "统一身份认证"
        case .secondClassroom: "到梦空间"
        }
    }

    var symbol: String {
        switch self {
        case .academic: "calendar"
        case .chaoxing: "books.vertical"
        case .campusSSO: "person.badge.key"
        case .secondClassroom: "flag"
        }
    }

    var summary: String {
        switch self {
        case .academic: "课表、成绩与考试"
        case .chaoxing: "课程、作业与图书馆"
        case .campusSSO: "审批、预约与 WebVPN"
        case .secondClassroom: "校园活动与二课学分"
        }
    }

    var services: [String] {
        switch self {
        case .academic: ["课程表", "成绩查询", "考试安排", "培养方案"]
        case .chaoxing: ["课程", "作业", "考试", "图书馆", "图书检索", "智慧微空间预约"]
        case .campusSSO: ["流程审批", "实验室预约", "校园 WebVPN"]
        case .secondClassroom: ["热门与最新活动", "活动报名", "现场活动签到", "第二课堂学分", "已关注部落与新活动提醒"]
        }
    }
}

extension ConnectionStatus {
    var label: String {
        switch self {
        case .unbound: "未绑定"
        case .authenticating: "正在绑定"
        case .connected: "已绑定"
        case .expired: "会话已过期"
        case .actionRequired: "需要重新授权"
        case .temporarilyUnavailable: "服务暂不可用"
        case .disconnecting: "正在解绑"
        case .cleanupRequired: "需要继续清理"
        }
    }
}

enum CampusTheme {
    static let background = adaptive(0xF6F5EF, 0x141A16)
    static let surface = adaptive(0xFFFFFF, 0x1D2620)
    static let accent = adaptive(0x205C42, 0xA7D3B3)
    static let ink = adaptive(0x16251C, 0xEDF4EC)
    static let muted = adaptive(0x536458, 0xB3C0B5)
    static let soft = adaptive(0xE7EEE4, 0x29392F)
    static let line = adaptive(0xE2E7DD, 0x37443A)

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255,
                alpha: 1
            )
        })
    }
}

struct TrailMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
            }
            path.move(to: point(0.18, 0.82))
            path.addLine(to: point(0.18, 0.49))
            path.addQuadCurve(to: point(0.51, 0.18), control: point(0.18, 0.18))
            path.addQuadCurve(to: point(0.84, 0.49), control: point(0.84, 0.18))
            path.addLine(to: point(0.84, 0.82))
            path.move(to: point(0.39, 0.82))
            path.addLine(to: point(0.39, 0.55))
            path.addQuadCurve(to: point(0.64, 0.55), control: point(0.52, 0.29))
            path.addLine(to: point(0.64, 0.82))
        }
    }
}

struct PlatformIcon: View {
    let platform: CampusPlatform
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    var body: some View {
        Image(systemName: platform.symbol)
            .font(.title3.weight(.medium))
            .foregroundStyle(CampusTheme.accent)
            .frame(width: side, height: side)
            .background(CampusTheme.soft, in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }
}

struct CampusPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.74 : 1)
    }
}

extension View {
    func campusColumn(maxWidth: CGFloat = 640) -> some View {
        frame(maxWidth: maxWidth)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
    }
}
