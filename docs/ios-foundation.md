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
- **校园账号**。按平台显示可见的状态文字。进入详情可浏览计划接入的服务。已接入的平台将独立发起绑定，清除本机数据前需要确认。
- **平台详情**。显示服务出处和范围。初始构建中的平台均显示「当前版本暂未开放绑定」。首页和服务说明都可在离线时浏览。

交互沿用系统标签栏、导航推入和返回。主页入口按下时以透明度反馈。系统语义字号可随 Dynamic Type 增大，辅助功能字号下服务网格转为单列。配色随系统明暗外观变化。

## 本地连接边界

首版仅注册平台入口，真实授权由后续各校园 Provider 接入。会话默认仅保存在内存，明确选择保存时才写入本机 Keychain。缓存按平台和单次账号绑定的独立标识隔离。解绑会清理选中平台的凭据、内存会话和账号缓存，清理失败会显示可重试状态。首版连接基础需要先解绑并清理旧绑定，再发起新的授权。后续由接入的 Provider 校验远程账号身份，再决定如何恢复既有绑定。

## 本地验证

```bash
swift test --package-path ios/CampusCore
xcodebuild -project ios/Yingke.xcodeproj -scheme Yingke \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -parallel-testing-enabled NO test
```

用 `xcrun simctl list devices available` 查询已安装的 iOS 18 或更新版本模拟器，把 `<simulator-udid>` 替换成设备 ID。核心测试使用模拟 Provider 和合成数据。UI 测试验证免登录启动、课表入口、校园账号列表和平台说明，并用仅 Debug 可用的模拟账号验证解绑确认、取消和平台隔离。
