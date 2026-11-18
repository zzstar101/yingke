import CampusCore
import SwiftUI

struct HomeView: View {
    let academicIsBound: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                masthead
                schedule
                services
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
            .campusColumn()
        }
        .background(CampusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var masthead: some View {
        HStack(spacing: 12) {
            TrailMark()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 25, height: 25)
                .frame(width: 48, height: 48)
                .background(Color(red: 0.12, green: 0.34, blue: 0.25), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("应刻")
                    .font(.title.weight(.bold))
                    .foregroundStyle(CampusTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("广州应用科技学院")
                    .font(.subheadline)
                    .foregroundStyle(CampusTheme.muted)
            }
            Spacer(minLength: 0)
        }
    }

    private var schedule: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            scheduleLink(date: context.date.formatted(Self.campusDateStyle))
        }
    }

    private func scheduleLink(date: String) -> some View {
        let subtitle = academicIsBound ? "查看本周课程安排" : "关联强智教务后查看课程"
        return NavigationLink(value: HomeRoute.timetable) {
            VStack(alignment: .leading, spacing: 8) {
                Text(date)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.80, green: 0.89, blue: 0.81))
                Spacer(minLength: 16)
                Text("今日课表")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.93))
                Label("查看课表入口", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 161, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(24)
            .background {
                GeometryReader { geometry in
                    Image("CampusWalk")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.04, green: 0.17, blue: 0.12).opacity(0.96), location: 0),
                            .init(color: Color(red: 0.03, green: 0.14, blue: 0.10).opacity(0.74), location: 0.53),
                            .init(color: .black.opacity(0.09), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(CampusPressStyle())
        .accessibilityLabel(Text("今日课表，\(date)，\(subtitle)"))
        .accessibilityIdentifier("home.schedule")
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("校园服务")
                .font(.title2.weight(.bold))
                .foregroundStyle(CampusTheme.ink)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(CampusPlatform.allCases, id: \.self) { platform in
                    NavigationLink(value: platform) {
                        VStack(alignment: .leading, spacing: 8) {
                            PlatformIcon(platform: platform)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(platform.name)
                                    .font(.headline)
                                    .foregroundStyle(CampusTheme.ink)
                                Text(platform.summary)
                                    .font(.footnote)
                                    .foregroundStyle(CampusTheme.muted)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading)
                        .padding(14)
                        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18).strokeBorder(CampusTheme.line)
                        }
                    }
                    .buttonStyle(CampusPressStyle())
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private static var campusDateStyle: Date.FormatStyle {
        var style = Date.FormatStyle().month(.twoDigits).day(.twoDigits).weekday(.wide)
        style.locale = Locale(identifier: "zh_CN")
        style.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return style
    }
}
