# 强智课表解析与 WakeUp 课程表参考

2026-11-18 核对。以下强智格式来自公开适配源码及其测试，适用范围以各校模板为准。

## 强智 HTML 课表

- **节次**。旧版样本包含 `一二`、`九十`、`第十二节`。`十一`表示单节，双节也可用 `第一二节 (01,02小节) 09:00-10:30` 一类标签显式给出，括号内小节优先，后面的钟点只是作息时间。厦门适配器示例是 `15,18-19(周)[03-04节]`，佛山适配器接受 `[03-04]节`。平顶山适配器注明第 11–12 节在中午，学校节次编号与作息顺序需分别保存。[中文节次与小节测试](https://github.com/QiWeiYouWei/zhengfang-apk/blob/67ff5471447dc09dd97c0e8327459a0f73901d70/app/src/test/java/com/tyust/course/academic/QzTimetableCellsTest.kt#L65-L85) · [第十二节测试](https://github.com/QiWeiYouWei/zhengfang-apk/blob/67ff5471447dc09dd97c0e8327459a0f73901d70/app/src/test/java/com/tyust/course/academic/QzTimetableCellsTest.kt#L20-L24) · [厦门适配](https://github.com/imshixin/AiSchedule/blob/1dfad468a5cbbc2ec9c123b81d6b9f5f6f01b4b3/%E5%8E%A6%E9%97%A8%E6%B5%B7%E6%B4%8B%E8%81%8C%E4%B8%9A%E6%8A%80%E6%9C%AF%E5%AD%A6%E9%99%A2-%E5%BC%BA%E6%99%BA.js#L77-L111) · [佛山适配](https://github.com/imshixin/AiSchedule/blob/1dfad468a5cbbc2ec9c123b81d6b9f5f6f01b4b3/%E4%BD%9B%E5%B1%B1%E8%81%8C%E4%B8%9A%E6%8A%80%E6%9C%AF%E5%AD%A6%E9%99%A2-%E5%BC%BA%E6%99%BA.js#L87-L98) · [平顶山适配](https://github.com/imshixin/AiSchedule/blob/1dfad468a5cbbc2ec9c123b81d6b9f5f6f01b4b3/%E5%B9%B3%E9%A1%B6%E5%B1%B1%E5%B7%A5%E4%B8%9A%E8%81%8C%E4%B8%9A%E6%8A%80%E6%9C%AF%E5%AD%A6%E9%99%A2-%E5%BC%BA%E6%99%BA.js#L65-L105)
- **星期与结构行**。公开解析器结合 `th`、`td` 及 `rowspan`、`colspan` 还原逻辑列，从表头识别 `星期一`／`周一`，支持以 `日`、`天` 表示星期日。空白、占位横杠会跳过，有课程块却读不到节次时会报格式变化。厦门适配按位置跳过首尾行，一份小爱适配则由物理行号推节次。广应科分隔行的具体标记及其他模板的表头别名尚未从公开样本核实。建议以显式节次定位课程，分隔行不占节次。用插入的午休或空白行、合并表头及同格多段课程核对后续课程是否偏移。[逻辑网格及结构处理](https://github.com/QiWeiYouWei/zhengfang-apk/blob/67ff5471447dc09dd97c0e8327459a0f73901d70/app/src/main/java/com/tyust/course/academic/AcademicStudyParser.kt#L98-L152) · [厦门行列处理](https://github.com/imshixin/AiSchedule/blob/1dfad468a5cbbc2ec9c123b81d6b9f5f6f01b4b3/%E5%8E%A6%E9%97%A8%E6%B5%B7%E6%B4%8B%E8%81%8C%E4%B8%9A%E6%8A%80%E6%9C%AF%E5%AD%A6%E9%99%A2-%E5%BC%BA%E6%99%BA.js#L15-L26) · [小爱样本行号推节次](https://github.com/ceresOPA/MI_AI_Course_Schedule/blob/b8ec3ee137c0e471806a2e6e1310201e05e64b99/parser.js#L59-L64)
- **许可证**。`QiWeiYouWei/zhengfang-apk` 的根许可证是 GPL v3。抽查 `imshixin/AiSchedule` 与 `ceresOPA/MI_AI_Course_Schedule` 固定版本的根目录及 README，均未找到明确的开源授权。本文仅记录格式事实，解析器和测试样本应自行编写。[GPL v3 原文](https://github.com/QiWeiYouWei/zhengfang-apk/blob/67ff5471447dc09dd97c0e8327459a0f73901d70/LICENSE) · [AiSchedule 仓库快照](https://github.com/imshixin/AiSchedule/tree/1dfad468a5cbbc2ec9c123b81d6b9f5f6f01b4b3) · [MI_AI_Course_Schedule 仓库快照](https://github.com/ceresOPA/MI_AI_Course_Schedule/tree/b8ec3ee137c0e471806a2e6e1310201e05e64b99)

## 广应科页面实测

经用户网页登录后，在「学生课表查询」核对了本校的页面结构。课表以 `th` 表示节次，存在「第一二节」和「第九十十一节」等合并行。最后一行的「备注」右侧为横跨七天的文本单元格。复现用例使用合成课程、教师、地点和备注。

## WakeUp 课程表

- **主动导入**。官方指南提供按学校查找与按教务类型导入，区分新版、旧版强智，也提供 HTML、CSV、分享口令和手动录入。可以新建课表作为导入目标，完成后检查课程是否正确、齐全。[导入课表](https://wakeup.fun/doc/import_schedule.html) · [从教务系统导入](https://wakeup.fun/doc/import_from_eas.html)
- **日常查看与编辑**。主界面默认显示本周，可翻周及切换课表。每张表可独立设置学期起始日和节次时间，每门课可手动编辑多个上课时段。隐私政策第五节说明常规课程数据在手机本地保存，主动在线分享才会上传所分享课表。iOS 历史更新日志曾记录 iCloud 同步，鸿蒙跨设备同步也见隐私政策第二节。公开指南确认的是用户主动发起的教务导入，专门的手动刷新入口、再次导入的合并规则及定时同步教务均未核实。可参考其使用流程，日常直接打开本地课表，导入由用户显式发起并在完成后核对结果。[主界面](https://wakeup.fun/doc/main_interface.html) · [课表设置](https://wakeup.fun/doc/settings/schedule_settings.html) · [添加和编辑](https://wakeup.fun/doc/add_course.html) · [官方隐私政策](https://www.wakeup.fun/policy.html) · [iOS 更新日志](https://wakeup.fun/doc/update/ios.html)
