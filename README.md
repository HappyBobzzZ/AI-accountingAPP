# AI 记账

> 说一句话，自动记一笔。完全离线可用，账单只存在你自己的手机里。

一个用自然语言记账的 Android App。不用一层层点分类、填金额、选日期——直接说「昨天买水果花了六块」，它会自己拆出**日期、金额、分类、子分类、备注**，确认一下就能存。

没有账号、没有云端同步、不上传任何数据。断网、飞行模式、在地铁里都能正常记账。

---

## 目录

- [这个 App 解决什么问题](#这个-app-解决什么问题)
- [功能](#功能)
- [界面速览](#界面速览)
- [技术栈](#技术栈)
- [快速开始](#快速开始)
- [打包](#打包)
- [项目结构](#项目结构)
- [核心设计](#核心设计)
  - [1. 双引擎解析：先云端，后本地](#1-双引擎解析先云端后本地)
  - [2. 离线语音识别](#2-离线语音识别)
  - [3. 人声检测：别让模型"幻听"](#3-人声检测别让模型幻听)
  - [4. 金额隐私](#4-金额隐私)
  - [5. 导入去重](#5-导入去重)
  - [6. 设计系统](#6-设计系统)
- [数据模型](#数据模型)
- [与电脑端配合（可选）](#与电脑端配合可选)
- [测试](#测试)
- [常见问题](#常见问题)
- [已知限制](#已知限制)
- [版本记录](#版本记录)
- [第三方资源](#第三方资源)

---

## 这个 App 解决什么问题

传统记账 App 记一笔要 5~8 次点击：打开 → 新增 → 选类型 → 选分类 → 选子分类 → 输金额 → 选日期 → 保存。坚持不了三天。

这个 App 把这一步压成**一句话**：

| 你说的话 | 解析结果 |
| --- | --- |
| `今天中午吃黄焖鸡花了25元` | 支出 / 餐饮 / 三餐 / ¥25.00 / 今天 / 备注「黄焖鸡」 |
| `昨天买水果花了六块` | 支出 / 餐饮 / 水果 / ¥6.00 / 昨天 / 备注「水果」 |
| `上周五打车32` | 支出 / 交通 / 打车 / ¥32.00 / 上周五 |
| `这个月工资到账8000` | 收入 / 薪资 / 工资 / ¥8000.00 / 本月 |

解析结果会先弹出来给你核对，**确认之前不会入库**，识别错了直接改。

---

## 功能

| 分类 | 功能 |
| --- | --- |
| **记账** | 一句话自然语言记账 · 手动表单记账 · 语音输入（长按说话） |
| **语音** | 端侧离线识别（不联网、不上传录音）· 系统识别兜底 · 录音实时音量条 |
| **账单** | 月度汇总 · 按日分组 · 当日小计 · 点按编辑 · 左滑删除 · 月份快选 |
| **统计** | 年度总览 · 月度收支条形图 · 支出分类占比排行 |
| **数据** | CSV 导出备份（走系统分享面板）· 从电脑增量导入历史账单 |
| **隐私** | 汇总金额默认遮罩 · 眼睛按钮临时显示 · 数据只存本机数据库 |
| **外观** | 浅色 / 深色双主题 · 跟随系统 · 统一设计 token |

金额颜色遵循中国习惯：**支出红色、收入绿色**。

---

## 界面速览

底部四个标签：

```
┌─────────┬─────────┬─────────┬─────────┐
│  记账   │  账单   │  统计   │  设置   │
└─────────┴─────────┴─────────┴─────────┘
```

- **记账**：本月概览卡（金额默认遮住，点眼睛显示，整卡可点进账单）→ 一句话输入卡 → 「长按说话」「手动填写」两个入口 → 最近记账
- **账单**：白卡三列汇总（支出 / 收入 / 结余）→ 可点的月份胶囊（弹 12 个月网格）→ 按日期分组的账单列表
- **统计**：年度总览 → 月度收支条形图（带图例）→ 支出分类占比
- **设置**：导入 / 导出 / 离线语音模型管理 / 隐私开关 / 解析引擎状态 / 版本

---

## 技术栈

| 层 | 选型 | 说明 |
| --- | --- | --- |
| 框架 | Flutter 3.44 / Dart 3.12 | Material 3，无状态管理库（纯 `setState`） |
| 存储 | `sqflite` | 单表 `bills`，DB version 2 |
| 语音识别 | `sherpa_onnx` + `record` | 端侧 Paraformer 中文 small int8 |
| 语音兜底 | `speech_to_text` | 走系统 RecognitionService |
| 导出 | `share_plus` | 写临时文件后调系统分享面板，免存储权限 |
| 网络 | `http` | 只用于可选电脑后端 |
| 权限 | `permission_handler` | 仅麦克风 |

---

## 快速开始

### 环境要求

- Flutter SDK ≥ 3.24（开发时使用 3.44.6）
- Android SDK，`compileSdk 36` / `minSdk 24`
- 真机或模拟器（语音功能需要真机麦克风）

### 运行

```bash
git clone <repo-url>
cd ai_accounting
flutter pub get
flutter run
```

### 只想要安装包

```bash
flutter build apk --release --target-platform android-arm64
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`，约 44 MB。

---

## 打包

这个项目有几个必须注意的打包细节，改之前请先读：

### 1. 只打 arm64

```bash
flutter build apk --release --target-platform android-arm64
```

不打这个参数的话体积会翻三倍以上。

### 2. 必须排除第三方 AAR 的其它 ABI

`onnxruntime`（`sherpa_onnx` 的依赖）的 AAR 里自带 x86 / x86_64 / armeabi-v7a 三套 `.so`，
`ndk.abiFilters` **管不住它们**，必须在 `android/app/build.gradle.kts` 里显式排除：

```kotlin
packaging {
    jniLibs {
        excludes += listOf("lib/x86/**", "lib/x86_64/**", "lib/armeabi-v7a/**")
    }
}
```

不做这一步，APK 会从 44 MB 涨到 92 MB。

### 3. 每次发版必须递增 versionCode

`pubspec.yaml` 里的 `version: 1.4.1+2009`，`+` 后面是 `versionCode`。
**不递增就无法覆盖安装**（系统会报"已安装更高版本"）。

### 4. 签名

`release` 构建目前复用 debug 签名（见 `android/app/build.gradle.kts`），
个人自用没问题；要上架或分发请换成正式 keystore，否则换机器打包会签名冲突。

---

## 项目结构

```
lib/
├── main.dart                     入口：主题、本地化、启动 MainShell
├── config.dart                   全局配置（电脑后端地址，可用 --dart-define 覆盖）
├── models/
│   └── bill.dart                 账单模型 + 分类/子分类常量 + 内容指纹
├── theme/
│   ├── app_theme.dart            设计 token：颜色/圆角/间距 + 浅深两套 ThemeData
│   └── category_style.dart       分类图标与配色 + CategoryPicker
├── pages/
│   ├── main_shell.dart           底部四标签容器
│   ├── home_page.dart            记账首页（输入 / 语音 / 概览 / 录音）
│   ├── bill_list_page.dart       账单列表（汇总 / 分组 / 编辑 / 删除 / 月份选择）
│   ├── annual_summary_page.dart  统计（年度 / 月度 / 分类占比）
│   ├── manual_entry_page.dart    手动记账
│   └── settings_page.dart        设置
├── widgets/
│   ├── app_widgets.dart          通用组件：卡片/空状态/账单行/金额/月份选择
│   ├── bill_form.dart            账单表单（手动页与确认弹窗共用）
│   └── bill_edit_sheet.dart      确认/编辑弹窗外壳
└── services/
    ├── api_service.dart          解析请求：云端优先，失败降级本地
    ├── local_parser_service.dart 本地正则解析引擎
    ├── bill_keywords.dart        关键词 / 正则词表
    ├── offline_asr_service.dart  离线识别（sherpa_onnx）
    ├── asr_model.dart            语音模型清单、下载、校验
    ├── asr_model_controller.dart 模型状态（下载进度 / 是否就绪）
    ├── voice_activity.dart       人声检测（WAV 能量分析）
    ├── haptics.dart              触感反馈（原生 Vibrator 通道）
    ├── database_service.dart     SQLite 单例
    ├── bill_csv.dart             CSV 生成（纯函数）
    ├── export_service.dart       分享导出
    ├── bill_import.dart          导入去重（纯函数）
    ├── data_ops.dart             导入 / 导出完整流程
    ├── app_events.dart           页面间数据变更广播
    ├── privacy_controller.dart   金额隐私开关
    ├── prefs.dart                本地偏好存储（JSON 文件）
    └── error_reporter.dart       异常上报（可选，需电脑端）

test/
├── local_parser_test.dart        解析用例（与电脑端用例表镜像）
├── bill_import_test.dart         指纹与去重
├── bill_csv_test.dart            CSV 格式
├── voice_activity_test.dart      人声检测判据
├── money_format_test.dart        金额格式化与遮罩
├── privacy_test.dart             隐私开关与卡片交互
├── ui_layout_test.dart           手机尺寸下全页面布局回归
└── widget_test.dart              主界面渲染
```

---

## 核心设计

### 1. 双引擎解析：先云端，后本地

```
用户输入
   │
   ├─→ POST {backendUrl}/api/extract   (3 秒超时)
   │        │
   │        ├─ 成功 → 用云端结果（NLP 更准）
   │        │
   │        └─ 失败 / 超时 / 不可达
   │                 ↓
   └──────────→ LocalParserService（纯正则，完全离线）
```

关键点：**后端不是必需的**。没有电脑、没连 WiFi 时，本地引擎能覆盖绝大多数日常说法。
界面上会提示这次用的是哪个引擎。

本地解析的金额识别顺序（踩过很多坑才定下来）：

```
中文数字+块/元 → 纯中文数字 → 数字+元/块 → ¥ 前缀
→ 动词+了+数字 → 裸动词+数字 → 块钱 → 兜底任意数字
```

日期词会**先剥离**再找金额，否则「16号」会被当成 16 元。

语音识别常见的同音错误也在这一层纠：`六款 → 六块`、`十五圆 → 十五元`、
`初一 → 周一`、`水果花六块 → 水果花了六块`。

### 2. 离线语音识别

```
长按麦克风
   ↓
record 录 16kHz 单声道 WAV
   ↓
人声检测（见下一节）── 没人声 → 提示重说，不调模型
   ↓
sherpa_onnx OfflineRecognizer（Paraformer 中文 small int8）
   ↓
文字回填输入框（不自动弹账单，先让你核对）
```

**模型不入包**：首次长按会引导下载 82 MB 的模型到应用私有目录，
之后完全离线。选 Paraformer small 而不是 SenseVoice，是因为体积只有后者
（237 MB）的三分之一，中文短句识别质量够用。

下载走 `hf-mirror.com` 优先、`huggingface.co` 兜底，逐文件校验字节数，
支持断点重试。

录音交互有两个细节：**按下即开录**（不等 350 ms 长按判定，否则开头一两个字会被吃掉），
以及识别器**在录音期间预热**（首次创建要 1~2 秒，正好和说话时间重叠）。

### 3. 人声检测：别让模型"幻听"

端到端语音模型在**纯静音或环境噪声**上不会返回空串，而是"脑补"出一段
莫名其妙的话。所以送进模型之前先做一次能量检测（`voice_activity.dart`）：

自己解析 WAV 头（兼容边录边写时 `data` 大小写成 0 或 `0xFFFFFFFF` 的情况），
按 25 ms 逐帧算 RMS → dBFS，三条判据：

| 判据 | 阈值 | 拦的是什么 |
| --- | --- | --- |
| 时长 | ≥ 0.25 s | 按一下就松手 |
| 峰值 | > −45 dBFS | 绝对静音 |
| 有声帧占比 | ≥ 4% | 被系统 AGC 放大过的恒定底噪 |

第三条是相对判据，阈值取 `max(噪声底 20% 分位 + 8 dB, −50 dB)`。
它专门对付"能量看着不低、但帧之间毫无起伏"的情况——那不是人声。

判为没人声就直接提示「没听到人声，长按麦克风再说一次」，**不浪费一次推理**。

### 4. 金额隐私

首页一打开就是本月支出的大数字，旁边有人瞄一眼就全看见了。

- 汇总金额**默认遮罩**为 `¥ ••••`
- 遮罩是**固定长度**的，不随位数变化——否则位数本身就泄露了"花了几千还是几万"
- 点概览卡上的眼睛可临时显示，选择会记住
- 只遮**汇总数字**（首页概览 / 账单汇总 / 统计总览），明细金额始终显示，
  否则列表就没法看了

### 5. 导入去重

导入历史账单时按**内容指纹**逐条比对，可反复导入而不产生重复：

```dart
String get fingerprint =>
    '$date|$type|$category|$subcategory|${amount.toStringAsFixed(2)}|$remark';
```

指纹**不含** `id` 和 `createdAt`——这两个在不同设备上必然不同。
新增字段时要记得同步进指纹。

### 6. 设计系统

所有颜色、圆角、间距只从 `lib/theme/app_theme.dart` 取，页面里不写
`Colors.blue.shade200` 这类硬编码（否则深色模式会崩、换配色要改几十处）。

- 语义色走 `context.palette`（`AppPalette` 主题扩展）
- 金额统一用 `moneyStyle()`，带 `tabularFigures`，多行金额小数点能对齐
- 分类图标不用 emoji，用 Material 线性图标 + 每类低饱和底色
  （emoji 在不同 ROM 上字形、基线都不一样）

---

## 数据模型

单表 `bills`，DB version 2：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK | 自增 |
| `type` | TEXT | `支出` / `收入` |
| `category` | TEXT | 8 个支出分类 + `薪资` / `其他` |
| `subcategory` | TEXT | 可为空 |
| `amount` | REAL | 正数，方向由 `type` 决定 |
| `date` | TEXT | `YYYY-MM-DD` |
| `remark` | TEXT | 可为空 |
| `created_at` | TEXT | ISO8601 |

分类与子分类：

| 分类 | 子分类 |
| --- | --- |
| 餐饮 | 三餐 / 水果 / 零食 / 饮料 / 酒水 / 买菜 |
| 交通 | 打车 / 公交 / 地铁 / 火车高铁 / 加油 / 停车 |
| 购物 | 服装 / 数码 / 洗护用品 / 美妆护肤 / 日用 / 理发 |
| 娱乐 | 电影 / 聚会 / 会员 / 游戏 / 旅游 |
| 居住 | 房租 / 水电燃气 / 宽带通信 / 物业 |
| 人情 | 红包 / 礼物 / 孝敬长辈 / 生日 |
| 医疗 | 药品 / 门诊 / 体检 |
| 薪资 | 工资 / 奖金 / 福利 / 兼职 |

数据库位置（应用私有目录，卸载即清除）：

```
/data/data/com.example.ai_accounting/databases/ai_accounting.db
```

### 导出的 CSV

UTF-8 带 BOM（Excel / WPS 直接双击不乱码），列为：

```
日期,类型,分类,子分类,金额,备注,创建时间
```

---

## 与电脑端配合（可选）

App 可以完全独立运行。如果想让解析更准、或把电脑上的历史账单导进来，
可以在电脑上跑一个同局域网的 HTTP 后端：

| 接口 | 用途 |
| --- | --- |
| `GET /api/health` | 探测后端是否可用 |
| `POST /api/extract` | 解析一句话，返回账单 JSON |
| `GET /api/import/csv` | 拉取历史账单用于导入 |
| `POST /api/log` | 接收手机端异常上报 |

后端地址在 `lib/config.dart` 里改，或者不改代码、编译时覆盖：

```bash
flutter build apk --release --target-platform android-arm64 \
  --dart-define=BACKEND_URL=http://192.168.1.10:8000
```

> 后端实现不在本仓库内。`lib/services/bill_keywords.dart` 里的关键词/正则表
> 与后端共用同一份词表，**改一端要同步另一端**。

---

## 测试

```bash
flutter test
```

共 52 个用例，覆盖：

- 解析用例表（金额 / 日期 / 备注 / 同音字容错 / 分类归属）
- 导入指纹与去重
- CSV 格式与转义
- 人声检测判据（静音、底噪、被放大的噪声、正常说话、小声说话）
- 金额格式化与隐私遮罩
- **布局回归**：在 390×844 下把四个页面和表单都过一遍，`RenderFlex` 溢出会直接让测试失败

> 如果 `flutter test` 报 `Invalid WebSocket upgrade request`，
> 多半是本机代理拦截了 `flutter_tester` 的 localhost 连接，先清掉代理环境变量：
> `HTTP_PROXY= HTTPS_PROXY= flutter test`

---

## 常见问题

**Q：APK 为什么有 44 MB？**
A：主要是 `sherpa_onnx` 依赖的 `onnxruntime` 原生库。语音模型本身不入包（另外下载 82 MB），
否则会到 130 MB 以上。

**Q：为什么要单独下载语音模型？**
A：把 82 MB 塞进安装包，所有人都得为「可能不用语音」付费。现在不用语音的人装 44 MB 就够。

**Q：华为 / HarmonyOS 上语音没反应？**
A：系统识别（兜底方案）依赖设备上的 `RecognitionService`，华为无 GMS，
需要装带识别服务的输入法（如讯飞输入法）。**离线识别不需要**，只要模型下载完成就行。

**Q：覆盖安装会清空账单吗？**
A：不会。同包名 + 同签名 + versionCode 递增时系统走原地升级，数据库文件保留。
但仍然建议定期用「设置 → 导出账单备份」留一份 CSV。

**Q：导出的 CSV 在手机 WPS 里日期显示成 `####`？**
A：那是列宽不够，不是编码问题。在 WPS 里把日期列拉宽即可。

**Q：数据会上传吗？**
A：不会。账单只写本机 SQLite。只有你主动点「从电脑导入」或连接了电脑后端时才有网络请求。

**Q：怎么彻底重置？**
A：卸载重装即可，数据库在应用私有目录，随卸载一起删除。

---

## 已知限制

- 只在 Android（含 HarmonyOS 兼容层）真机上验证过，iOS / 桌面端未测试
- 只有导出，**没有 CSV 导入恢复**（导入依赖电脑后端）
- 单个账本，没有多账本 / 预算 / 定期账单
- 分类固定，暂不支持自定义
- release 使用 debug 签名

### 可能的下一步

- [ ] 本地 CSV 导入恢复（不依赖电脑）
- [ ] 预算与超支提醒
- [ ] 多账本
- [ ] 自定义分类
- [ ] 桌面小组件

---

## 版本记录

| 版本 | 主要变化 |
| --- | --- |
| 1.4.1 | 汇总金额默认遮罩、概览卡可点、统计页恢复收支双数字 |
| 1.4.0 | 界面与信息架构全面重做：底部四标签、设计 token、分类图标换线性图标、表单合一 |
| 1.3.3 | 人声检测拦截静音幻听、原生振动通道修长按无反馈 |
| 1.3.2 | 备注提取修正、识别后不自动弹窗、同音纠错、按下即录 |
| 1.3.1 | 修复长按麦克风无响应（Tooltip 抢走手势） |
| 1.3.0 | 端侧离线语音识别（sherpa_onnx + Paraformer） |
| 1.2.0 | 账单导出备份（CSV + 系统分享） |
| 1.1.0 | 账单编辑、导入增量去重、Git 版本管理 |
| 1.0.0 | 基础记账：一句话解析、分类统计、本地存储 |

---

## 第三方资源

- 语音模型：[sherpa-onnx-paraformer-zh-small-2024-03-09](https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-small-2024-03-09)
- 识别引擎：[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- 图标：Material Symbols（Flutter 内置）

---

## 许可

个人项目，暂未指定开源协议（默认保留所有权利）。如需使用请先联系作者。
