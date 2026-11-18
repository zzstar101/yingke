# 客户端与认证架构草案

> iOS 已实现原生界面与本地连接基础，详见 [iOS 首版说明](ios-foundation.md)。真实平台接入和 Android 客户端按本文方向继续推进。

## 总体原则

- 不设计应刻自有身份体系。第一阶段仅维护本机上的多个**外部校园服务连接**。
- 四套独立账号：学习通、教务、统一身份认证、到梦空间。即使学号相同，也不能默认密码相同。
- 每个平台可独立连接、恢复会话、同步、断开；一个模块认证失败不影响其他模块。
- 不强行把所有服务归入“统一认证根会话”；只有实际证实存在 SSO 依赖时，才显式声明依赖。
- 当某平台下的多个业务模块共用同一账号，但会话关系未知时，先用一个 Provider 组织业务，具体站点会话分别管理。

## 建议职责边界

| 组件 | 职责 |
| --- | --- |
| ConnectionRegistry | 记录已添加的平台连接、连接状态、最近同步时间，不存储密钥正文 |
| CredentialVault | 通过 iOS Keychain 存储用户明确选择保存的凭据、Token、敏感会话材料 |
| SessionCoordinator | 协调登录、会话探活、失效、必要时重新授权；合并并发刷新 |
| Provider Adapter | 每个平台独立实现认证协议、网络客户端、会话作用域与业务能力 |
| Data Repository | 把平台 HTML/JSON 归一化为课程、成绩、考试、活动等领域模型 |
| Local Cache | 原生持久化缓存；以平台标识和远程账号标识隔离 |
| Feature UI | SwiftUI 消费领域模型和状态，不直接拼接 Cookie、处理验证码或解析 HTML |

接口可采用独立动作：connect、probe、refresh、disconnect、fetch。**不同学校平台的认证流程不必强行抽象为一套相同参数**；支持验证码、网页登录、OAuth 等不同交互挑战。

## 会话状态

建议区分：
- unbound：未绑定
- authenticating：正在认证
- connected：认证有效
- expired：凭据或会话确实失效
- actionRequired：需要验证码、MFA 或用户重新授权
- temporarilyUnavailable：网络/学校服务异常，不能误报密码错误

恢复策略：优先复用有效会话；明确识别认证过期才进行认证恢复；避免在普通业务失败、限流或网关错误时反复登录。自动恢复失败后等待用户操作。

## 生命周期和隔离

- 各服务使用独立 CookieJar/URLSessionConfiguration 或可证明安全的隔离机制。
- Cookie 依域名/路径处理；不得把教务 Cookie 转发给学习通、统一认证或其他站点。
- 同一平台若支持多个学生身份，后续必须有独立命名空间；首版**不预设多学生切换是必需功能**。
- 断开连接时应清理对应服务的凭据、敏感网页状态和内存会话，明确缓存保留/删除策略。
- 认证状态更新使用串行协调器与 generation/epoch，防止登出后旧异步请求写回新的会话。
- WebKit 的 CookieStore 与 URLSession 不自动等价。使用 WKWebView、ASWebAuthenticationSession 时须明确可获得的会话结果，不假定系统浏览器 Cookie 可读取。
- 登录凭据与 Cookie 不进 UserDefaults、普通日志、分析事件或代码仓库。

## 本地数据

初期适配 SwiftData 或 SQLite：先定义数据模型与迁移策略，再确定具体持久化技术。课表、成绩和活动数据都记录来源系统、远程账号、同步时间和缓存新鲜度。

离线状态允许查看最近一次成功同步的结果，清楚标注更新时间。敏感个人信息按最小化采集原则处理，不缓存身份证号、家庭地址等无关学籍字段。

## 技术路线

**iOS**：Swift、SwiftUI、URLSession、Security/Keychain、WebKit（仅必要时）、UserNotifications、WidgetKit（后续有需要再做）。

**Android**：Kotlin、Jetpack Compose、OkHttp/Ktor、Android Keystore、Room 等原生组件。

共享的是需求、协议说明、领域字段、错误语义、测试夹具（脱敏）和验收用例，而非强制共享 Swift/Kotlin 源码。

## 关于通知后端的唯一例外

到梦空间新活动“尽可能实时推送”原则上需要**极简服务端 + APNs**，详见 [推送设计及待验证前提](push-notifications.md)。这不代表引入应刻自有账号或上传校园密码。

在活动数据合法获取方式未确认前，不创建一个默认持有用户到梦空间凭据的服务器。

## 工程约束

- 网络层保持系统 TLS 证书校验；禁止全局关闭 ATS、证书验证或域名验证。
- 有状态接口和非幂等操作（报名/签到）不可在不明确结果时盲目自动重试。
- 认证和 HTML 解析使用脱敏 fixture 进行回归测试；真机验收与模拟响应测试分开记录。
- 不照抄其他学校的 CAS 流程；先验证本校四个系统实际登录方式。
