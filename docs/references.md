# 开源校园客户端与架构参考

> 这些仓库用于学习产品覆盖面、账号与会话管理、原生体验等，不代表协议、接口或学校登录流程可以直接移植。依赖使用和引用应遵守各仓库许可证。

## 产品和功能参考

| 项目 | 仓库 | 参考方向 |
| --- | --- | --- |
| 聚在工大 HFUT-Schedule | https://github.com/Chiu-xaH/HFUT-Schedule | 校园多业务服务、教务与校园网模块、原生 Android 体验 |
| 不高山上 Bugaoshan | https://github.com/The-Brotherhood-of-SCU/Bugaoshan | 统一认证与子系统认证分层、依赖、并发续期、故障隔离 |
| 岱宗盒子 | https://github.com/yeliqin666/xjtu-toolbox-android | 多学生身份管理、独立会话命名空间、站点连接器、Android Compose |
| 交大自由行 BJTUselfService | https://github.com/JasonZhang1225/BJTUselfService-KMP-Refreshed | CAS/MIS 登录状态机、多平台安全凭据存储、作业聚合 |
| TigerDuck | https://github.com/tigerduck-app/tigerduck-app | iOS SwiftUI、Keychain、SSO/Moodle/图书馆独立凭据、账号数据生命周期 |
| TigerDuck Android | https://github.com/tigerduck-app/tigerduck-app-android | 独立 Kotlin/Compose 原生版本的组织思路 |
| 青蟹 SUSE-OAA | https://github.com/suse-edu-cn/SUSE-OAA-APP | 课程、教务与社团信息聚合 |
| TUM Campus | https://github.com/TUM-Dev/campus_flutter | 综合校园应用的信息架构 |

## 最值得读的具体内容

- Bugaoshan 认证设计：https://github.com/The-Brotherhood-of-SCU/Bugaoshan/blob/preview/docs/architecture/authentication.md
- 岱宗盒子 AccountManager：https://github.com/yeliqin666/xjtu-toolbox-android/blob/main/app/src/main/java/com/xjtu/toolbox/account/AccountManager.kt
- 岱宗盒子 SessionManager：https://github.com/yeliqin666/xjtu-toolbox-android/blob/main/shared/data/src/commonMain/kotlin/com/xjtu/toolbox/auth/SessionManager.kt
- TigerDuck 账号状态清理清单：https://github.com/tigerduck-app/tigerduck-app/blob/main/docs/account-state.md
- TigerDuck Swift AuthService：https://github.com/tigerduck-app/tigerduck-app/blob/main/swift/TigerDuck/Services/Auth/AuthService.swift
- BJTU 登录协议迁移记录：https://github.com/JasonZhang1225/BJTUselfService-KMP-Refreshed/blob/main/docs/archive/migration/m3-login-protocol.md

## 对应的架构经验

1. **跨多个学生身份切换**与**一个学生绑定多个服务**不是一回事。应刻第一阶段只要求后者。
2. 如果有 SSO：根会话与子系统会话分离；如果没有：多个 Provider 账号各自独立。
3. 安全存储应该有显式的清理策略，而不只是一句“使用 Keychain”。
4. 会话刷新必须合并并发请求，避免重复登录；登出时要处理尚未完成的异步任务。
5. 不应复制别校针对特定 Cookie、验证码、WebVPN 或学校域名的假设。
6. **参考项目存在历史安全问题**；尤其不要照搬关闭 TLS 校验、明文存密码或随意重定向携带敏感头的实现。
