# 应刻 iOS 首版界面与连接基础

对应 [Issue #5](https://github.com/zzstar101/yingke/issues/5)。首版用 Swift 和 SwiftUI 实现，最低 iOS 18。打开 [Yingke.xcodeproj](../ios/Yingke.xcodeproj/project.pbxproj)，选择 `Yingke` scheme 和 iPhone 模拟器即可运行。

## 设计参考

| GitHub 项目 | 借鉴与落地 |
| --- | --- |
| [TigerDuck](https://github.com/tigerduck-app/tigerduck-app#screenshots) | 首页优先显示课表和每日信息。应刻的首屏把「今日课表」作为主入口，绑定前明确显示数据来源和所需账号。 |
| [不高山上](https://github.com/The-Brotherhood-of-SCU/Bugaoshan/blob/preview/README.md) | 校园服务集中呈现，学生可以按用途快速寻找入口。应刻按四个来源组织服务，并逐个平台显示连接状态。 |
| [聚在工大](https://github.com/Chiu-xaH/HFUT-Schedule/blob/dev/README.md) | 首页突出常用功能。应刻采用类似的内容优先级，并用系统标签栏、导航返回和 SF Symbols 呈现。 |

### 首版页面

- **首页**。校园名称、今日课表、四个平台入口。配色采用校园绿和暖白，课表使用一张单独生成的校园氛围图。图中建筑为虚构场景。
- **校园账号**。按平台显示可见的状态文字。进入详情可浏览服务范围。已接入的平台独立发起绑定，清除本机数据前需要确认。
- **平台详情**。强智教务提供授权和四项查询入口，其他三项平台显示计划接入的服务。首页和服务说明可离线浏览。

交互沿用系统标签栏、导航推入和返回。主页入口按下时以透明度反馈。系统语义字号可随 Dynamic Type 增大，辅助功能字号下服务网格转为单列。配色随系统明暗外观变化。

## 本地连接边界

强智教务使用隔离的 WebKit 官方登录页，学生在网页上输入独立教务账号、密码和验证码。完成网页登录后，点击「完成绑定」，客户端激活会话并验证课表入口。会话默认只保留在内存中，勾选「在本机保留登录会话」后才将 Cookie 写入 Keychain。

课表支持学期和教学周筛选，成绩支持按学期查询。考试安排和培养方案采用保守解析，真实考试明细和培养方案完整字段仍待实测。网络失败、页面结构变化或会话失效时，仅回退到同一绑定、同一筛选条件上次成功的缓存，并显示同步时间。解绑清理选中平台的会话和缓存。会话失效后可以继续查看已缓存结果，重新授权时需先清理旧绑定。应用内真实账号的端到端流程尚待本人验证。接口细节见 [强智教务研究](research/qz-academic.md)。

## 本地验证

```bash
swift test --package-path ios/CampusCore
xcodebuild -project ios/Yingke.xcodeproj -scheme Yingke \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -parallel-testing-enabled NO test
```

用 `xcrun simctl list devices available` 查询已安装的 iOS 18 或更新版本模拟器，把 `<simulator-udid>` 替换成设备 ID。核心测试使用模拟 Provider 和合成数据。UI 测试使用本地合成授权页和模拟账号，验证免登录启动、筛选与缓存提示、解绑确认和跨标签页的数据清理。
