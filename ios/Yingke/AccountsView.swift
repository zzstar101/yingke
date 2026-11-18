import CampusCore
import SwiftUI

struct AccountsView: View {
    let model: AccountsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("校园账号")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(CampusTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("各平台独立绑定，按需使用。")
                        .font(.body)
                        .foregroundStyle(CampusTheme.muted)
                }
                VStack(spacing: 0) {
                    ForEach(CampusPlatform.allCases, id: \.self) { platform in
                        if platform != CampusPlatform.allCases.first {
                            Divider().overlay(CampusTheme.line).padding(.horizontal, 16)
                        }
                        platformRow(platform)
                    }
                }
                .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 21))
                .overlay {
                    RoundedRectangle(cornerRadius: 21).strokeBorder(CampusTheme.line)
                        .allowsHitTesting(false)
                }
                if model.loadFailed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("无法读取本机账号状态。")
                            .foregroundStyle(CampusTheme.ink)
                        Button("重试") { Task { await model.reload() } }
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 4)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.title3)
                        .foregroundStyle(CampusTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("凭据只保存在本机")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CampusTheme.ink)
                        Text("绑定时保存的凭据由 iOS 钥匙串保护。")
                            .font(.subheadline)
                            .foregroundStyle(CampusTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(CampusTheme.soft, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
            .campusColumn()
        }
        .background(CampusTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func platformRow(_ platform: CampusPlatform) -> some View {
        let statusLabel = model.snapshot(for: platform)?.status.label ?? (model.loadFailed ? "状态未知" : "正在读取")
        return NavigationLink(value: platform) {
            HStack(spacing: 12) {
                PlatformIcon(platform: platform)
                VStack(alignment: .leading, spacing: 4) {
                    Text(platform.name)
                        .font(.headline)
                        .foregroundStyle(CampusTheme.ink)
                    Text(platform.summary)
                        .font(.footnote)
                        .foregroundStyle(CampusTheme.muted)
                    Text(statusLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CampusTheme.accent)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CampusTheme.muted)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CampusPressStyle())
        .accessibilityLabel(Text("\(platform.name)，\(platform.summary)，\(statusLabel)"))
        .accessibilityIdentifier("accounts.\(platform.rawValue)")
    }
}

struct PlatformDetailView: View {
    let platform: CampusPlatform
    let model: AccountsModel
    @State private var confirmingDisconnect = false
    @State private var disconnecting = false
    @State private var disconnectFailed = false
    @State private var showingAcademicAuthorization = false

    var body: some View {
        let snapshot = model.snapshot(for: platform)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    PlatformIcon(platform: platform)
                    Text(platform.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(CampusTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let snapshot {
                        Text(snapshot.status.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CampusTheme.accent)
                    }
                }
                if let snapshot {
                    connectionPanel(snapshot)
                    if platform == .academic, let bindingID = snapshot.bindingID {
                        academicServices(bindingID: bindingID)
                    } else {
                        services
                    }
                } else if model.loadFailed {
                    Button("重新读取账号状态") { Task { await model.reload() } }
                        .buttonStyle(.bordered)
                } else {
                    ProgressView("正在读取账号状态")
                        .tint(CampusTheme.accent)
                }
            }
            .padding(.vertical, 16)
            .campusColumn()
        }
        .background(CampusTheme.background.ignoresSafeArea())
        .navigationTitle(platform.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert("解绑\(platform.name)？", isPresented: $confirmingDisconnect) {
            Button("解绑并清理本机数据", role: .destructive) {
                Task {
                    disconnecting = true
                    defer { disconnecting = false }
                    disconnectFailed = !(await model.disconnect(platform))
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除该平台的本机会话、凭据和缓存。其他校园平台可继续使用。")
        }
        .sheet(isPresented: $showingAcademicAuthorization) {
            AcademicAuthorizationView(model: model)
        }
    }

    private func academicServices(bindingID: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([AcademicEndpoint.schedule, .grades, .exams, .plan], id: \.self) { endpoint in
                if endpoint != .schedule { Divider().overlay(CampusTheme.line) }
                NavigationLink {
                    BoundAcademicDataView(endpoint: endpoint, bindingID: bindingID, model: model)
                } label: {
                    HStack {
                        Text(endpoint.title)
                            .foregroundStyle(CampusTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(CampusTheme.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CampusPressStyle())
                .accessibilityIdentifier("academic.service.\(endpoint)")
            }
        }
        .padding(.horizontal, 16)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("计划接入的服务")
                .font(.headline)
                .foregroundStyle(CampusTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            ForEach(platform.services, id: \.self) { service in
                Divider().overlay(CampusTheme.line)
                Text(service)
                    .font(.body)
                    .foregroundStyle(CampusTheme.ink)
                    .padding(.vertical, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CampusTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func connectionPanel(_ snapshot: ConnectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if platform == .academic && snapshot.canConnect {
                Button("绑定教务账号") { showingAcademicAuthorization = true }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("academic.bind")
            } else if platform == .academic && [.expired, .actionRequired].contains(snapshot.status) {
                Text("教务会话需要重新授权。可查看已缓存的数据，重新绑定前请先解绑当前账号。")
                    .font(.subheadline)
                    .foregroundStyle(CampusTheme.muted)
            }
            if snapshot.canDisconnect {
                Button(snapshot.status == .cleanupRequired ? "继续清理" : "解绑账号", role: .destructive) {
                    confirmingDisconnect = true
                }
                .buttonStyle(.bordered)
                .disabled(disconnecting)
            }
            if disconnecting {
                ProgressView("正在清理本机数据")
            } else if disconnectFailed {
                Text("清理未完成，请重试。")
                    .font(.subheadline)
                    .foregroundStyle(CampusTheme.ink)
            } else if !snapshot.canConnect && snapshot.status == .unbound {
                Text("当前版本暂未开放绑定")
                    .font(.headline)
                    .foregroundStyle(CampusTheme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BoundAcademicDataView: View {
    let endpoint: AcademicEndpoint
    let bindingID: String
    let model: AccountsModel

    var body: some View {
        if model.snapshot(for: .academic)?.bindingID == bindingID {
            AcademicDataView(endpoint: endpoint) { endpoint, fields in
                try await model.academicData(endpoint, fields: fields, bindingID: bindingID)
            }
            .id(bindingID)
        } else {
            ContentUnavailableView("教务账号已解绑", systemImage: "person.crop.circle.badge.minus")
                .navigationTitle(endpoint.title)
        }
    }
}
