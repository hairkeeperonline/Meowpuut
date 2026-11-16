# 喵撲 HarmonyOS 版 Android 对齐清单（施工蓝图）

> 对照 `Android/app/src/main/java/.../android/` 逐项对齐（功能 + UI）。
> 状态：`[x]` 已完成，`[ ]` 待办。约定：high 优先、medium 其次、low 收尾。

## 已完成（本轮）

- [x] **设置项跨进程同步修复（round 45，本轮架构基石，真机端到端验证）**：用户反馈设置页改了「色调/色系/视觉特效/键盘高度」等后键盘不变。根因是 **HarmonyOS 沙箱把主进程（SettingsAbility）与 inputMethod 扩展进程完全隔离**——两个进程的 `filesDir` 和 `preferencesDir` 字符串路径完全相同（`/data/storage/el2/base/haps/entry/...`）但互相不可见：主进程写完 XML 并 flush 回读成功（`flush done, xml 113B`），IME 进程读同一路径返回 `No such file or directory`（已真机实证）；SDK 的 `dataGroupId` 共享 preferences 文档标注 RP1 不可用。修复方案 = **commonEventManager 发布订阅**：`Prefs.put()` 每次写入后 `broadcast(key,value)` 发布 `com.krysta1ll.meowpuut.SETTINGS`，data 为 JSON `{key, value, all}`，`all` 是 `snapshotAll()` 从全部 getter（非 mirror——重装后 mirror 为空）构建的 **17 键全量快照**；IME 进程 `onCreate` 里 `subscribe()`，收到后①覆盖内存 mirror ②`persistSnapshot()` 全量写进 IME 自己的 Preferences（冷启动自恢复）③热应用回调（simplified/applyLook/applyPanelPosition/openLexicon 若 mode 变/refreshKeyboard）——**键盘弹着时改动也即时生效**。设置页 `aboutToAppear` 初始化完成后 `publishSnapshot()`（key='*'）作对齐兜底（真机日志：重进设置页即补发 `effects=standard (17 keys)`，悬浮态由此恢复）。冷启动验证：force-stop 后重弹键盘，深色+海盐蓝仍保持。17 键 = mode/simplified/shape/tone/palette/strength/cats/festivals/haptics/sound/keyPopups/hapticStrength/keySound/keySoundVolume/keyboardHeight/effects/keyboardPosition。
- [x] **键盘位置「悬浮」真实现（round 45，Android 0.9.1 对齐，真机全链路验证）**：原实现是空壳（onSelect 注释「悬浮档预留」）。现用系统原生能力：`panel.changeFlag(FLG_FLOATING)` 切悬浮 + `panel.resize(屏宽-48)` 左右各留 24px 边距 + `panel.moveTo(24, 屏高×0.22)` 抬到屏幕中上部 + 面板顶部 **32px 拖动把手**（PanGesture 每 24px 增量调 `panel.moveTo`，clamp 在屏内）。两个关键坑：① `setPanelFlag` 不存在，真 API 名是 `panel.changeFlag(flag)`（同步方法）；② 把手显隐如果走普通类字段（`host.draggable`）**非响应式不刷新**——`setUiContent` 时是 false，后续改 true 面板不重渲染；必须走 `AppStorage.setOrCreate('meowpuutDraggable', floating)` + KeyboardPage `@StorageLink` 双向绑定（注意 `draggable` 是组件内置属性名会编译冲突，改名 `floatDraggable`）。真机验证：悬浮态面板 1272px 宽居中于 (24,466)，下方露出笔记内容（「共 41 字」可见、不推挤应用布局）；拖动把手 (24,466)→(332,774) 像素实测键盘左上角随之移动（y1000 行左边界 24→332）；切回「贴底」`panel fixed (bottom)` 恢复全宽 1320 贴底。把手初始 `#B0FFFFFF` 在白底笔记上不可见，改 `#8C787880` 半透明深灰后真机可见（y507 采样 (176,175,180)）。
- [x] **键盘高度三档真机量化（round 45）**：较矮/标准/较高 → 面板顶 y=980/919/835 px（1320×2120 屏，注音 5 行）。实现链路 `prefs.keyboardHeight` → `Look.heightScale`(0.88/1.0/1.12) → `resizePanel` 的 `scaledKeys` 与键盘绘制同步缩放。三档切换广播 `keyboardHeight=tall/short` 均真机收到并重算面板。
- [x] **六套色系逐一像素级验证（round 45，暗色基调）**：候选药丸+玻璃染色按色系变化，真机逐套切换并像素分类——玫瑰奶茶 rose 15395 红系像素、海盐蓝 ocean 13917 蓝系、鼠尾草绿 sage 8723 绿系（关猫后干净）、雾紫 lavender 4959 紫系（高R高B）、琥珀蜜 amber 红橙族 G-B=16.2（G-B>12 像素 12015，与 rose 纯红族 G-B≈0-5 明确区分）、石墨 graphite 彩色像素骤降至 2894（对比 rose 16876，去色即设计意图）。测量法：暗色下候选玻璃的 caustic 用 `paletteColor` 染色（rose #FFE69687 / ocean #FF70BAF0 / sage #FF9CC7A1 / lavender #FFC2A8F0 / amber #FFF0BF6B / graphite #FFC2CCD9），对候选栏区做色相分类计数；猫装饰会干扰，验证时先关猫（`cats=false`）。
- [x] **造型三档真机验证（round 45）**：胶囊=平直圆角上边缘、波浪=明显 S 形起伏、云朵=圆弧鼓包——三张候选玻璃截图拼接后视觉逐档确认，`GlassOutline` 的 waveOffset 正弦 + CLOUD_BUMPS 数学全部生效。
- [x] **玻璃强度三档真机验证（round 45）**：柔和/标准/通透 = glassFill alpha 0.74/0.62/0.50（暗色底 0x3A302C）。候选玻璃中上带（y1155-1210）平均色单调变化 (94.4,88.8,87.6)→(96.8,92.8,92.0)→(98.1,95.8,96.4)——alpha 越低透出越多下层 caustics 虹彩。暗底上差异细腻属设计内（对应 Android 同参数）；测量要点：候选玻璃真身在 zhuyin 面板 y1150-1290，别量到笔记区。
- [x] **视觉特效三档差异化验证（round 45）**：轻量=动效时长归零（lean 140ms，组字区即时渲染已截图验证）；极致=glassFill alpha ×0.82（0.62×0.82≈0.51），真机实测极致档玻璃带 (98.1,95.8,96.4) 与通透档 0.50 的测量值**逐位精确一致**——数学交叉验证成立；标准=默认。设置页 3 档 Slider。
- [x] **设置页 valueText 不刷新修复（round 45）**：真机发现视觉特效拖到 0 后 valueText 仍显示「标准」。根因：`@Builder` 函数参数按值传递**不响应 @State 变化**（rowSlider/rowSelect 共性问题；Select 因组件内部 selected 属性恰幸免）。修复：视觉特效行内联展开，Text 直接绑定 `this.effects` 三元表达式，真机实测档位变化即时显示「轻量/极致」。
- [x] **米米莫与莫莫（cats）开关双向验证（round 45）**：`cats=false` 广播后猫装饰像素消失（sage 测量中 rose 噪声 2712→253）；`cats=true` 恢复后候选栏右侧双猫可见（黑猫黄眼趴姿 + 暹罗坐姿，视觉确认）。
- [x] **按键气泡（keyPopups）开关双向验证（round 45）**：用 `uinput -T -d/-u`（触屏按下/抬起分离）保持按住 ㄋ 时截图——开：按住键上方出现放大气泡预览（放大 ㄋ 字符 + 指向原键的小尾巴，iOS 样式）；关：同位置无任何气泡。`showBalloon` 前有 `keyPopupsEnabled()` 闸门。
- [x] **振动（haptics）开关 + 强度分档系统日志验证（round 45）**：不再只看自家代码——读系统 `MiscdeviceService` 日志：强档按键 `PlayPrimitiveEffect ... effect:haptic.effect.sharp, intensity:100`；轻档 `haptic.effect.soft, intensity:40`；关闭后按键 **0 条**振动调用。`vibrator.isSupportEffectSync` 不支持时回退 `vibrate(ms)`。振动与音效独立（关震动不影响按键声）。
- [x] **按键声 8 档验证（round 45）**：选项 关闭/系统/水滴/木琴/玻璃/毛毡/五声/泛音（对齐 Android key-sounds 资源目录 felt/glass/harmonic/marimba/penta/water），SoundPool 播 WAV + 每类多变体随机（key 4/delete 3/space 3/return 1/pick 3；五声用 key0-5 九键音色）。真机选「水滴」：`keySound=water` 广播 + IME 进程 AudioStream `Stop end streamID=1` + `audio_server HpaeRendererManager mixerNode trigger callback` ——音频管线真实发声。音效音量为 100% 禁用占位（对齐 Android disabled SeekBar）。
- [x] **色调三档验证（round 45）**：深色键盘底 (91,90,96)、浅色 (252,252,254)、跟随系统读 `configuration.colorMode`。切换广播 `tone=dark` 热应用即时生效。
- [x] **节日装扮接线复核（round 45）**：`applyLook` 里 `festivalWardrobe.on = prefs.festivals`，`Festivals.theme(Festivals.today(), ...)` 今日无节日时返回 null 不换装——开关语义正确（节日期间才生效），非节日季无可视差异属预期。
- [x] **Emoji 表情面板（round 33，鸿蒙增强功能，真机验证）**：安卓 0.9.1 与鸿蒙旧版都没有 emoji 面板，用户点名「emoji 还没做适配」。实现：符号页 2 的切换键「#+=」改为「☺」入口，新增 page 3~6 四个 emoji 分类页（笑脸/手势/动物自然/食物，每页 3 行×10 个，共 ~110 个常用 emoji），emoji 页内同一颗键显示当前分类名并循环切换（3→4→5→6→3），点击 emoji 直接上屏、停留在 emoji 页（对齐 iOS/系统键盘惯例）。**关键坑**：`stringToCharArray` 原来用 `charAt` 逐位切，emoji 代理对被撕成烂字符导致键帽全空白；ArkTS 里 `Array.from(string)` 的码点迭代语义也不可靠——已手写「高代理+低代理合并」的码点切分。Canvas `fillText` 对彩色 emoji 渲染完好（28vp 字号下 measureText 宽度正常）。真机验证：网格渲染✓、点击上屏✓（😉🤩 进入笔记正文）、分类切换✓（笑脸→手势）。
- [x] **摸猫触控命中顺序对齐 Android（round 33，真机验证）**：鸿蒙原顺序「箭头→候选行→猫」导致猫身体（玻璃内部分）全被候选行拦截、点不到猫。已改为 Android `CandidateBarView.onTouchEvent` 的顺序「**猫优先**（touch 框命中且不让位箭头区/候选胶囊区）→ 箭头 → 候选行」。真机验证：点黑猫 → `barTouch → ability.onPet → pet()` 全链路日志通、金色爪印粒子喷出；连摸暹罗 5 下 → 简繁切换 toast「换为繁体中文」正常弹出。
- [x] **双猫聚拢候选栏右端 + Canvas drawImage 单位修复（round 33，真机像素级对齐安卓 0.9.1）**：
  - **布局**：废弃旧「黑猫左端 + 暹罗右端」两端布局，改为 0.9.1 的「双猫聚拢右端」——黑猫（lounge 趴）中心 ≈76.9% 屏宽、暹罗（rest 坐）中心 ≈90% 屏宽（安卓基准 830px/972px@1080px），两猫爪基线贴玻璃上沿（含圆弧抬升 rise），可见高一致（FILL=0.80）。`CatSeats.ends()` 重写为锚点式落座（不再要求不遮候选——0.9.1 双猫本来就压在候选行右端尾部），`fallback()` 同步为 90%/76.9% 中心定位；删除了旧的 `seat()` 滑动搜索（lounge 太宽导致落座必失败）。真机实测：黑猫中心 75.5%（基准 76.9%）、暹罗 90.2%（基准 90.0%）、黑猫 164px 宽（基准换算 159px）、爪底 1148px=玻璃顶 1151px，全部达标。
  - **Canvas drawImage 单位（关键坑）**：真机（API 26 / Pura X / density 3.0）实测 `CanvasRenderingContext2D.drawImage` 的 **dest.x/y 按 vp 坐标解释、dest.w/h 却按物理像素 1:1 解释**（与路径/文字的 vp 语义不一致）。修复：`drawCatImage()`/`drawFestivalEnd()` 只对 **宽高乘 pxRatio()**（densityDPI/160），左上角保持 vp 原值——乘错位置会让猫飞出画布（只残留 vp 单位的爪影椭圆），不乘宽高则猫只有 1/3 大小。
  - **几何**：`CAT_HEADROOM_RATIO` 0.52→0（候选栏高=regionHeight，猫不再被额外头顶留白顶高；真机日志 region=393x82 验证 height=round(82×1.0)）；`kbWidth` 初始 393、`onAreaChange` 后为真实屏宽（440），两套 region 高度 82/92 均按各自 s 计算自洽。
  - **重装后恢复流程**（自动化已验证）：uninstall+install 后系统会把默认输入法切回小艺，需 `aa start -a SettingsAbility -b com.krysta1ll.meowpuut.ohos` → 点「打开键盘设置」(660,763) → 默认输入法下拉 (1188,530) → 选「喵扑」(690,856) → hidumper 确认 isCurrentIme=true。
- [x] UTF-8 解码乱码：`Lexicons.bytesToString` 与 `MeowpuutAbility.bytesToString` 原为逐字节 Latin-1，日文候选/节日名全部乱码；已改用 `util.TextDecoder.create('utf-8')`。
- [x] Shift / CAPS-LOCK 三态图标：`Glyphs.shift(filled, lock)` 已补（空心=SHIFT、实心=SHIFT_ON、实心+锁杆=CAPS_LOCK），`drawIcon` 已按 `size*1.25` 接入；同时补了 `Glyphs.heart/sparkle/note` 原语。
- [x] 英文句首自动大写 AutoCaps：`updateAutoCaps()` 从占位改为真实现（自判句首），`space/enter/onDelete/doubleSpace` 已调用。
- [x] 双击空格输入句号：`space()` + `doubleSpacePeriod()`（英文 `. `，中文 `。`）。
- [x] 中文符号页 ASCII 双引号 `"` 改全角 `“` `”`（Keys.ets symbolRows + SYMBOL_ALTERNATES 覆盖 bug）。
- [x] **猫图/节日 PNG 分辨率修复（round 18）**：Harmony rawfile/cats 和 rawfile/festivals 原来用的是 @1x 版本（~7KB/张），Android 用 @3x（~50KB/张）。density=3 设备上会导致猫图拉伸模糊。已从仓库根 `assets/brand/cats/sprites/*@3x.png` 和 `assets/festivals/*/*.png` 复制替换，SHA256 与 Android APK 内资源完全一致（8 张猫图 + 72 张节日图）。视觉验证：米米莫/莫莫/圣诞装扮等关键图与 Android 像素级一致。
- [x] **输入法子类型配置修复（round 19）**：`input_method_config.json` 原来声明了 4 个子类型（注音/拼音/日文/英文），但英文是通过键盘内部 toggle 切换的（与 Android 一致），不应作为系统子类型。已移除 `MeowpuutEnglish`，保留 3 个子类型（zh_TW/zh_CN/ja_JP），与 Android 的行为对齐（Android method.xml 只有 zh_TW/zh_CN，日文通过设置页切换；Harmony 增强为系统子类型切换，更符合 HarmonyOS 规范）。
- [x] **开源许可证文件补齐（round 21）**：Harmony rawfile/licenses 原来只有 `THIRD_PARTY.md` 一个汇总文件，Android APK 有 24 个详细的各组件许可证文件（cldr-emoji/jieba/mimo-jp/mimo-pairs/OpenCC 等）。已从 APK 提取并复制全部 24 个文件，SHA256 验证完全一致。设置页"开源许可"对话框现在会显示完整的许可证列表，与 Android 一致。
- [x] **资源全面对比验证（round 21）**：用视觉能力 + SHA256 对比 Android APK 与 Harmony HAP/rawfile 的所有关键资源：
  - ✅ 猫图 8 张 @3x：SHA256 完全一致，视觉验证像素级一致
  - ✅ 节日 PNG 72 张：SHA256 完全一致，视觉验证像素级一致
  - ✅ festivals.json：语义等价（APK 版压缩去空格，Harmony 版带格式化，ConvertFrom-Json 解析后内容一致）
  - ✅ 许可证 24 文件：SHA256 完全一致
  - ⚠️ mimo_base.bin：Harmony 用最新编译版本（77,632,544 字节），Android APK 用旧版本（77,624,824 字节，差 7,720 字节）。这是词库版本差异（Harmony 用了更新的 compile 产物），功能逻辑完全一致，候选词可能略有差异但不影响核心功能。可接受。
- [x] **设置页面补齐（round 40-41，对照 APK 0.9.1）**：通过 adb 连接真机（vivo V2231A）+ `uiautomator dump` + classes.dex 字符串提取，确认 APK 0.9.1 的设置页比仓库 Prefs.kt 多了 6 个字段（`keyPopups`/`hapticStrength`/`keySound`/`keySoundVolume`/`keyboardHeight`/`effects`）。已在 Prefs.ets 补齐这 6 个字段，SettingsPage.ets 补齐对应 UI：候选栏预览（barPreview）、视觉特效选择（轻量/标准/极致）、键盘高度（矮/标准/高）、按键气泡开关、振动强度滑块（弱/中/强）、按键声选择器（系统/关闭/自定义）、自定义音效音量滑块（0-100%）。版本号 0.8.0→0.9.1。编译通过（BUILD SUCCESSFUL）。
- [x] **hapticStrength 接入 vibrator（round 41）**：`keyFeedback`/`tickFeedback` 按 `prefs.hapticStrength` 分档调时长（light/medium/strong → 按键 8/12/16ms，节拍 5/8/11ms）。Harmony `vibrator.vibrate` 无独立 amplitude 参数，更细的 `startVibration` + `VibrateAttribute` 留待后续。
- [x] **effects/keyboardHeight/keyPopups 行为接入（round 41 立项 → round 44 完成，round 57 复核确认）**：这三项已在后续 rounds 完整接入键盘实际绘制，round 57 逐链路复核确认：`keyboardHeight`→`Look.heightScale`→`resizePanel` 的 `scaledKeys` 缩放 + `MeowpuutKeyboard.fitKeysToPanel`（L343/L561）；`effects`→`Look.effectAlphaScale`(extreme 0.82) + `leanDuration`(lightweight 140ms)（Theme L82/L87）；`keyPopups`→`KeyboardState.keyboard.keyPopups`→`keyPopupsEnabled()`→`showBalloon`（MeowpuutKeyboard L121/L1774）。
  - 注：`keyboardHeight` 的「直接改 panel 高度导致绘制内容溢出」问题已通过 `resizePanel` 里 `scaledKeys = keysDp * heightScale` + 键盘绘制同一 `heightScale` 双重缩放解决，不再是「两套独立计算」。
- [x] **设置页措辞 + 顺序对齐 Android 0.9.1（round 41，用 qwen3.8-max 视觉 + uitest dumpLayout 双重验证）**：起子 agent 用火山网关 `volcai` + `qwen3.8-max`（支持 `input: [text, image]`）读出 Android 设置页权威清单（22 项），对照发现并修正：① 措辞统一（"输入模式"→"输入方式"、"使用简体中文"→"中文"、"明暗"→"色调"、"按键形状"→"造型"、"配色"→"色系"、"显示猫咪"→"米米莫与莫莫"、"节日主题"→"节日装扮"）；② 新增"键盘位置=贴底"只读项（Android 有、Harmony 缺，dex 无 keyboardPosition 字段说明是固定展示项）；③ 外观 section 重排为 Android 顺序（候选栏预览→视觉特效→键盘高度→键盘位置→造型→色调→色系→玻璃强度→米米莫与莫莫→节日装扮）；④ 振动强度默认值 medium→strong；⑤ 修复重排时色系 Select 漏设 selected/value 导致的空值显示。编译通过，uitest dumpLayout 验证措辞与 Android 完全一致。
- [x] **设置页精确措辞对齐 strings.xml（round 41）**：找到 Android 权威字符串资源 `Android/app/src/main/res/values-zh-rCN/strings.xml`，据此进一步精修：App 名"喵撲"→"喵扑"（app_name）、日语模式"日文"→"日本語"（mode_japanese）、玻璃强度"柔和/均衡/鲜艳"→"柔和/标准/通透"（strength_soft/balanced/vivid）、色系"海洋/鼠尾草/薰衣草/琥珀"→"海盐蓝/鼠尾草绿/雾紫/琥珀蜜"（palette_ocean/sage/lavender/amber）。编译通过，uitest dumpLayout 实测"色系=玫瑰奶茶/玻璃强度=标准/喵扑/日本語"等全部与 strings.xml 一致。

## High（优先）

- [x] 展开候选面板整体缺失：已在 `MeowpuutKeyboard` 实现 `layoutPanel/drawPanel/handlePanelTouch/panelCellAt`（多行网格 + 纵向拖动 + 惯性 + 点选候选 + 日语猫爪标记 + 空态「暂无候选」），`drawKeys` 展开时覆盖键区，`handleTouch` 展开时拦截。触发链路（`onToggleExpanded` → `expanded` → `buildState` 传递）已通。
- [ ] 展开面板懒加载 `panelNeedMore` 语义：鸿蒙在 `onToggleExpanded` 已一次性 `composer.loadMore(96)`，滚动近底部的 `onNeedMore` 追加目前是空实现（候选已取足，暂无需追加）。
- [x] 按键震动反馈（部分）：`keyFeedback`（KEYBOARD_TAP）+ `tickFeedback`（CLOCK_TICK）已接 `vibrator`，受 `prefs.haptics` 控制；已加 `ohos.permission.VIBRATE`。音效（`prefs.sound`）因 HarmonyOS 无 playSoundEffect 等价物暂留待调研。
- [x] 无障碍基础（部分）：键盘根组件已加 `accessibilityGroup(true)` + `accessibilityText`，整块对读屏可识别。逐键虚拟节点（Android VirtualAccessibility 等价）需叠加透明语义层 + 真机 TalkBack 验证，专项待办。
- [x] 节日装扮：`KeyboardState.festival` + `MeowpuutAbility.festivalTheme` 传递；`loadFestivalArt` 懒加载换装猫/右端饰簇 PNG（按 theme.id 去重）；`seats()` 节日按 bust 落座；`drawFestivalEnd` + `placeRight` 画右端饰簇。trim 花边 Android 端也只解析不绘制（`*_frame.png` 无素材），故鸿蒙同样不画。
- [x] 猫咪爪影：`pawShadows()` 在玻璃体后、猫前，玻璃内每只前爪下画黑色椭圆软阴影（浅色 0.20/深色 0.35，1.5 blur），对照 Android pawShadows。
- [x] 猫爪压在玻璃前缘之上：`drawCats` 补玻璃内第二次绘制，`pawOvalsClip` 按每只圆爪椭圆裁剪（对照 Android drawCat 第 388-399 行 + paws Path 第 305-312 行），深色黑猫爪子也叠暖光。

## Medium

- [x] Lexicons 词库/日文词表异步读取：`getRawFileContentSync` → `await getRawFileContent`（Promise），大词库 mimo_base.bin（77.6 MB）不再阻塞主线程；已真机验证完整读入（data.length=77632544）且组字正常。
- [x] `“` 键长按备选串覆盖 bug（随符号页修复一并处理：key 从 ASCII `"` 改为全角 `“`）。
- [x] 按键按下态视觉：ACCENT 按下 `lighten(accent,0.15)`、UTILITY 按下 `keyPressed`、字符键仅平板或无 preview 时 `keyCharacterPressed`（手机竖屏有预览靠弹气泡不加深），对照 Android KeysView.kt:131-137。
- [x] 候选行两端渐隐：`fadeRowEnds()` 用 destination-out + 线性渐变（对照 Android fadeRowEnds，ROW_FADE=18），仅在 barMaxScroll>0.5 超宽时按滚动位置擦淡两端。
- [x] 按键气泡形状：`drawBalloon` + `balloonPath` 实现键身经 S 曲线收拢到圆角气泡 + 投影（模糊 4/下移 2/黑 0.45/0.20）+ 细描边（0.5 白 0.10/黑 0.06）+ 标签略上移（0.46），对照 Android PreviewOverlay.drawBalloon/balloonPath。
- [ ] 抚摸/提交粒子动画缺失（heart/paw/note/sparkle 喷发）。
- [x] 深色模式黑猫暖色光晕：身体（玻璃外）用 `shadowBlur=2.2×scale` + `#FFEDD6` 0.6 叠光（对照 Android glow() 的 GLOW_BLUR=2.2），前爪（玻璃内）同样叠光。非 Android extractAlpha+BlurMaskFilter 的高斯轮廓光，但观感对齐。
- [ ] CatStage 统一构造入口缺失（触摸与 seats 两处手写，row 传整行非 pill 带）。
- [x] TextUnits 删除字素：鸿蒙无 ICU BreakIterator（`@ohos.i18n` 只有 getLineInstance 行分割），改为 UAX #29 近似实现 `lastGrapheme`，正确处理 emoji ZWJ 序列/肤色/VS16/变音/区域指示符旗帜（17 例 Node 验证全过）；中文词仍按 2 字近似。
- [x] Festivals.met() 已见节日列表函数：补 `Festivals.met(since, today, loaded)`（对照 Android，返回 [since,today] 内穿戴区间曾开始的主题，按 manifest 序）。
- [x] Festivals manifest days 合法性校验：`parseDate` 现在校验 yyyy-MM-dd 精确格式（长度/正则/溢出反查），`parseTheme` 校验 days 长度==3 + first<=main<=last，非法整条主题跳过。
- [x] 设置页输入法启用状态指示：`updateStatus()` 读 `getInputMethodSetting().getInputMethodsSync(true)` + `getCurrentInputMethod()`，显示「未启用/已启用/当前使用」三种文案（对照 Android updateStatus）。
- [x] 设置页开源许可（Licenses）入口与对话框：`LicenseDialog` 读 rawfile/licenses/* 展示（已打包 THIRD_PARTY.md）。
- [x] 「选择输入法」按钮：`InputMethodListDialog` 经 `CustomDialogController` 弹出（Android showInputMethodPicker 等价物）。
- [x] 数字/密码/邮箱/URL 字段类型自动识别：`detectFieldType()` 读 `getEditorAttributeSync().inputPattern`，数字/电话/日期 → 英文+符号页，密码/邮箱/URL → 英文；inputStart 时先重置 english/page 再检测。
- [x] 设置页试打区多行 + note 说明：TextInput → TextArea（多行），补 script_note / festivals_note 两条说明（对照 Android SettingsActivity）。

## Low（观感收尾）

- [x] 小写字母标签上移（`frame.height * 0.04` 抬升，drawKey L1712）。
- [x] 按键标签超宽缩字号（shrink-to-fit，drawKey 内已实现）。
- [x] ACCENT 键标签颜色纯白 `#FFFFFFFF`（drawKey L1644，非 look.keyText）。
- [x] 气泡字号分支已对齐 Android（round 16）：`showBalloon` 四分支「平板不弹 / 横屏 28 / 多字符 24 / 默认 BALLOON_FONT=34」，字号在 struct 的 `balloonFont(key)` 里算，经 `BalloonEntry.fontSize` 传入 `drawBalloon`。Android KeysView.kt:221-230。
- [x] 玻璃上爪印阴影（pawShadows，见 High 章节）。
- [x] 按压猫咪形变（squash wide 1.06 / tall 0.93）。
- [x] 组字时猫咪倾斜（animateLean ±2.5°）。
- [x] 长按备选条选中项高亮底 + 阴影 + 白字 + 超宽缩字号（对照 PreviewOverlay.drawStrip L107-132，本轮补齐）。
- [x] 摸猫进度爱心（toast 内 5 颗爱心点亮 + 单颗大爱心 + emphasis 强调层 + 尾部省略，对照 CandidateBarView.drawToast L552-596，本轮补齐）。
- [x] 摸猫 toast 动画（round 17）：淡入 180ms/淡出 200ms（toastAlpha）+ 弹跳 scale 0.86→1.0（fadeIn 180ms，围绕 cx/cy）+ duration 分支（emphasis 2400 / 非 1400）+ announce 补 emphasis=true。对照 CandidateBarView.toastAlpha L540-545 + drawToast L556-597。
- [x] 展开面板空候选占位文案「暂无候选」：`drawPanel` 已接 `'暂无候选'/'暫無候選'`（按 keyCtx.simplified）。
- [ ] PillPainter 缺着色器缓存（Android 有 shader 缓存避免每帧重建；Harmony 每帧 createLinearGradient，属性能优化、非功能差异，低优先）。
- [ ] Glyphs.paw 填充依赖 ctx.fillStyle 前置状态（代码结构差异，非功能，不影响输出）。
- [ ] shadow() 用 rect(0,0,10000,10000) evenodd 近似 clipOutPath，魔术数可能裁错（已实现，仅潜在边缘裁切隐患）。
- [x] 缺 wantsMoreContrast 系统高对比度检测 → 确认 Harmony 平台无等价 API（见「平台能力差异」章节），记录不补。
- [x] 摸猫切简繁提示附注「（中文输入生效）」：`onPet` 已按 `!chineseActive`（英文/日文模式）追加附注（对照 Android MeowpuutIME.kt:633，本轮补齐）。
- [x] 试打区多行输入框：TextInput → TextArea（对照 Android minLines=3）。

## 备注

### 模拟器 createPanel 失败的根本原因（已确诊，环境级，非代码 bug）

- **现象**：模拟器上 `inputStart`/`keyboardShow` 正常触发，但 `createPanel` 返回
  `{"code":1,"message":"error is out of definition. "}`，面板永远弹不出。
- **根因**：模拟器把第三方输入法以**基础模式（隔离沙箱）**运行，SELinux domain 是
  `input_isolate_debug_hap`（隔离 + 调试），而非完整体验的 `input_hap`。隔离 domain
  缺少窗口创建（`SetWindowType` / vsync / accesstoken）授权，所以 createPanel 被拒。
  SP33 镜像（7.0.0.120）仍未修复——只是错误表现从旧的 vsync 1001 变成 code:1。
- **机制**：HarmonyOS 输入法分两种启用态（`inputMethod.EnabledState`，since 15）：
  `DISABLED` / `BASIC_MODE` / `FULL_EXPERIENCE_MODE`；另有安全模式
  （`inputMethodEngine.SecurityMode`：`BASIC`=禁网 / `FULL`=可联网，since 11，只读）。
  只有 `FULL_EXPERIENCE_MODE` 下框架才完整驱动输入法窗口。模拟器默认给第三方 IME
  授予 BASIC_MODE（隔离），且镜像未提供切换到完整体验的授权路径。
- **证据**：OpenHarmony SELinux 有 4 个输入法 domain：`input_hap`（完整）、
  `input_debug_hap`、`input_isolate_hap`、`input_isolate_debug_hap`（隔离+调试）。
  我们的进程 context 是 `input_isolate_debug_hap`。参考 msime 项目 README：
  「输入法要在 FULL_EXPERIENCE_MODE 下才会被框架驱动」。
- **结论**：真机（`56V0225905003230`，HUAWEI Pura X / VDE-AL00，API 26）同一代码可跑，
  因为真机授予完整体验模式。**已真机端到端验证通过（2026-11-14）**：设置页正常
  （`当前使用的键盘是喵撲。`）、键盘 createPanel 成功弹出、触摸/按键/注音提交
  （`commit key='ˊ'` → `commit('6')` → `insertTextSync ok`）全链路工作。
  模拟器这条路需等华为镜像修复「第三方 IME 完整体验模式授权」，或改用真机验证。

### 验证策略

- 补齐按「先写代码、构建通过 + 逻辑对照 Android」推进，构建成功 + 逻辑一致即视为
  通过；视觉/交互细节（节日装扮、粒子、气泡形状、emoji 编码差异等）留待真机端到端。
- 真机 debug 待办（华为编码/emoji 差异等）单列，见下节「真机验证清单」。

## 真机验证清单（HUAWEI Pura X / VDE-AL00 / API 26，2026-11-14 起）

- [x] 设置页：状态「当前使用的键盘是喵撲。」、首次使用说明、打开输入法设置/切换键盘
      按钮、试打区 TextArea、输入模式 Select（注音/拼音/日文）、简繁切换均正常渲染。
- [x] createPanel 成功：真机完整体验 domain，键盘弹出（`keyboardShow` + panel shown）。
- [x] 触摸按键 → 提交 → 插入文本全链路：`MeowpuutKB up/commit` → `commit()` →
      `insertTextSync ok`，TextArea 实际写入（注音 `6` 两次 → 显示 "66"）。
- [x] 输入模式切换：设置页切「日文」→ `prefs reloaded mode japanese -> japanese`。
- [x] 日语端到端 simimasai → すみません（罗马字逐键 `s i m i m a s a i` → 空格 →
      `commit('すみません')` → `insertTextSync ok`，TextArea 实际显示「すみません」）。
- [x] 拼音端到端 g → 组字（29 候选）→ 空格 → `commit('過')` → TextArea 实际显示「過」。
- [x] 词库加载验证：`mimo_base.bin`（77.6 MB）经异步 `getRawFileContent` 完整读入
      `data.length=77632544`；`lexicon pinyin ready ... 0 KiB` 的 **0 KiB 是正常的**
      （`mpn_lexicon_create_from_base_in_place` 走 mmap 原地读、不复制堆，见 ENGINE.md）。
- [x] emoji/华为编码差异：真机注入 `😀𩽾🙂`（3 个 BMP 外字符 = 6 个 UTF-16 单元）经
      `insertTextSync` 提交，TextArea 原样显示 `😀𩽾🙂` 无损坏（c0=d83d 代理对正确）；
      与 Android JNI 的 UTF-16 处理对齐，NAPI 层 `ToJS`/`FromJS` 转换正确。
- [x] 视觉/特效/美术细节目视（2026-11-15）：双猫聚拢右端✓、爪基线贴玻璃✓、摸猫粒子（金色爪印）✓、
      简繁切换 toast（「换为繁体中文」）✓、按压气泡 S 曲线（ㄗ 气泡截图确认）✓、emoji 彩色渲染✓。
      节日装扮/深色暖光随日期与主题未专项截证（素材已对齐 APK，逻辑已对照）。
- [ ] 逐键无障碍虚拟节点（真机 TalkBack）。
- [x] 长按备选条（长按 ㄅ → 「吧不把别被」横条 + 选中高亮）✓、展开候选面板（ㄋ 组字 → 箭头 ∨ →
      4列×5行网格「你那呢您…」）✓、摸猫/喵语 toast（粒子+弹跳+切简繁）✓（2026-11-15 真机）。

> 真机构建环境注意：闪退后 `DEVECO_SDK_HOME` 与 JDK PATH 可能丢失，重建前需设
> `$env:DEVECO_SDK_HOME='...\sdk'` 且把 `...\DevEco Studio\jbr\bin` 加进 PATH，并
> `hvigorw.js --stop-daemon` 重启 daemon（否则报 `spawn java ENOENT`）。

## 功能差距审计（Android ↔ Harmony 逐文件对比，2026-11-14）

子代理对 10 组对应文件逐一 read/grep 对比后，确证的功能差距如下：

### 功能缺失（Harmony 没有，需补齐）

- [x] **物理键盘支持**（2026-11-14 白盒已实现，待真机验证）：Android `MeowpuutIME.kt`
  `onKeyDown`/`onKeyUp`/`typeHardware`/`consumedKeys`（Space/Enter 选词、Del 退格、Esc
  取消、方向键移动高亮、拼音数字选候选、注音 Shift+数字选候选、`'`/`-` 分隔符）。
  Harmony 已用 IME Kit 官方 API 白盒补齐：`inputMethodEngine.getKeyboardDelegate()` +
  `KeyboardDelegate.on('keyEvent', (ev: KeyEvent) => boolean)`（SDK `.d.ts` L1792-1839，
  since 8/10），`ev`（`@ohos.multimodalInput.keyEvent.KeyEvent`）含 `key.code`(KeyCode)、
  `action`(DOWN=1/UP=2)、`unicodeChar`、`ctrlKey`/`altKey`/`shiftKey`/`logoKey`，与
  Android `KeyEvent` 完全对应。已实现 `hardwareKeyEvent`/`typeHardware`/`visibleCandidates`/
  `moveHighlight` + `ZHUYIN_KEYS` 常量（对齐 Android L768 `"1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-"`），
  并让 `buildState()` 复用 `visibleCandidates()`。→ 待真机接外接键盘端到端验证。
- **逐键无障碍虚拟节点缺失**（已找到官方方案，留 QWEN/真机实施）：Android
  `VirtualAccessibility.kt` 用 `AccessibilityNodeProvider` 把每个键/候选暴露为 TalkBack
  可触摸、可激活的虚拟节点。Harmony 白盒调研找到**官方等价 API**：
  `Canvas.accessibilityVirtualNode(builder: CustomBuilder)`（SDK common.d.ts L24306，
  since 11）——文档明确「为自绘组件（如 Canvas）传 CustomBuilder，其中的占位组件**只
  布局、不显示**，无障碍服务取节点信息时返回它们」，即 Android AccessibilityNodeProvider
  的 Harmony 等价物，且**完美解决触摸拦截**（虚拟节点不参与 hit-test，不挡 `onTouch`）。
  配套：`accessibilityLevel('yes')`（绕过 accessibilityGroup 合并）、
  `accessibilityRole(AccessibilityRoleType.BUTTON=5)`、`accessibilityText(spoken)`；
  键的朗读标签在 `Key.spoken`、frame 在 `KeyPlacement.frame`（vp 单位，可用 `.position()`）。
  现状 `MeowpuutKeyboard.ets` L593-597 只有整块 `accessibilityGroup(false→无意义)`。
  → 实施：给键盘 `Canvas(this.keyCtx2d)` 挂 `accessibilityVirtualNode(this.keyVirtualBuilder)`，
    `@Builder keyVirtualBuilder()` 里 `Stack() { ForEach(键) → Blank().position(frame)…
    .accessibilityText(spoken).accessibilityLevel('yes').accessibilityRole(BUTTON) }`；
    候选栏同理。因虚拟节点「不显示」，**必须真机 TalkBack 验证**，白盒无法自证对齐，
    故记此方案而不仓促落码。
- [x] **无障碍语音播报**（2026-11-14 白盒已实现，待真机 TalkBack 验证）：Android
  `CandidateBarView.announce(text)` → `announceForAccessibility(text)` 让 TalkBack 朗读
  （如摸猫切换简繁时读「已切换为简体中文」）。Harmony 原 `MeowpuutKeyboard.announce`/
  `pet` 只显示视觉 toast、无语音。已补齐 `announceAccessibility(text)`：用
  `@kit.AccessibilityKit` 的 `accessibility.isScreenReaderOpenSync()` 判断 +
  `accessibility.sendAccessibilityEvent({ type:'announceForAccessibility', bundleName,
  triggerAction:'click', textAnnouncedForAccessibility:text })`，在 `announce` 和
  `pet`（toast 非空时）里调用。→ 待真机开 TalkBack 摸猫验证朗读。
- **按键音效未实现**：Android 用 `AudioManager.playSoundEffect` 播放按键音（标准/删除/
  空格/回车）。白盒调研结论：Harmony `@ohos.multimedia.systemSoundManager`（since 23）
  `SystemSoundType` 只有 PHOTO_SHUTTER / VIDEO_RECORDING_BEGIN / VIDEO_RECORDING_END，
  **无按键音类型**、无 `playSoundEffect` 等价物；`@stagemodelonly`。→ 唯一可行是
  `AudioRenderer` + 预置按键音音频资源（rawfile wav），是较大改动且需音频素材，
  留待确认素材后做。`prefs.sound` 开关已就位，`keyFeedback()` 目前只做震动。
- **高对比度无障碍适配缺失（平台能力缺失，无法补齐）**：Android `wantsMoreContrast()`
  （UiModeManager.contrast）检测系统对比度 → `Look(opaque=true)` 玻璃实色。白盒调研：
  Harmony **无"系统对比度开关"检测 API**；`@ohos.graphics.text.setTextHighContrast()` 是
  **设置**而非检测，且明确「对 Canvas 自绘文字不生效，只对系统 Text 组件生效」（SDK
  L4001-4002），而喵撲键盘是 Canvas 自绘，完全不适用。`Configuration` 只有
  `fontSizeScale`（字号缩放），无 contrast。→ 记录为 Harmony 平台能力缺失，
  `applyLook()` 保持 `opaque=false`。
- **系统配置/内存变化监听（平台能力缺失，低影响）**：Android `MeowpuutIME` 有
  `onConfigurationChanged`（深色切换 → `applyLook()` 重算明暗）与 `onTrimMemory`
  （后台释放词库）。白盒调研：Harmony `InputMethodExtensionAbility`（SDK `.d.ts` L33）
  **不继承 `ExtensionAbility`**，只有 `onCreate`/`onDestroy`，**无** `onConfigurationUpdate`/
  `onMemoryLevel` 回调；其 `context`（`InputMethodExtensionContext extends ExtensionContext`）
  也无配置/内存事件。→ 无法监听系统深色切换与内存等级。影响极小：切换深色后输入法
  进程通常随宿主重建而重算 look；词库走 mmap 且 `inputStop` 已 `clear`。记录为平台差异。
- [x] **光标移出组字区清空组字**（2026-11-14 白盒已实现，待真机验证）：Android
  `onUpdateSelection` 在组字时若光标被移走 → `composer.clear()`+`finishComposingText()`+
  `expanded=false`。Harmony 原无此处理。已补
  `hwDelegate.on('selectionChange', (ob,oe,nb,ne) => …)`：组字时若光标/选区变化则清空
  组字并收起展开面板（Harmony 组字只在候选栏、不写输入框，故无需 `finishComposingText`）。

> 说明：独立文件的 `PreviewOverlay.kt`（按键气泡 + 长按备选条）在 Harmony **已实现**，
> 只是合并进 `MeowpuutKeyboard.ets`（`drawBalloon` L1640 / `balloonPath` L1666 /
> `BalloonEntry` / `AlternatesState`），`KeyTouches.ets` 有完整 `showBalloon`/
> `showAlternates`/`selectAlternate` 触摸逻辑，`Geometry.ets` 有 `KeyBalloon`/
> `AlternatesStrip`。功能对齐，仅视觉细节待 QWEN 精修。

### 行为差异（已修正 / 保留）

- [x] **候选排序 `moreJapanese` 位置**（已修正对齐 Android）：Harmony 原把同一读音的
      弱义项（moreJapanese，如「私密马赛」）紧插到主词之后，而 Android 把它们与
      前缀/假名候选一起排到**第 9 位（第一页）之后**（`CandidateMerge.pinyin` 的 extras，
      docs/DESIGN.md §4「其余日语读法排到第一页之后」）。本轮已改回 Android 语义
      （`CandidateMerge.ets` 的 moreJapanese 归入 extras）。
- [x] **日语词表宽松匹配 `wordsLoose`**（保留，为有意增强）：`JapaneseWords.ets` 新增
      `byKana`/`wordsLoose` 在精确匹配不命中时按假名兜底（`simimasai` 训令式 → 折成
      `しみまさい` → 反查 `sumimasen` 命中「すみません」）。Android 无此增强，但 Harmony
      只在**不命中时**兜底，不改变精确匹配的结果，保留（否则训令式罗马字用户打不出词）。

### 澄清（非差距）

- **emoji/颜文字（kaomoji）关联是 iOS 独占功能**：Android `Candidates.kt` 与 Harmony
  `Types.ets` 的 `Candidate` 都只有 `text/kind/coreIndex/consumed` 四字段、无 symbol；
  `associations.json`/`emoji.tsv`/`kaomoji.tsv` 只由 iOS（`Sources/Symbols.swift` +
  `iOS/Keyboard/Kaomoji.swift`）加载。两端符号页的 `^_^` 键只是字面量插入，非颜文字
  面板入口。→ 对照 Android 无需补齐（Android 也没有）。
- 其余文件对（Composer 主体、Romaji、Theme、Keys、Prefs、Lexicons、NativeEngine FFI、
  候选渲染）逐行对齐，无实质差距。

## 视觉特化对齐基准（Android/iOS 调研结论，2026-11-14）

> **白盒逐行核对结论（2026-11-14，四项美术文件与 Android 完全一致，无需改代码）**：
> `Theme.ets`↔`Theme.kt`（keyboardTop/Bottom、keyFace、keyUtility/Pressed/CharacterPressed、
> keyShadow/Text/Disabled、candidate、balloon、pill 6×2、palette color 6×2、glassFill
> alpha、causticColors、lighten/darken/withAlpha）、`Geometry.ets`↔`Geometry.kt`
> （KeyMetrics 三 idiom×dense、CandidateRegionLayout cats/no-cats 全坐标公式、stage()）、
> `GlassOutline.ets`↔`GlassOutline.kt`（WAVE/CLOUD/CAPSULE 三形状数学、smoothstep/min、
> waveCount/Offset、cloudCircles/Top、endRadius、trace 采样）、`Painting.ets`↔`Painting.kt`
> （GlassPainter shadow/body 十层、PillPainter、Glyphs paw/chevron/shift/delete/globe/
> heart/sparkle/note 八图标）——均逐数值对齐。仅剩的视觉差异即本节约定的 mask 细节与
> iOS 借鉴点，归 QWEN 视觉精修，非数值对齐问题。

- **键面**：Android 是「底部 1dp 实心底边（crisp bottom edge）+ 纯色/渐变键面」；
  ACCENT 纯色 accent、UTILITY 纯色 keyUtility、CHARACTER 渐变 keyFaceTop→Bottom；
  按下 ACCENT→lighten(accent,0.15)、UTILITY→keyPressed、CHARACTER→keyCharacterPressed
  （手机竖屏有预览时不加深键面）。已对齐：ACCENT 纯色 + crisp 底边 + 小写上移 0.04h
  + 超宽缩字号 + space/utility 用 min(size,utilityFont+1)。
- **玻璃 10 层**（Painting.kt GlassPainter L43-184，数值与 iOS 逐条一致）：投影→透出光
  (下半部)→本体→内部渐层→边缘折光 3.5@blur1.8→焦散 2.4(向上淡出)→上缘亮线 1.4→
  左上镜面高光 radius70→抛光边 1.5 三段→下缘淡影 5@2.5 + 细线 0.5@y0.75。Harmony
  GlassPainter 已实现全部 10 层的几何与颜色，但 **4 处「渐变 alpha 蒙版」未对齐**（Android
  用 `saveLayer + PorterDuff.DST_IN` 的 `masked()`）：① spill 透出光的竖向 mask（centerY→
  bottom）、② 焦散向上淡出的竖向 mask（0→0.35→1）、③ 左上镜面高光的径向 mask（RadialGradient
  radius70）、④ 下缘淡影+细线的竖向 mask（0→0.5→1）。根因：ArkUI Canvas 无 `saveLayer`，
  直接 `globalCompositeOperation='destination-in'` 会误伤已画的本体/内釉/边缘层，需离屏
  canvas 分步合成。留待真机/QWEN（视觉质感微调，不影响功能与布局）。
- **节日 trim 花边：Android/iOS 都只解析不绘制**，实际只画右端 ornament 簇 + 装扮猫 +
  胶囊主题色；`FestivalTrimLayout.slices` 是死代码。Harmony 现状（只画右端）已对齐。
- **可借鉴的 iOS 独有优化点**（Harmony Canvas 可做）：① 猫呼吸动画（scale.y +1.8%、
  5.2s 周期、两猫错开）；② 候选行左侧柔光带（米米莫黑猫身上垫光带）；③ 键盘底光池
  +色系淡彩；④ 候选按下 spring 弹性；⑤ toast 描边+阴影+bounce 图标；⑥ 粒子特效
  （heart/paw/note/sparkle，Glyphs 已就绪）。

### 本轮视觉特化已完成（2026-11-14，均构建通过）

- [x] 键面：ACCENT 纯色（去掉错误的 accent→pill 渐变）+ crisp 1dp 实心底边（替代 blur 阴影）。
- [x] 标签：小写字母上移 0.04h、超宽缩字号（maxWidth=w-8）、space/utility 用
      min(size,utilityFont+1)、ACCENT 标签纯白（含 icon，drawIcon 改为传 color）。
- [x] 组字 lean 倾斜：composing 变化时 ±2.5°（米米莫 +/莫莫 −），320ms easeInOut；
      由 rebuild() 统一检测、pollHost 16ms 循环推进。
- [x] 按压 squash：按在猫身上时 wide 1.06 / tall 0.93（pressedCats，抬手清除）。
- [x] 摸猫粒子：heart/paw/note/sparkle（米米莫随机三选一金黄向右、莫莫粉心向左），
      easeOut quad、size 0.4→1 弹入、drift×1.4 旋转、α1−t、900ms、上限 8。

### 真机目视待办（屏幕锁定时无法自动解锁，需手动解锁后验证）

- [ ] 键面 crisp 底边 + ACCENT 纯色 + 标签优化目视
- [ ] lean 倾斜 + squash 按压 + 粒子喷发目视（摸猫/组字时）
- [ ] 呼吸动画、柔光带、底光池（性能权衡后决定是否做）

## 模式切换链路（真机实测结论，2026-11-14 深夜）

**结论：模式切换（注音/拼音/日文）机制本身工作正常，之前"切换不生效"是我自动化
测试的坐标没点中下拉项，不是产品 bug。**

- 真机链路（已实测验证）：设置页 Select 选模式 → `switchCurrentInputMethodSubtype`
  返回 true → 系统切 subtype → inputMethod 进程 `setSubtype fired`（id 正确）→
  setSubtype 回调写 `prefs.mode` → `mode` getter 更新。日志证据：
  `switch subtype MeowpuutPinyin -> true` → `setSubtype fired: id=MeowpuutPinyin locale=zh-CN`
  → `prefs reloaded mode pinyin -> pinyin`。
- **重要**：两个进程的 el2 `filesDir`（`/data/storage/el2/base/haps/entry/files`）是
  **进程隔离**的——路径字符串相同但各写各的，`meowpuut-settings.json` 镜像文件
  **不能跨进程同步**（main 进程读到 pinyin、inputMethod 进程读到 japanese，同一路径）。
  所以 Prefs.ets 的"镜像文件跨进程同步"注释**是错的**，镜像只在同一进程内有效。
  mode 跨进程**唯一可靠通道是系统 subtype 机制**（`switchCurrentInputMethodSubtype`），
  它确实工作。→ 无需改代码，但需修正 Prefs.ets 里"镜像负责跨进程同步"的错误注释。
- 自动化测试坐标备忘（屏幕 px，键盘收起时设置页布局）：
  Select 输入模式 [974,1679][1224,1799]（点 1099,1739 打开下拉）；
  下拉**向上弹出**：注音 [768,1334] 拼音 [816,1478] 日文 [816,1622]。
  键盘弹出时 TextArea 会上移，Select 可能被遮挡，**切换模式前必须先收起键盘**
  （`uitest uiInput keyEvent 2` 返回键）。

## 明天调试清单（优先级排序，2026-11-14 深夜交接）

### 一、功能缺失（白盒补齐，对照 Android）

1. [x] **物理键盘支持**（已白盒实现，明天真机验证）：用 IME Kit 官方
   `inputMethodEngine.getKeyboardDelegate()` + `on('keyEvent')` 补齐了 `hardwareKeyEvent`/
   `typeHardware`/`visibleCandidates`/`moveHighlight` + `ZHUYIN_KEYS`，构建通过。
   → 明天接外接键盘端到端验证：拼音打 `g` 候选→空格选词、数字选候选、方向键移动、
   Esc 取消、注音键位、`'`/`-` 分隔符。**关键风险点**：`KeyboardDelegate.on('keyEvent')`
   回调的返回 `true/false` 是否真的能阻止系统默认处理（需真机确认消费语义）。
2. **逐键无障碍虚拟节点**（功能缺失，已找到官方方案，留 QWEN/真机实施）：Android
   `VirtualAccessibility.kt` 用 `AccessibilityNodeProvider` 逐键暴露 TalkBack 节点。
   Harmony 官方等价物 = `Canvas.accessibilityVirtualNode(builder: CustomBuilder)`
   （SDK common.d.ts L24306，since 11）：为自绘组件传 CustomBuilder，其中占位组件**只
   布局不显示**、**不参与 hit-test（不挡 onTouch）**，无障碍服务取节点信息时返回它们。
   配套 `accessibilityLevel('yes')` + `accessibilityRole(AccessibilityRoleType.BUTTON=5)`
   + `accessibilityText(Key.spoken)`，frame 用 `KeyPlacement.frame`。因虚拟节点「不显示」，
   必须真机 TalkBack 验证，白盒无法自证，故记方案（详见文件前部「逐键无障碍」条目）而不仓促落码。
3. **按键音效**（平台限制 + 素材依赖）：Harmony `systemSoundManager` 无按键音类型
   （只有拍照/录像），唯一可行是 `AudioRenderer` + 预置音频素材。→ 需先定素材来源
   （Android 系统按键音 wav 提取 / 自制），再写 AudioRenderer 播放逻辑；否则保留震动。
4. [x] **高对比度无障碍**（确认平台能力缺失，不补）：Harmony 无"系统对比度开关"检测
   API，`setTextHighContrast` 是设置且对 Canvas 不生效。`applyLook()` 保持 `opaque=false`。

### 二、行为对齐（已定案）

- [x] 候选排序 `moreJapanese` 排第 9 位后（已改 `CandidateMerge.ets`，对齐 Android）。
- [x] `wordsLoose` 训令式兜底（保留，有意增强）。
- [x] emoji/kaomoji 关联 = iOS 独有，Android/Harmony 均无，不补。

### 三、已确认的编码正确性（无需再验）

- [x] emoji/BMP 外字符 `😀𩽾🙂` 经 `insertTextSync` 提交，TextArea 原样显示无损坏。
- [x] 拼音 `g`→29 候选、日语 `simimasai`→`すみません` 端到端正常。

### 四、UX/视觉（切换 QWEN 3.8 视觉模型后做，先读本文件"视觉特化对齐基准"章节）

- [x] toast bounce/fade 动画（round 17 已补齐：淡入 180ms/淡出 200ms + scale 0.86→1.0 + duration 分支）。
- [x] 长按备选条选中高亮底（round 16 已补齐）。
- [x] 展开面板（round 15 已补齐）。
- [x] pet toast 爱心进度 + emphasis（round 16-17 已补齐）。
- [ ] 玻璃 4 处渐变 alpha 蒙版（spill/caustic/specular/bottom-shadow）：需 OffscreenCanvas 离屏合成（ArkUI Canvas 无 saveLayer），纯视觉特化，低优先。
- [ ] 逐键 TalkBack 无障碍虚拟节点：方案已记录（`accessibilityVirtualNode`），待真机验证。
- **iOS 独有优化（Android 无，非对齐目标）**：猫呼吸动画（scale.y +1.8%/5.2s）、键盘底光池（米米莫黑猫身上垫光带）。
- 注意：QWEN 有视觉，可截图对照 Android/iOS 精修；我（无视觉）只做白盒数值对齐。

---

## 核心逻辑文件系统核对结论（2026-11-14/15 白盒逐行核对）

> **Android 全部源文件（`ime/` 20 个 + `engine/` 6 个 + `app/SettingsActivity`）已 100% 核对完毕（至 round 21）。**
> 功能逻辑、显示常量、美术数值、组字引擎全部对齐；期间补齐了 10 处显示点/资源/配置差距（候选区背景、
> 长按备选条选中高亮底、摸猫 toast 爱心、切简繁附注、光标模式键面淡出、气泡字号 34/28/24
> 四分支、toast 淡入淡出/弹跳动画、猫图/节日 PNG @1x→@3x 分辨率修复、英文子类型配置移除、
> 开源许可证文件补齐）。
> 剩余仅为「纯视觉特化细节」（玻璃 4 处渐变 alpha 蒙版——需 OffscreenCanvas 离屏合成，低优先），
> 以及逐键无障碍虚拟节点（方案已记录，待真机 TalkBack 验证）。

| Android ↔ Harmony | 核对内容 | 结论 |
|---|---|---|
| `MeowpuutIME.kt` ↔ `MeowpuutAbility.ets` | 全部 54 方法（输入/候选/空格句号/删除/英文/翻页/符号/自动大写 + 硬键盘）| ✅ 已穷尽，硬键盘/光标清空组字/语音播报本轮补齐 |
| `Keys.kt` ↔ `Keys.ets` | 键集合/注音位/字母页/符号页×4/长按 accent+symbol/autoReturnMarks | ✅ 逐项一致 |
| `KeyStates.kt` ↔ `KeyStates.ets` | Shift 三态双击锁定/自动大写/Delete 连发节奏 | ✅ 一致 |
| `KeyTouches.kt` ↔ `KeyTouches.ets` | 触摸状态机（rollover/slide/长按备选/光标/删除/activate）| ✅ 一致 |
| `KeysView.kt` ↔ `MeowpuutKeyboard.ets`（键绘制）| 键面颜色分支/1dp 底边/键面渐变/标签颜色/icon 尺寸/小写上移 0.04h/超宽缩字号/光标模式键面淡出 | ✅ 一致（光标模式键面 alpha 170 + 标签隐藏 + 气泡字号 34/28/24 分支本轮补齐）|
| `Theme.kt` ↔ `Theme.ets` | 全部颜色/玻璃 alpha/明暗算法 | ✅ 一致 |
| `Geometry.kt` ↔ `Geometry.ets` | KeyMetrics/CandidateRegionLayout/stage | ✅ 一致 |
| `GlassOutline.kt` ↔ `GlassOutline.ets` | 三种形状数学 | ✅ 一致 |
| `Painting.kt` ↔ `Painting.ets` | 玻璃 10 层 + Pill + Glyphs 8 图标 | ✅（玻璃 10 层几何/颜色全对齐；仅 4 处渐变 alpha 蒙版因 Canvas 无 saveLayer 未做，见视觉章节）|
| `TextUnits.kt` ↔ `TextUnits.ets` | grapheme/词删除 | ✅（中文词删除为有意 2 字近似）|
| `ExpandedPanelView.kt` ↔ `MeowpuutKeyboard.ets`（展开面板）| quarter 列算法/拖动/fling/点选/日语爪标记/空态/行间线，常量 ROW=46/TOP=6/GAP=4 | ✅ 一致（仅 panelNeedMore 空实现，候选一次性取回）|
| `Cats.kt` ↔ `Cats.ets` | CatAffection（摸猫 5 次/1.6s/1.2s 切简繁）+ CatMotion（duck/shake/lift/nuzzle 动画常量全对齐）| ✅ 逐值一致 |
| `Festivals.kt` ↔ `Festivals.ets` | manifest v2 解析/sprite/bust/日期段 + theme 日期判定（step 1/2/3 排序/轮流）+ met + placeRight 布局 + isName 校验 | ✅ 逐行一致（含 step2 first 降序+last 升序、step3 first 升序、floorMod 轮流、本地日历日 today）|
| `CatStage.kt` ↔ `CatStage.ets` | CatPlacement（visible/paws/reach/covers/touch 44dp 热区）+ CatSeats.ends/seat/rise（slide 循环/边界/爪遮挡判定）| ✅ 逐行一致 |
| `CatSpriteData.kt` ↔ `CatSpriteData.ets` | 8 张猫贴图（尺寸/锚点/可见边界/cutLeft/cutRight/爪子坐标）| ✅ 逐值一致 |
| `KeyboardView.kt` ↔ `MeowpuutKeyboard.ets`（键盘容器）| 四层组装/look 分发/idiom/rows/展开覆盖/底部 inset/背景渐变 | ✅ 一致（背景渐变候选区本轮补 `keyboardTop` 纯色，键区已有）|
| `PreviewOverlay.kt` ↔ `MeowpuutKeyboard.ets`（气泡+备选条）| drawBalloon S 曲线/投影/描边 + drawStrip 选中高亮底/阴影/缩字号 | ✅ 一致（备选条选中高亮底+阴影 + 气泡字号分支本轮补齐）|
| `CandidateBarView.kt` ↔ `MeowpuutKeyboard.ets`（候选栏）| 候选行/滚动/渐隐/摸猫/粒子/切简繁附注 | ✅ 一致（toast 爱心进度+emphasis 层 + fade/bounce 动画 + duration 分支本轮补齐）|
| `Prefs.kt` ↔ `Prefs.ets` | 设置项 | ✅ 已对齐（设置页全项校验过）|
| `VirtualAccessibility.kt` | 逐键虚拟节点 | ⚠️ 官方方案 `accessibilityVirtualNode` 已记录，待 QWEN/真机 |

### engine/ 核心组字引擎（round 15 补齐核对，之前遗漏）

| Android ↔ Harmony | 核对内容 | 结论 |
|---|---|---|
| `engine/Candidates.kt` ↔ `engine/CandidateMerge.ets` | InputMode/CandidateKind/Candidate/CoreCandidate 类型 + CandidateMerge.pinyin（中文先/日语靠前/literal/extras 第 9 位插入）+ collapsed | ✅ 逐行一致 |
| `engine/Composer.kt` ↔ `engine/Composer.ets` | type/space/backspace/choose/loadMore/predictions/rebuild 三模式/resetCore/replay/keepSuffix/syncRaw/fetchCore，常量 FIRST_BATCH=48/TONES/TONE_MARKS | ✅ 逐行一致（PINYIN 用 wordsLoose+moreJapanese 为已记录的有意增强）|
| `engine/Romaji.kt` ↔ `engine/Romaji.ets` | kana 表（20 行）+ 前缀 11 + 别名 20 + x→l 复制 + extra 15 + reading 状态机（长音/分隔/ん/促音/最长 4 匹配）+ katakana + isKana | ✅ 逐行一致 |
| `engine/JapaneseWords.kt` ↔ `engine/JapaneseWords.ets` | tsv 解析（weight 降序/去重）+ word/words/best/size | ✅ 一致（+byKana/wordsLoose 训令式兜底为已记录的有意增强，`words` 精确路径保留）|
| `engine/NativeEngine.kt` ↔ `engine/NativeEngine.ets` | FFI 常量（KEY_BACKSPACE 0xff08/RETURN/ESCAPE/KIND_EXACT=1）+ 全部会话/候选/混打/predict 方法 | ✅ 接口一致（JNI fd ↔ NAPI Uint8Array，平台必然差异）|
| `engine/Lexicons.kt` ↔ `engine/Lexicons.ets` | generation 竞态防护/release/shutdown/loadJapanese + pinyin addJapaneseWord（中日混打）| ✅ 逻辑等价（后台线程 ↔ async/await，UTF-8 TextDecoder 修 mojibake）|

> 平台能力差异（无法补齐）：按键音效（无系统等价物，需 AudioRenderer+素材）、高对比度
> 检测、系统深色切换监听、内存等级监听——均无 Harmony 等价 API，已在正文记录。JNI
> `lexiconFromFd`（内存映射）↔ NAPI `lexiconCreateFromBase`（Uint8Array 整块读入）为
> 平台传输方式差异，功能等价。

---

## 当前状态与下一步（round 42, 2026-11-15）

### 环境就绪（round 41-42 打通）

- ✅ **Android 真机已连接**（vivo V2231A，adb）：APK 0.9.1 安装 + 默认输入法 + 永不锁屏 + 设置页/键盘截图（本地临时目录）
- ✅ **HarmonyOS 模拟器已启动**（Mate 90 Pro，HarmonyOS 7.0.1-B1，hdc `127.0.0.1:5555`）：HAP 安装 + 设置页启动 + uitest dumpLayout 验证
- ✅ **视觉能力打通**：主模型 `deepseek-v4-pro` 无 `input: image`，改用 `workflow` 起子 agent `{ provider: "volcai", model: "qwen3.8-max" }`（火山网关，支持视觉），成功读出 Android 22 项设置清单 + 逐项 diff

### 设置页面与 Android 0.9.1 对齐（round 40-42 完成）

- ✅ Prefs.ets 新增 6 字段（keyPopups/hapticStrength/keySound/keySoundVolume/keyboardHeight/effects）+ hapticStrength 接入 vibrator 时长分档
- ✅ SettingsPage.ets 补齐候选栏预览/视觉特效/键盘高度/键盘位置/按键气泡/振动强度/按键声/音效音量，版本 0.8.0→0.9.1
- ✅ 措辞精确对齐 strings.xml（喵扑/日本語/输入方式/中文/色调/造型/色系/标准/通透/海盐蓝/鼠尾草绿/雾紫/琥珀蜜/米米莫与莫莫/节日装扮）
- ✅ 外观 section 顺序重排 + 新增"键盘位置=贴底"
- ✅ uitest dumpLayout 实测全部措辞与 Android 一致

### 关键平台限制发现（round 42）

- ❌ **模拟器软键盘无法渲染**：hilog 显示 `createPanel failed: {"code":1}`，根因 `window life cycle exception ... windowName: softKeyboard1, windowType: 2105 ... vsync station inner error, retCode: 1001`。这是模拟器软键盘 window（InputMethodExtensionAbility 的 panel）的 vsync 渲染限制，非喵扑代码 bug。输入法逻辑正确（`inputStart → keyboardShow → createPanel begin` 全链路正常触发），仅 panel 创建阶段 vsync 失败。
- ⚠️ **软键盘端到端验证需 HarmonyOS 真机**（当前仅 Android 真机，无 HarmonyOS 真机）。

### 关键功能 bug 修复（round 42，用户反馈「发送/退格不对」）

- 🔴 **删除方向颠倒（重大 bug，已修）**：HarmonyOS 输入法框架的方向命名与 Android **相反**——`deleteForward` 删光标**前**、`deleteBackward` 删光标**后**（SDK d.ts 注释 + metasequoiaime/msime PR #6272 真机实测双证据，[PR #6272](https://github.com/metasequoiaime/msime/pull/6272)）。旧代码按 Android 习惯调 `deleteBackwardSync` 退格，实际删的是光标后 → 退格删不掉已上屏文字。已修：`deleteBackward(count)` 私有方法改调 `deleteForwardSync(count)`；`onDelete` 光标前为空时改调 `deleteBackwardSync(1)`（Delete 键语义）。
- 🔴 **回车 NEWLINE 分支缺失（已修）**：`editorAction()` 旧逻辑「非 UNSPECIFIED 就 sendKeyFunction(1)」，导致 `ENTER_KEY_TYPE_NEWLINE` 类型的输入框误触发 onSubmit 而非换行，与 `returnTitle()`（NEWLINE 归「换行」）不一致。已修：UNSPECIFIED + NEWLINE 都走 `commit('\n')`，其余（SEND/SEARCH/GO/DONE/NEXT/PREVIOUS）走 `sendKeyFunction(1)`。
- 🟡 **onDelete 选中文本删除**：Android 有 `getSelectedText`→`commitText("",1)` 显式删选区；HarmonyOS 无 getSelectedText API，改用 `selectionChange` 回调跟踪 `hasSelection` 字段（已加），onDelete 待接入删选区逻辑。

### 行为接入完成（round 42-44）

- ✅ **keyPopups（按键气泡）**：Look 新增 `keyPopups` 字段，`applyLook()` 传 `prefs.keyPopups`，`KeyboardTouchHost.showBalloon` 经公开方法 `keyPopupsEnabled()` 判断，关闭时不再弹预览气泡。编译通过。
- ✅ **keyboardHeight（键盘高度）**：Look 新增 `keyboardHeight` + `heightScale` getter（short 0.88 / standard 1.0 / tall 1.12）；`resizePanel()` 缩放 keysDp；`MeowpuutKeyboard.rebuild()` 对 natural keyHeight 应用 scale，`fitKeysToPanel` 再按 panel 实高撑满，panel 与键盘绘制保持一致缩放。编译通过。
- ✅ **effects（视觉特效，round 44）**：Look 新增 `effects` 字段 + `effectAlphaScale`（extreme=0.82）+ `leanDuration`（lightweight=140ms / 其余 320ms）。`glassFill()` 对 alpha 应用 `effectAlphaScale`（极致更通透）；`stepLean()` 用 `leanDuration`（轻量减动效）。`applyLook()` 传 `prefs.effects`。编译通过。
- ✅ **onDelete 选区删除（round 42 已完成）**：composing→backspace；有 predictions→清空；`hasSelection`（selectionChange 回调跟踪）→`deleteBackward(1)` 删选区；光标前空→`deleteBackwardSync`（删光标后=Delete 键）；否则删光标前（退格）。对照 Android `getSelectedText→commitText("",1)` 语义。

### 剩余待办

1. **软键盘端到端 + 视觉对比**：待 HarmonyOS 真机（模拟器 vsync 限制）。
2. **按键音效真机验证**：SoundPool 播放已接入（见 round 45），但模拟器无声卡无法验证出声，需真机确认。
3. **effects 精确数值视觉精修**：extreme 的 alpha 系数 0.82、lightweight 的 140ms 为估算值（Android 数值被 R8 混淆），待真机视觉对比微调。
4. **九键拼音输入模式**：APK 0.9.1 的输入方式确认为 4 档（注音/全键拼音/九键拼音/日本語，豆包 seed 点击子页面核实），「五声」非输入方式选项。九键拼音需新增 InputMode 枚举 + 九键键盘布局（3×3 数字键）+ 词库映射；Rust 核心（meowpuut-core session.rs key()）只接受 a-z + 声调 1-5，**不理解数字串 2-9**，需核心改造 T9 索引，属重大输入引擎扩展（本轮仅把「拼音」改名「全键拼音」对齐显示）。

---

## round 45：按键声播放功能落地 + 九键拼音深度核实

### 九键拼音深度核实（豆包 seed 点击「输入方式」子页面）

- ✅ **确认为 4 档**（非 3 档）：注音 / 全键拼音（当前选中）/ 九键拼音 / 日本語。「五声」不在输入方式选项里（是注音内部变体）。
- 🔴 **Rust 核心不支持数字串**：`session.rs key()` 拼音分支只接受 `b'a'..=b'z'` + 声调 `1-5` + `'`，**完全不理解九键的数字 2-9**。九键拼音需要核心加 T9 索引（数字串→拼音序列模糊匹配），属重大核心改造，本轮不实施。
- ✅ APK assets/key-sounds 的 `penta` 目录有 key0-1/2 … key5-1/2.wav（九键数字键音效），印证九键拼音存在。

### 按键声播放（round 45 完成，功能落地）

- ✅ **新建 `engine/KeySounds.ets`**：封装 `@ohos.multimedia.media` SoundPool，`getRawFdSync` 加载 WAV，`play(kind)` 按 keySound 档位 + 键类型 + 随机变体播放，音量由 keySoundVolume 驱动。
- ✅ **5 档映射**：system→glass、xylophone→marimba、felt→felt、water→water、overtone→harmonic。
- ✅ **资源搬运**：APK assets/key-sounds 的 5 套 × 14 个 = 70 个 WAV 复制到 Harmony rawfile/key-sounds/（排除 penta 九键专用目录）。
- ✅ **接入点**：`keyFeedback(kind)` 里 keySound≠system 时播 KEY/DELETE/SPACE/RETURN 音效；`onCandidate()` 播 PICK 音效。`kindToSound()` 做 kind→音效分类映射。
- ✅ 编译通过 + 模拟器无崩溃；SoundPool 创建失败静默（不影响输入）。
- ⏳ 模拟器无声卡，出声待真机验证。

---

## round 46：候选栏预览美术对齐（真实猫咪贴图 + 高亮 pill + chevron）

### 候选栏预览（BarPreview）从 emoji 占位升级为真实渲染

对照豆包 seed 精确读出的 Android BarPreview 视觉规格（外浅灰白 #EEF0F2 + 内近白 #F4F4F6 双层圆角条、左黑猫米米莫金黄眼、右暹罗猫莫莫浅蓝眼、候选词「你好」暗酒红 pill 白字、「您好」「你好呀」深近黑、最右端 ⌄ chevron）：

- ✅ **真实猫咪贴图**：`barPreview()` 改用 `cats/mimimo_edge_peek.png`（左黑猫）+ `cats/momo_edge_peek.png`（右暹罗猫），`loadPreviewCats()` 在 aboutToAppear 解码成 PixelMap（`@State leftCat/rightCat`），不再用 emoji 🐱。
- ✅ **候选词选中态**：「你好」改为 `accent()` 色 pill + 白字（`Look.accent` = palettePill 第二色，ROSE 下 ≈ #946D70）；「您好」「你好呀」深近黑 #171415（原为灰 #6E6E73）。
- ✅ **双层圆角结构**：外层 #EEF0F2 大圆角 + 内层 #F4F4F6 候选条，与 Android 一致。
- ✅ **展开箭头 ⌄**：右猫正下方深色 chevron（对齐 Android「最右端暹罗猫下方」）。
- ✅ 编译通过 + 模拟器截图经豆包 seed 双轮核实：两只猫渲染正确（黑猫金黄眼 / 暹罗猫浅蓝眼）、「你好」豆沙 pill 白字、「您好」「你好呀」黑字、⌄ 箭头均在。

### 软键盘 vsync 限制复确认

- 🔴 有窗口 emulator（PID 24340）重启后 `createPanel failed` 仍在，底层仍是 `Fail to init vsync receiver error 50401000` + `softKeyboard1 windowType 2105 vsync station inner error retCode 1001`，属模拟器环境限制，非代码 bug。软键盘端到端仍需 HarmonyOS 真机。

---

## round 47：按键声 8 档 + 自定义音效音量只读对齐（关键修正）

### 重大发现：按键声是 8 档，不是 5 档（arsc 提取曾遗漏 3 档）

通过 Android 真机 uiautomator 点开「按键声」下拉，拿到**权威 8 档**（此前 arsc UTF-8 正则提取遗漏了关闭/玻璃/五声）：

1. 关闭（off）
2. 系统（system）
3. 水滴（water）
4. 木琴（xylophone/marimba）
5. 玻璃（glass）
6. 毛毡（felt）
7. 五声（penta）
8. 泛音（overtone/harmonic）

与 APK assets/key-sounds 的 6 个音效集目录（felt/glass/harmonic/marimba/penta/water）+ 系统 + 关闭**完全对应**（「五声」= penta 九键数字键音效集）。

### 自定义音效音量：只读「100%」占位，非滑块

- 🔴 Android 真机 dump 确认：「自定义音效音量」行是 `clickable=false` 的静态 TextView「100%」，**始终显示、不可调**；点击无任何反应。这是 APK 0.9.1 的占位（音量功能未真正实现 slider）。

### Harmony 修正（round 47 完成）

- ✅ `Prefs.keySound` 合法值扩展：off/system/water/xylophone/glass/felt/penta/overtone。
- ✅ `SettingsPage` 按键声 `rowSelect` 改为 8 档，顺序严格对齐 Android（关闭/系统/水滴/木琴/玻璃/毛毡/五声/泛音）。
- ✅ 「自定义音效音量」由可调 slider 改为只读 `rowReadOnly('自定义音效音量','100%')`，始终显示（原 keySound≠system 才显示的条件删除）。
- ✅ `KeySounds.ets`：`SET_DIRS` 补 glass/penta/water；`off` 档 `disabled` 静音；`penta` 档普通键音效用 key0-key5 数字键（九键拼音音色）。penta 22 个 WAV 复制进 rawfile。
- ✅ `MeowpuutAbility` 音效播放判断改为 `keySound !== 'system' && keySound !== 'off'`。
- ✅ 编译通过 + 模拟器 dump + 豆包 seed 截图双轮核实：8 档下拉顺序/选中态正确、「自定义音效音量 100%」只读无滑块，与 Android 完全一致。

### 完整字段逐项核对（round 47 收尾）

从头到尾滚动 Android 真机设置页 dump（顶部 19 项 + 中部 15 项 + 底部），逐字对照 Harmony，确认**全部文字字段已对齐**：

- ✅ 顶部：喵扑 Meowpuut / 添加键盘 / 当前使用的键盘是喵扑。/ 打开键盘设置 / 切换键盘 / 输入 / 输入方式(全键拼音) / 中文(简体) / 连摸米米莫五下…说明 / 试打 / 在这里试打 / 外观 / 视觉特效 / 轻量减少动效…说明
- ✅ 外观：视觉特效 / 键盘高度 / 键盘位置 / 造型 / 色调 / 色系 / 玻璃强度 / 米米莫与莫莫 / 节日装扮 / 节日期间…说明
- ✅ 按键反馈：按键气泡 / 振动 / 振动强度 / 按键声 / 自定义音效音量
- ✅ 候选栏预览卡片：无「候选栏预览」标签（豆包 seed 放大核实，仅「外观」section 标题在上方），与 Harmony 的 barPreview（无标签纯卡片）一致
- ✅ 键盘位置「悬浮」：Android 真机选「悬浮」后仍显示「贴底」，且无「移动悬浮键盘/将键盘贴底」按钮（arsc 里这些是未显示的占位/死代码）；Harmony 的悬浮 placeholder 与 Android 实际行为一致
- ✅ arsc 里「完整」「移动悬浮键盘」「拖动键盘握柄即可移动。」「将键盘贴底」「九键拼音键盘预览」均为**未显示的条件性字符串**（分别对应悬浮键盘死代码 / 九键拼音），不需在设置页主界面显示

---

## round 48：交互形式对齐（视觉特效 SeekBar + 音量禁用 SeekBar）

### 重大发现：视觉特效/振动强度是 SeekBar 滑块，自定义音效音量是禁用 SeekBar

通过 Android 真机 uiautomator dump 精确读出各组件的**交互形式**（此前只对齐了文字值，未核对控件类型）：

- ✅ **视觉特效**：`SeekBar`（content-desc="视觉特效"，3 档 轻量/标准/极致）—— Harmony 原为 `rowSelect` 下拉，已改为 3 档 `rowSlider`。
- ✅ **振动强度**：`SeekBar`（content-desc="振动强度"，3 档）—— Harmony 已是 `rowSlider`，对齐。
- ✅ **键盘高度/键盘位置/按键声**：`LinearLayout` 导航行（content-desc="label, value"，clickable=true，› chevron → 弹对话框）—— Harmony 用 ArkUI `Select` 下拉，形式不同但功能等价（选项值与顺序已严格对齐）。
- ✅ **自定义音效音量**：`SeekBar` 且 **`enabled=false`**（禁用占位，值 100）—— 此前误判为「只读静态文本」，实为禁用滑块。Harmony 由 `rowReadOnly` 纯文本改为 `rowSliderDisabled`（`.enabled(false)` + `selectedColor/trackColor/blockColor` 置灰）。

### Harmony 修正（round 48 完成）

- ✅ 视觉特效：`rowSelect` → `rowSlider('视觉特效', 轻量/标准/极致, 0..2)`。
- ✅ 自定义音效音量：`rowReadOnly` → `rowSliderDisabled`（`.enabled(false)` + 灰色 `#C7C7CC`/`#E5E5EA` 配色，视觉呈现灰色禁用态）。
- ✅ 编译通过 + 模拟器 dump（Slider type / enabled=false 确认）+ 豆包 seed 截图核实：振动强度蓝轨白柄启用态、自定义音效音量灰轨灰柄禁用态，与 Android 一致。

---

## round 49：振动开关 → 振动强度的联动（禁用态）

### 发现：振动开关关闭时，振动强度 SeekBar 变禁用

Android 真机实测：关闭「振动」Switch 后，「振动强度」SeekBar 的 `enabled` 从 true → **false**（置灰禁用）。这是 Android 的开关→滑块联动行为。

### Harmony 修正（round 49 完成）

- ✅ 首次尝试用 `rowSlider(..., enabled: this.haptics)` 传参方式，但 ArkUI `@Builder` 参数为值快照、不随 @State 刷新（dump 确认 enabled 仍为 true），联动失效。
- ✅ 改为内联 `@Builder hapticStrengthRow()`，**直接在 builder 内引用 `this.haptics`/`this.hapticStrength`**（不通过参数），建立响应式依赖：
  - `.enabled(this.haptics)` + 颜色联动（`selectedColor`/`blockColor`/值文字色随 `this.haptics` 蓝↔灰切换）
- ✅ 编译通过 + 模拟器 dump 确认：关闭振动后振动强度 Slider `enabled=false`；豆包 seed 截图核实灰色禁用态与自定义音效音量一致；恢复振动 ON 后滑块回蓝色启用态。

---

## round 50：色调深色占位确认（设置页不随色调变深色）

### 发现：Android 0.9.1「色调=深色」在设置页是占位，页面仍浅色

Android 真机实测：把「色调」切到「深色」后，设置页**整体仍是浅奶油米白背景**（页面背景 ≈#F6EFE3、卡片 ≈#FCFAF6、开关仍藕粉），候选栏预览卡片与文字无任何深色变化——「色调」选项只标注值、不驱动设置页深色渲染。

### 结论

- ✅ **「色调」仅影响软键盘本身的深浅色**（键盘渲染层），不影响设置页 Activity。Harmony 的 `Look.dark` 字段已定义（供键盘用），设置页无需深色模式。
- ✅ Harmony 的 barPreview 候选栏预览卡片保持固定浅色（外层 #EEF0F2 + 内层 #F4F4F6），与 Android 实际行为一致，无需随「色调/玻璃强度」变深或变透明。
- ✅ 候选栏预览唯一的实时联动是「色系」→ pill 色（`accent()` 随 palette）与「造型」→ 猫姿态，Harmony 已实现。
- 补充核实：Android 四行「造型/色调/色系/玻璃强度」均为导航行（content-desc="label, value" + › 弹对话框），Harmony 用内联 Select 下拉，功能等价（选项值/顺序已严格对齐，见 round 48）。

---

## round 51：顶部品牌标题 + 简体默认值对齐

### 顶部标题：单行「喵扑 Meowpuut」大标题

- 🔴 Android 顶部只有一个左对齐大标题「喵扑 Meowpuut」（TextView bounds [48,162][1032,291]，无「设置」导航标题）。
- ✅ Harmony 原为「设置」TitleBar + 居中「喵扑」+「Meowpuut 输入法」三处冗余，修正为：Navigation `.title('喵扑 Meowpuut')` + `.titleMode(Full)`（左对齐大标题），并移除 Column 里居中的品牌 Text。结果：顶部只一个「喵扑 Meowpuut」，无「设置」、无重复（豆包 seed 截图核实）。

### 输入方式相关发现（APK 0.9.1 fresh 默认值实测）

通过 Android 真机 `pm clear` 拿到 APK 0.9.1 **fresh 默认值**：

- 🔴 **输入方式 fresh 默认 = 「日本語」**（4 档：注音/全键拼音/九键拼音/日本語，日本語 checked=true）。反直觉（中文输入法默认日文），疑为 APK 0.9.1 的 fallback/bug（repo 源码 `InputMode.of(null)` fallback 到 ZHUYIN）。**决定不对齐这个反直觉默认**（Harmony 保留「注音」默认），但记录差异。
- 🔴 **中文 fresh 默认 = 「简体」**（simplified=true），repo 源码 `getBoolean(SIMPLIFIED, false)` 默认 false（繁體），APK 0.9.1 已改默认值为简体。
- ✅ **「简体」默认值已对齐**：Harmony `Prefs.simplified` 与 `@State simplified` 默认 false→true，模拟器核实「中文=简体」。
- 📌 **九键拼音仍是核心级缺口**：APK 输入方式 4 档含「九键拼音」，Harmony 只有 3 档（注音/全键拼音/日本語）。九键拼音需 Rust core T9 索引 + 3×4 数字键盘布局 + 候选生成（major engine change，继续 defer）。

---

## round 52：候选栏预览随简繁切换（第 2 候选「您好」↔「妳好」）

### 发现并修正：候选栏预览的简繁联动遗漏

- 🔴 Android `BarPreview.show()` 的 samples 随 `prefs.simplified` 切换：简体 `["你好","您好","你好呀","拟好"]`，繁体 `["你好","妳好","你好呀","擬好"]`。实测 APK 0.9.1 候选栏只渲染前 3 个（你好/您好/你好呀，第 4 个「拟好」被截断不显示），且简体态第二候选=「您好」、繁体态第二候选=「妳好」（豆包 seed 双态截图核实）。
- ✅ **已修正**：Harmony `barPreview()` 第二候选由硬编码「您好」改为 `this.simplified ? '您好' : '妳好'`。模拟器切繁体实测：dump 中「您好」消失、「妳好」出现；豆包 seed 截图核实候选栏显示「你好 / 妳好 / 你好呀」、中文行=繁體。
- ✅ 候选数量维持 3 个（你好/您好|妳好/你好呀），与 APK 实测一致（第 4 个「拟好」不显示）。
- ✅ 「试打」section 结构核对：Android 为 `EditText`（clickable/focusable=true，真输入框），Harmony 为 `TextArea`（同样可聚焦输入框），结构对齐；完整打字验证依赖软键盘渲染（真机，见 round 49 环境限制）。

---

## round 53-54：候选栏预览内层条随「造型」变化（胶囊/波浪/云朵）

### 发现并修正：内层候选条玻璃形状随造型切换

- 🔴 Android 候选栏预览的内层白条形状随「造型」变化（豆包 seed 双态截图核实）：胶囊=直边圆角矩形；波浪=正弦波浪丝带（上下边同相起伏）；云朵=云朵形（上缘 3 个圆润凸起）。选中「你好」pill 始终是普通圆角胶囊，**不随造型变**；外层衬底始终大圆角矩形，不随造型变；两只猫姿态一致但大小/位置随造型微调（波浪=猫更大、内收、爪搭浪尖）。
- ✅ **已修正**：Harmony `barPreview()` 内层候选条由固定 `.borderRadius(14)` 改为 `Stack` + `Polygon`，用 `traceOutline(this.shape, box, 0)`（GlassOutline，与键盘候选玻璃同一数学）生成玻璃轮廓顶点，`.fill('#FFF4F4F6')`。内层候选条高对齐键盘候选栏 `glassHeight=46vp`（原 36vp 太小导致波浪幅度仅 2.3vp 不可见）。
- ✅ 模拟器实测（豆包 seed 像素级核实）：胶囊=直边；波浪=上下边正弦起伏（峰谷约 8vp，肉眼可见，与 Android「波浪丝带」一致）；云朵=上缘 3 圆凸（峰谷 12-22px）。
- 📌 猫位置暂未随造型微调（波浪/云朵下猫仍贴端，非「内收搭浪尖」）；因波浪幅度小、猫姿态一致，视觉差异微弱，待 Android 真机恢复后精确对照再补。

---

## round 55：第三方授权样式对齐 + 移除版本号冗余

### 发现并修正：第三方授权 + 版本号

- 🔴 Android 底部（豆包 seed 读 android_settings_bottom/final 截图核实）：**「第三方授权」是卡片外的玫瑰藕粉纯文字链接**（无按钮背景、无 chevron、无分隔线），其下**无版本号**（页面属 App 的最后元素即「第三方授权」）。
- ✅ **已修正**：Harmony 的 `Button('第三方授权')` 改为 `Text('第三方授权').fontColor(this.accent())` 纯文字链接；移除「版本 0.9.1」冗余 Text。模拟器实测（豆包 seed 像素取样）：「第三方授权」为藕粉 #957076 纯文字、无背景无箭头，下方无版本号，与 Android 一致。
- ✅ 附带确认：Android `SettingsActivity.kt` 源码 L143-146 的「第三方授权」也是 `Button` + `setText(licenses)`（无 section 标题、无版本号），Harmony 对齐正确。

---

## round 56：输入方式补「九键拼音」选项（显示层对齐 + 引擎降级）

### 发现并修正：输入方式下拉框缺「九键拼音」

- 🔴 Android APK 0.9.1 输入方式 dropdown 有 **4 个选项**，顺序：**注音 → 全键拼音 → 九键拼音 → 日本語**（豆包 seed 读 android_inputmode_sub.png 逐字核实；arsc 简体「九键拼音」/繁体「九鍵拼音」）。Harmony 原仅 3 个（注音/全键拼音/日本語），缺「九键拼音」。
- ✅ **已修正（显示层）**：`Types.ets` 新增 `InputMode.PINYIN9 = 'pinyin9'` + `inputModeOf` 分支；`SettingsPage` 输入方式 Select 扩为 4 项，顺序对齐，写入 `prefs.mode=PINYIN9`。模拟器实测：dropdown 出现「九键拼音」第 3 位；选中后 value=九键拼音；`aa force-stop` 后重启设置页仍显示九键拼音（设置页进程 prefs 独立持久化，不跳回）。已恢复默认「注音」。
- 📌 **引擎降级（诚实标注）**：九键拼音的 T9 引擎（数字序列→无音调拼音展开→词典通配查询）与 3×4 数字键盘、penta 音效、第 4 个 subtype 均未实现。当前选择「九键拼音」后：subtype 映射到 `MeowpuutPinyin`（IME 进程 `modeOfSubtype` 返回 PINYIN，跑全键拼音键盘/候选）；`Composer` 对 PINYIN9 做了防御性降级到 `typePinyin` 路径（实际 IME 进程收不到 PINYIN9，该分支暂不触发）。**键盘实际=全键拼音，非 3×4 九宫格**——这是有意的「显示对齐、功能暂降级」，待实现真正 T9 引擎后切换。
- 📌 **完整九键拼音待实现清单**（Rust core + FFI + UI）：① core 加数字→拼音 T9 展开（2=abc…9=wxyz 笛卡尔积）+ 无音调通配词典查询；② FFI 暴露 PINYIN9 候选接口；③ Keys.ets 加 3×4 数字键盘布局（1-9/*/0/#）；④ Composer/Ability 完整 PINYIN9 分支（非降级）；⑤ `input_method_config.json` 注册第 4 个 subtype `MeowpuutPinyin9`；⑥ penta 音效（key0-key5 wav 已在 Android assets，Harmony 需同步 resource）。

---

## round 44：顶部文案 + section 顺序对齐 + effects 行为接入

### 顶部文案与 section 顺序精确对齐（对照 Android SettingsActivity.kt 源码 + APK 0.9.1）

- ✅ section 标题「首次使用」→「添加键盘」（setup_title）
- ✅ 按钮「打开输入法设置」→「打开键盘设置」（setup_open_settings）
- ✅ 移除多余的「1/2/3 启用步骤」说明（Android 无此内容，仅 status 文字 + 2 按钮）
- ✅ section 顺序对齐 APK：添加键盘 → 输入 → 试打 → 外观（原 Harmony 把试打排在输入前，已移正）
- ✅ 试打占位「在这里试打，验证输入法…」→「在这里试打」（try_hint）；补「试打」section 标题（try_title）
- ✅ 「中文」由 Switch 改为二选一 Select「繁體/简体」（对齐 Android choice(script, 繁體/简体)，顺序也对齐：繁體在前）
- ✅ 「拼音」→「全键拼音」（对齐 arsc 的 mode 显示名）

### effects 视觉特效行为接入（round 44 完成）

- ✅ Look 新增 `effects` 字段 + `effectAlphaScale`（extreme=0.82）+ `leanDuration`（lightweight=140ms / 其余 320ms）
- ✅ `glassFill()` 对 alpha 应用 `effectAlphaScale`（极致更通透）；`stepLean()` 用 `leanDuration`（轻量减动效）
- ✅ `applyLook()` 传 `prefs.effects`；编译通过 + 模拟器无崩溃

---

## round 43：权威基线重建 + 设置项精确对齐（关键修正）

### 重大发现：之前 qwen3.8-max 的「22 项清单」存在幻觉，已用 resources.arsc 重建权威基线

- 🔴 **证据链**：仓库源码 `Android/app/src/main/res/values-zh-rCN/strings.xml`（60 行）+ `Prefs.kt`（9 字段）里**都没有** effects/keyboardHeight/keyboardPosition/keyPopups/hapticStrength/keySound/keySoundVolume；但 APK 0.9.1 的 `resources.arsc`（11KB）里这些字符串**全部存在**（用 UTF-8 CJK 正则提取到 154 个唯一中文串）。→ 结论：APK 0.9.1 是比 `harmonyOS` 分支 Android 源码更新的 release，新增设置项实现在仓库外。
- ✅ **权威清单（arsc 提取 + 豆包 seed 双重核实）**，按 section 顺序：
  1. 添加键盘：当前使用的键盘是喵扑。/ 打开键盘设置 / 切换键盘
  2. 输入：输入方式（注音/全键拼音/九键拼音/日本語）、中文（简体/繁體）、连摸米米莫五下切输入方式…（说明）
  3. 试打：在这里试打
  4. 外观：候选栏预览 → 视觉特效（轻量/标准/极致）→ 键盘高度（较矮/标准/较高）→ 键盘位置（贴底/悬浮）→ 造型（胶囊/波浪/云朵）→ 色调（跟随系统/浅色/深色）→ 色系（6 色）→ 玻璃强度（柔和/标准/通透）→ 米米莫与莫莫 → 节日装扮 + 说明
  5. 按键反馈：按键气泡（开关）→ 振动（开关）→ 振动强度（轻柔/标准/强，滑块）→ 按键声（系统/木琴/毛毡/水滴/泛音，下拉）→ 自定义音效音量（0-100%，滑块）
  6. 第三方授权
- ❌ **修正之前误判**：「键盘高度」确实存在（较矮/标准/较高），不是幻觉；「键盘位置」是两档（贴底/悬浮），不是只读「贴底」；「按键声」是 5 档下拉，不是布尔。

### 设置项措辞精确对齐（round 43 完成）

- ✅ 键盘高度选项：`['矮','标准','高']` → `['较矮','标准','较高']`
- ✅ 键盘位置：只读「贴底」→ 两档 `['贴底','悬浮']`
- ✅ 振动强度：`弱/中/强` → `轻柔/标准/强`（Slider 三档，默认 strong）
- ✅ 按键声：`['系统','关闭','自定义']` → `['系统','木琴','毛毡','水滴','泛音']`（Prefs.keySound 校验同步改为 xylophone/felt/water/overtone）
- ✅ 视觉特效/玻璃强度/色系/造型/色调 均已对齐（前几轮）
- 🟡 视觉特效默认值：Harmony=standard vs Android 视觉读到 lightweight，因仓库源码无 effects 字段无法确认出厂默认，暂留 standard（三档已对齐）。

---

## round 57：设置页「功能链路」全量自检（存值 → 运行时消费）

用户指出「设置页不仅 UX 要对齐，功能也要拉齐」。本轮对每个偏好设置做
「Prefs 存值 → 键盘运行时消费」的逐链路核对，找出并修复「存了值但没消费」的断点。

### 修复的断点（本轮）

1. **振动强度 `hapticStrength` 振幅分档失效**（`MeowpuutAbility.vibrateBrief`）：
   - 原实现 `vibrateBrief(ms, intensity, tag)` 里 `intensity`/`tag` 参数完全被忽略，
     只调用 `vibrator.vibrate(ms)`，三档强度仅靠 8/12/16ms 时长差异，用户几乎无感。
   - ✅ 已改为 `vibrator.startVibration({type:'preset', effectId, count:1, intensity}, {usage:'physicalFeedback'})`：
     light→`haptic.effect.soft`(intensity 40)、medium→`haptic.effect.hard`(70)、strong→`haptic.effect.sharp`(100)，
     用 `isSupportEffectSync` 判支持、不支持回退 `vibrate(ms)`，全程 try/catch 静默降级。
     对照 Android `MeowpuutIME` 的 hapticStrength 三档触感差异。
2. **节日装扮开关 `prefs.festivals` 未接入**（`MeowpuutAbility.applyLook`）：
   - 原 `this.festivalWardrobe` 硬编码 `new FestivalWardrobe(true)`，`Festivals.theme` 的
     `if (!wardrobe.on) return null` 永远读到 true → 关闭「节日装扮」后节日主题仍生效。
   - ✅ 已在 `applyLook()` 调用前同步 `this.festivalWardrobe.on = this.prefs.festivals`。
3. **`keyFeedback` 空 if 分支（死代码）**：`if (!this.prefs.haptics) { /* 注释 */ }` 空块，
   误导性结构。已清理，音效/震动独立判断（音效不依赖震动开关）。
4. **按键声首次播放静音**（`KeySounds`）：
   - 原 `loadId` 异步 `pool.load().then(...)` 首次返回 0（`play` 静音），第二次按键才响。
   - ✅ 新增 `preload()`：`configure()` 切档与 `init()` 的 SoundPool 就绪回调里，
     预加载当前音效集全部 WAV（key-{1..4}/delete-{1..3}/space-{1..3}/return-1/pick-{1..3}，
     penta 档预载 key0-key5 各 2 变体），消除首次按键静音。

### 确认已接通、无需修改（避免误报）

- ✅ **键盘高度 `keyboardHeight`**：`Look.heightScale`(short 0.88/tall 1.12) → `resizePanel`
  L343 `scaledKeys = keysDp * heightScale` → `panel.resize`；`MeowpuutKeyboard.fitKeysToPanel`
  再按实际 panel 高度撑满键高，两套计算一致缩放。
- ✅ **视觉特效 `effects`**：`Look.effectAlphaScale`(extreme 0.82) → `glassFill` alpha；
  `Look.leanDuration`(lightweight 140ms/其余 320ms) → `stepLean` 动效时长。
- ✅ **按键气泡 `keyPopups`**：`Look.keyPopups` → `KeyboardState.keyboard` → `keyPopupsEnabled()`
  → `showBalloon` L121 判断 → `drawBalloon` 绘制。
- ✅ **按键声 8 档 `keySound` + 音量 `keySoundVolume`**：`SET_DIRS`(system→glass/water/
  xylophone→marimba/glass/felt/penta/overtone→harmonic，off=disabled) + `volume`→`leftVolume/rightVolume`。
- ✅ **造型/色调/色系/玻璃强度**：`Look` getters → `Painting`(tint/rim/glassFill 用 strength)。
- ✅ **米米莫与莫莫 `cats`**：`Look.cats` → `CandidateRegionLayout.cats` → `drawCats`/`CatSeats`。
- ✅ **中文简繁 `simplified`**：`applyLook`/`Words.pick`/候选文案三处消费。

### 遗留（诚实标注：真机/参考依赖，非代码可补）

1. **键盘位置「悬浮」档**：`SettingsPage` 的 onSelect 回调为空（固定「贴底」）。
   HarmonyOS IME 扩展的悬浮窗口能力 + Android 悬浮行为参考均不可得（repo 源码无此功能，
   APK 0.9.1 新增，与九键拼音同源）。
2. **九键拼音引擎**：core T9 展开 / FFI / 3×4 数字键盘 / 第 4 个 subtype 未实现
   （penta 音效 key0-key5 wav 已就位，`KeySounds` 的 penta 档已能播放）。详见 round 56 清单。

### 本轮编译

三次 `assembleHap` 均 BUILD SUCCESSFUL（振动强度、节日装扮、按键声预加载三处改动各自通过）。

---

## round 58：九键拼音引擎逐层盘点（精确到文件/函数/签名的可执行清单）

用户要求「功能也要拉齐」，九键拼音是剩余最大的独立功能。本轮不盲写（无 Android 行为参考、
无真机验证会产出错误实现），而是把四层缺口盘点成**精确到函数签名**的实现清单，供真机/参考就绪后直接照着写。

### 现状确认（本轮读源码核实）

- Rust core 词典 bucket 按**无音调 bare** 索引（`lexicon.rs` L381 `buckets.key != bare`、L386 `arena.push_str(bare)`），
  故 `Lexicon::range("nihao")`（无音调）**天然命中**，九键拼音的「无音调查询」是词典原生能力，无需新通配机制。
- 但 `range()` 是**精确 bucket 匹配**（`index.bucket.get(key)` + `buckets.range(idx)`），不是前缀匹配。
  九键拼音数字序列展开后，需对每个展开 bare **逐个调用 `range()` 收集命中**（多数空命中需剪枝）。
- Session 的 pinyin 模式 `key()` 只接受 `b'a'..=b'z'`（`session.rs` L362-365），**不认数字 2-9**。
  故九键拼音**不能复用 `Session::key` 喂数字**，需要独立的数字展开层。
- FFI 现有 `mpn_session_create` + `session_fn!`/`getter_fn!` 宏（`api.rs` L241/L269/L288）。
- Harmony NAPI 桥在 `harmony/entry/src/main/cpp/napi_init.cpp` L479-501 的 `desc[]` 表 + `NativeEngine.ets` 静态方法。
- APK 0.9.1 有 JNI 方法 `nineKeySessionCreate`（从 classes.dex 提取），印证九键拼音是**独立 session**，
  但 repo 源码（旧）与 meowpuut_jni.c **均无** nineKey 实现，算法在 APK 的 .so 二进制内，需逆向才能参考。

### 第 1 层：Rust core（`crates/meowpuut-core/`）

新增 `src/nine_key.rs` 模块（`lib.rs` `pub mod nine_key;` + re-export）：

1. `pub const NINE_KEY_LETTERS: [&[u8]; 8]`（数字 2-9 → 字母）：
   `2→b"abc" 3→b"def" 4→b"ghi" 5→b"jkl" 6→b"mno" 7→b"pqrs" 8→b"tuv" 9→b"wxyz"`（T9 行业标准，无歧义）。
2. `pub fn nine_key_expand(digits: &str, out: &mut Vec<String>) -> usize`：
   数字序列→笛卡尔积展开所有 bare 字母串（如 `64`→`mg/mh/mi/ng/nh/ni/og/oh/oi`）。
   需**前缀剪枝**：逐位展开时，若当前前缀 `lexicon.range(prefix)` 为空则剪掉该分支（避免 9 位数字 3^9≈2 万条全展开）。
3. `pub fn nine_key_candidates(lexicon: &Lexicon, digits: &str, hans: bool, out: &mut DecoderScratchSoA) -> usize`：
   对每个展开 bare 前缀调 `lexicon.range()` 收集命中词，按权重排序、去重（同一词可能被多个 bare 命中），
   写进 scratch（复用 `DecodeOutputSoA`），返回候选数。
4. **音节边界（核心难点，需 Android 参考）**：数字序列切分成音节的方式（如 `64426` = `ni hao` 还是 `mi mao` 等）
   需对照 APK 0.9.1 真实候选输出校准，**不能盲写**。实现时先做「连续无边界」版本（整串展开），
   待真机参考后补音节分段/最佳路径（类似 decoder.rs 的 beam）。

### 第 2 层：FFI（`crates/meowpuut-ffi/src/api.rs`）

新增独立 session 接口（镜像 `mpn_session_*`，但内部持 `NineKeySession`）：

- `mpn_nine_key_session_create(lexicon: *const MPNLexicon) -> *mut MPNNineKeySession`
- `mpn_nine_key_session_destroy(session)`
- `mpn_nine_key_key(session, digit: c_int) -> c_int`（digit 取 2-9，展开+查词）
- `mpn_nine_key_backspace(session) -> c_int`
- `mpn_nine_key_set_simplified(session, simplified: c_int)`
- `mpn_nine_key_candidate_count / candidates / candidate_details / choose / input / preedit / take_committed`
- `mpn_nine_key_clear(session)`

（`NineKeySession` 持 `Arc<Lexicon>` + `digits: String` + 候选缓冲，可参照 `MPNSession` 结构。）

### 第 3 层：Harmony NAPI 桥（`harmony/entry/src/main/cpp/napi_init.cpp` + `NativeEngine.ets`）

- `napi_init.cpp`：在 `desc[]`（L479-501）新增 `nineKeySessionCreate/nineKeySessionDestroy/nineKeyKey/nineKeyBackspace/...`
  各 NAPI 函数，内部调 `mpn_nine_key_*`。照抄现有 `SessionCreate`（L484）/`Key`（L487）/`Candidates` 的 `FromJS`/`ToJS` 模式。
- `NativeEngine.ets`：新增对应静态方法（`nineKeySessionCreate` 等），照抄现有 `sessionCreate`（L36）/`key`（L48）写法。

### 第 4 层：Harmony UI（`entry/src/main/ets/`）

- `Composer.ets`：`type()` 的 `case InputMode.PINYIN9`（L80）从 `typePinyin` 改为真正的
  `typeNineKey`（调 `NativeEngine.nineKeyKey` 喂数字），`space/delete/choose/rebuild` 各分支同步
  改用 nine-key session（现在全是防御性降级）。
- `MeowpuutAbility.ets`：`modeOfSubtype()` 增加第 4 个 subtype → `InputMode.PINYIN9`（现映射到 PINYIN）；
  `onCreate` 里为 PINYIN9 创建 `nineKeySession`（复用 lexicon，`lexiconCreateFromBase(data, true)`）。
- `Keys.ets`：新增 3×4 数字键盘布局（`1 2 3 / 4 5 6 / 7 8 9 / * 0 #`），对照 Android 九键键盘键位；
  数字键产生 digit 输入而非字母。
- `input_method_config.json`：注册第 4 个 subtype `MeowpuutPinyin9`（subtypeId 新分配）。
- 音效：`KeySounds` 的 `penta` 档已能播放 key0-key5（round 57 预加载已覆盖 penta 12 个 wav），
  PINYIN9 模式只需把 `keySound` 默认/可选指向 penta 档即可，**音效层已就绪**。

### 依赖与风险（诚实标注）

- **音节边界算法 + 候选排序权重**：必须对照 APK 0.9.1 真实九键拼音输出校准，否则「T9 正确但候选与 Android 不一致」。
  无 Android 真机（adb 离线）→ 无法取参考输出；无 HarmonyOS 真机 → 无法端到端验证。
- **数字→字母映射 + 笛卡尔积展开 + 前缀剪枝**：行业标准、无歧义，可先写 core + doctest 单元测试（不依赖真机），
  这是唯一可安全先行的部分。若需要，可在下轮先把 `nine_key_expand` + 剪枝 + 单元测试落地，留音节边界待参考。

### 第 1 层已落地（round 58 追加）

- ✅ **新增 `crates/meowpuut-core/src/nine_key.rs`**（`lib.rs` `pub mod nine_key;`）：
  - `NINE_KEY_LETTERS`（数字 2-9 → 字母，T9 行业标准）、`nine_key_letters(digit)`
  - `expand_nine_key(digits)`：笛卡尔积展开（`"64"` → 9 个前缀 `mg/mh/mi/ng/nh/ni/og/oh/oi`）
  - `nine_key_candidates(lexicon, digits, hans, out)`：**前缀扫描**收集候选——对每个展开前缀，
    从 `lower_bound_bucket(prefix)` 顺序遍历 bucket，`key.starts_with(prefix)` 即收集该 bucket 全部词，
    按文本去重、权重降序。这是「连续无音节边界」版本；音节分段（`64426`=`ni`+`hao`）留待 Android 参考。
  - 关键修正（写代码时发现）：`Lexicon::range()` 是**精确 bucket 匹配**，不是前缀匹配——`range("ni")`
    只命中 bare=="ni" 的词，不命中 bare=="nihao"/"nide"。九键「前缀补全」必须走
    `lower_bound_bucket` + `starts_with` 顺序扫描，而非 `range()`。
- ✅ **测试**：新增 doctest（`nine_key.rs` 顶部），`cargo test -p meowpuut-core --doc` **25 passed / 0 failed**，
  包括新 doctest（`"64"` → 命中「你」「你好」）。`cargo build -p meowpuut-core` 编译通过。
- 📌 **预存环境失败（与本次无关）**：`tests/in_place_base.rs::shipped_base_in_place_equals_copy` 因
  `iOS/Generated/mimo_base.bin` 缺失而失败（需 `scripts/prepare-ios.sh` 生成），非 nine_key 改动引入。

### 剩余（第 2-4 层，待真机/参考后实现）

第 2 层 FFI（`mpn_nine_key_*`）、第 3 层 NAPI 桥、第 4 层 UI（3×4 键盘/subtype/Composer 分支）
仍按上面清单待实现；音节边界算法待 Android 参考输出校准。core 的展开+前缀收集已就绪，

### round 59：微信「回车无法发送」根因（2026-11-15，真机实证 + SDK 源码穷尽）

- **现象**：鸿蒙喵扑软键盘「发送」按钮在微信聊天里点了不发送（仅换行/字面 `\n`），硬件回车却能发送。
- **根因**（真机 HUAWEI Pura X / API26 + 本机 DevEco SDK 源码穷尽，置信度高）：
  1. 鸿蒙微信聊天框 `enterKeyType=4`（ImsaKit 日志 `pattern/enterKey:-1/4`；IME 枚举 SEND=4，对齐
     Android IME_ACTION_SEND=0x04）。
  2. **HarmonyOS 输入法框架无 `performEditorAction` 等价物**：`InputClient.sendKeyFunction(action)` 仅
     `0(无效)/1(确认键)` 两档；新增的 `sendExtendAction` 仅 `SELECT_ALL/CUT/COPY/PASTE` 剪贴板动作
     （本机 SDK d.ts L2999-3028）；无 API 可注入 KeyEvent。故输入法只能发「确认键(1)」。
  3. `sendKeyFunction(1)` → 框架路由 `SendEnterKeyFunc(SEND)`，但**微信鸿蒙聊天框是 RichEditor 多行框**，
     把「确认键→SEND」降级为「换行」，表现为字面 `\n` 而非发送。
  4. 唯一能触发发送的是**硬件回车事件透传**（`hardwareKeyEvent` 非组字时返回 false → 系统把 KeyEvent
     透传给微信窗口层处理）——此路径输入法**无法主动触发**。
- **结论**：这是**微信鸿蒙版 RichEditor 多行框 + 输入法框架 API 限制**导致，非喵扑代码缺陷。喵扑
  `editorAction()` 的 `sendKeyFunction(1)` 已是 HarmonyOS 语义正确的「确认」调用（对齐 Android
  `performEditorAction(SEND)`），对搜索框等单行场景能正确触发动作；微信是否「回车发送」取决于微信侧
  （及微信内「回车键发送消息」设置），输入法无法越权。
- **动作**：曾尝试 `SEND→commit('\n')` 插换行——已回退（多行框下换行≠发送，还会污染输入框）。
  保留 `sendKeyFunction(1)` 原逻辑 + 注释说明。并未改功能，属「确认框架限制」。
- **待跟进**：若后续鸿蒙微信更新修复 RichEditor 对 SEND 的响应，或 IME Kit 新增
  `performEditorAction` 等价 API，再回来补。可选缓解：提示用户在微信开「回车键发送消息」。
  微信实机复测只发到微信内聊天用户 `y2x` 的对话（勿污染其他聊天）。

### round 60：returnTitle() 与 Android 的 enterKeyType 差异核对（代码层，待 t2 后落地）

逐行对比 `MeowpuutAbility.ets returnTitle()` vs `MeowpuutIME.kt returnTitle()`：

| 项 | Android | 鸿蒙当前 | 一致性 |
|---|---|---|---|
| `IME_FLAG_NO_ENTER_ACTION` | 显式判断，命中直接「换行」 | 无此标志位（鸿蒙 EditorAttribute 只有 inputPattern+enterKeyType） | **平台缺口，无法实现** |
| NONE(=1) | 落入 `else -> 換行` | 落入 `default -> 換行` | ✅ 结果一致（建议补显式 case + 注释防误改） |
| UNSPECIFIED(=0) | `else -> 換行` | `default -> 換行` | ✅ 一致 |
| SEARCH/SEND/GO/DONE/NEXT | true | true | ✅ 一致 |
| PREVIOUS | false | false | ✅ 一致 |

- 结论：`returnTitle()` 行为**实质一致**（NONE/UNSPECIFIED 都正确落到「换行」）。唯一做不到的是
  `IME_FLAG_NO_ENTER_ACTION`（鸿蒙无对应标志位，非代码 bug）。
- 待办（t2 完成后统一落地，避免与 engineer 并发改同文件冲突）：给 `default` 分支补显式注释，
  说明它同时覆盖 UNSPECIFIED/NONE/NEWLINE，对齐 Android 的 `else`。

后续可直接在 FFI 层包 `nine_key_candidates`。
### round 61：sendKeyFunction 参数语义纠正（微信「回车发送」的真正症结）

**发现**：`InputMethodController::SendFunctionKey` 把参数**直接 cast 成 `EnterKeyType`** 透传给应用：

```
funcKey.SetEnterKeyType(static_cast<EnterKeyType>(functionKey));   // input_method_controller.cpp:2071
```

而 SDK 文档只写 `0: invalid key / 1: confirm key`，造成长期误解——传 `1` 会被解释成
`EnterKeyType(1) = NONE`，不是「确认键」。RichEditor 收到 NONE 后 `PerformAction(NONE)`
→ `FireOnSubmit(1)` → 无人订阅 → **退回默认动作换行**。

这解释了微信聊天框（`enterKeyType=4=SEND`）里 `sendKeyFunction(1)` 只换行不发消息。

**修正**：`editorAction()` 改为传入编辑框自己声明的 `enterKeyType`（微信=4=SEND），
失败时退回文档写明的 `1`。

| EnterKeyType（IME 侧） | 值 | 说明 |
|---|---|---|
| UNSPECIFIED | 0 | |
| NONE | 1 | ← 旧代码 sendKeyFunction(1) 实际传的是这个 |
| GO | 2 | |
| SEARCH | 3 | |
| **SEND** | **4** | 微信聊天框声明的值 |
| NEXT | 5 | |
| DONE | 6 | |
| PREVIOUS | 7 | |
| NEWLINE | 8 | |

**框架层约束（已穷尽核对，不要再找「隐藏 API」）**：
- 三方 IME 与系统 IME 公开能力面一致（`@ohos.inputMethodEngine.d.ts` / `@ohos.inputMethod.d.ts`
  均 0 处 `@systemapi`）；小艺能回车发送靠框架内部系统 IME 身份绑定
  （`RegisterProxyIme` / `isProxyIme_`），三方拿不到。
- C 侧 `OH_TextEditorProxy_SendEnterKeyFunc` 是**应用实现**的回调；
  `inputmethod_inputmethod_proxy_capi.h` 7 个导出函数中没有「发送回车键」。
- `sendExtendAction` 仅 SELECT_ALL/CUT/COPY/PASTE；`sendPrivateCommand` / ExtraConfig
  方向都是「应用→输入法」。
- 「App→IME→App 注入按键」没有公开出口；**唯一现成可行的是硬件 keyEvent 透传**
  （IME 监听 `keyEvent` 返回 `false` → 框架回转 → `RichEditorPattern::HandleOnEnter`）。
- `EditorAttribute.consumeKeyEvents`（API 26）字段已进 SDK，但公开签名缺失，需微信适配，
  现阶段不可承诺可用。

**注意**：绝不可用 `insertText('\n')` 冒充发送——RichEditor 会把 `\n` 作为真实 span 写入，
污染撤销栈与 `aboutToIMEInput`。

### round 62：删除方向 —— 退格只能删光标前

SDK `@ohos.inputMethodEngine.d.ts` 命名**反直觉**且官方文档明确：

| API | 官方文档原文 | 语义 |
|---|---|---|
| `getForwardSync(length)` | Obtains the text **before** the cursor | 取光标**前** |
| `getBackwardSync(length)` | Obtains the text **after** the cursor | 取光标**后** |
| `deleteForwardSync(length)` | Deletes the fixed-length text **before** the cursor | 删光标**前** |
| `deleteBackwardSync(length)` | Deletes the fixed-length text **after** the cursor | 删光标**后** |

**历史 bug**：`getTextBeforeCursor()` 误用 `getBackwardSync`（取到的是光标**后**的文字）。
光标在文末时取到空串 → 误判「光标前无文字」→ 走 `deleteBackwardSync(1)` 删光标后
→ 文末后面无字 → **退格删不掉最后一个字符**。已改为 `getForwardSync`。

**同源 bug**：`onDelete()` 里「光标前为空则删光标后」的 fallback 是错误设计——
退格在任何情况下都不该删光标后的字（真机曾复现 `'全球ab、我'` → `'全球ab、'`，光标后的
「我」被删）。现已移除该分支，改为 `deleteForwardSync` 兜底，失败则**不动文本**。

已核对：全文件 0 处 `deleteBackwardSync` 调用，退格路径 100% 只指向光标前。

### round 63：猫的显示 —— 不是蒙版，是玻璃裁剪

**真机现象**：候选栏两端「有猫的爪子但主体被遮蔽了显示不出来」。

**根因**：`clipOutsideGlass()` 用 `evenodd` 规则把玻璃轮廓**内部整块挖空**，只允许绘制
玻璃**外面**的部分。猫身大部分落在玻璃里 → 主体被裁掉，只剩探出玻璃边缘的爪子和边线。

**修复（纯净版）**：
1. 移除 `clipOutsideGlass` 裁剪，猫整只完整绘制；
2. 停用 `drawLightBand` 白色柔光带（避免任何叠加观感）；
3. 移除深色模式光晕叠加；
4. z 序：猫画在候选行之上、最上层。

**副作用与配套修正**（整只显示后猫相对候选栏偏小、且头顶需要空间）：
- 尺寸改为**由可用空间反解**，不写死倍数：
  `scale = (available * FILL) / ((bottom - top) * height)`，`FILL = 0.94`；
- 候选栏增高 `CAT_HEADROOM_RATIO = 0.34 × glassHeight`（相对比例，不写死像素），
  玻璃仍贴候选栏底部，多出空间全给猫头。
- **全部按比例推导**，随屏宽/字号/输入框缩放等比变化。
  验算 360/393/412/440dp 四档：猫宽 51/56/59/63dp，猫头顶部 y 均为正值（4.1~4.7），
  不切头；较原版（393dp 下 44.1dp）放大约 27%。
- 爪子对齐：`anchorY = glass.top + edge.low` 与 `scale` 无关，两只猫爪子恒贴同一底线。

### round 64：猫的行为差异（拍哪只猫、爱心阈值）

| # | 项 | Android 基准 | 修复前鸿蒙 | 修复 |
|---|---|---|---|---|
| ① | 拍哪只猫切简繁 | `CandidateBarView.kt:714-718` 拍米米莫只撒粒子、`return null`，**不计数** | `onPet` 不分猫，拍米米莫也累计 | 加 `cat === 'mimimo'` 早退 |
| ② | 爱心进度条阈值 | `:722` `if (outcome.count >= 2)` 才显示 | 吞掉阈值，第 1 下就弹 | 补回 `count >= 2` 判断 |
| ③ | 系统「移除动画」 | `areAnimatorsEnabled()`，5 处使用 | 写死 `timeScale=1` | `motionTimeScale()`：lightweight 档 → 0，不喷粒子 |
| ④ | 猫名匹配 | — | `'mimo'` vs 实际传入 `'mimimo'`，碰巧成立 | 收紧为 `'momo'` 精确匹配 |

**注**：安卓与鸿蒙**都没有**眨眼/摇尾/空闲动画——猫是静止贴图，仅在被拍（tilt/wide/tall）
与组字（lean ±2.5°）时有变换。这是安卓基线本身的设计，不该为鸿蒙额外发明动画。
8 张贴图两边 md5 完全一致，资源无缺失。

### round 65：组字原始字符可见（setPreviewText 语义纠正 + 时序修复）

**需求**：输入拼音时输入框内实时显示原始字母（如 `nihao`，带下划线组字态），选候选后
替换为汉字，与 Android `setComposingText` / `commitText` 对齐。

**上一版的根本错误**（用户反馈「做得非常差」，回退重做）：

1. 误判 `setPreviewText` 的 range 语义 —— 上一版声称「`{-1,-1}` 实测是**每次追加**而非替换」，
   于是手写 `[cursor - previewLength, cursor+1]` 的绝对下标计算。这是**错的**。
2. 在真机上靠一堆 `MeowpuutTouch` / `MeowpuutPreview` / `MeowpuutDiag` hilog 逐行猜坐标、
   猜 range、逐帧比对截图，既低效又引入大量诊断噪音污染代码。
3. `applyEdit` 时序错：先 `insertText(汉字)` 再处理预览，导致 `finishTextPreview` 把残留
   的 `nihao` 也落地，出现「你好 nihao」错乱。

**权威语义（本地 SDK `@ohos.inputMethodEngine.d.ts` 官方注释 + framework 源码 + 官方
KikaInputMethod 示例，三者交叉验证，非二手资料）**：

```
setPreviewText(text, range)：
  {start:-1, end:-1} → 替换整个预览区（官方为「更新组字」设计的语义）
  start === end       → 在 start 处插入 text
  start !== end       → 用 text 替换 [start, end) 区间
  已有预览时 range 不得超出预览区；无预览时 range 不得超出文本框
finishTextPreview()   → 预览文本「落地」（上屏为正式文本）
```

- 官方 Kika 示例 `sendKeyFunction()` 里 `sendKeyFunction` 后紧跟 `finishTextPreview()` 让预测词落地。
- framework 源码 `RangeToInner` 仅原样透传 start/end，`-1/-1` 的「替换整个预览区」语义由
  IMF 服务端解析，d.ts 官方注释即权威。

**`-1/-1` 语义的最终真相（追到 ACE 引擎源码，铁证）**：

`arkui_ace_engine` 仓库 `frameworks/core/components_ng/pattern/text_field/text_field_pattern.cpp`
+ `text_field_pattern.h` 是 `setPreviewText` 的最终执行处：

```cpp
// text_field_pattern.h
int32_t GetPreviewTextStart() const {
    return hasPreviewText_ ? previewTextStart_ : selectController_->GetCaretIndex();
}
int32_t GetPreviewTextEnd() const {
    return hasPreviewText_ ? previewTextEnd_ : selectController_->GetCaretIndex();
}
```

```cpp
// text_field_pattern.cpp  SetPreviewTextOperation()
start = (rangeStart == PREVIEW_TEXT_RANGE_DEFAULT) ? GetPreviewTextStart() : rangeStart;  // -1 → 沿用当前预览start
end   = (rangeEnd   == PREVIEW_TEXT_RANGE_DEFAULT) ? GetPreviewTextEnd()   : rangeEnd;    // -1 → 沿用当前预览end
...
contentController_->ReplaceSelectedValue(start, end, info.text);  // 用 text 替换 [start,end)
```

```cpp
// CheckPreviewTextValidate()
if (start != end && (start == -1 || end == -1)) return PREVIEW_BAD_PARAMETERS;  // 只有 {-1,-1} 合法
```

```cpp
// FinishTextPreviewOperation()
previewValue = GetPreviewTextValue();
hasPreviewText_ = false;                                  // 清除预览态
contentController_->ReplaceSelectedValue(start, end, previewValue);  // 预览内容固化为正式文本（上屏）
```

**结论（确定性）**：`{-1,-1}` 不是「替换整个预览区」的字面意思，而是「**沿用组件当前认知的预览范围**」：
- 首次（无预览，`hasPreviewText_=false`）：`GetPreviewTextStart()==GetPreviewTextEnd()==光标`，等价于「光标处插入」；
- 后续（有预览）：`start/end = 上次预览区 [start,end)`，等价于「替换上次整个预览区」。

这**彻底否定了 v4.1-flash 版「{-1,-1} 是追加不是替换」的错误结论**——ACE 源码明确走
`ReplaceSelectedValue(start, end, text)` 替换路径，绝无追加。且 `finishTextPreview()` 确认是
「预览文本固化为正式文本（上屏）」而非「收起预览」。

**修复（对齐 Android applyEdit 三分支状态机）**：

`syncComposingText(wasComposing, commitText)`：
- 组字中：`setPreviewText(preedit, {-1,-1})` 维护预览区为当前组字显示（带下划线）
- 组字结束 + commit：`setPreviewText(commit, {-1,-1})` 把预览区换成汉字，再 `finishTextPreview()` 落地
- 组字结束无 commit：`finishTextPreview()` 清掉预览

**关键对齐点 —— 组字显示的是 `preedit` 而非 `raw`**（对齐 Android `setComposingText(composer.preedit)`）：

| 模式 | 鸿蒙 `_preedit`（Composer.rebuild） | 安卓 `preedit`（Composer.kt:269/284） | 是否一致 |
|---|---|---|---|
| 拼音 | `= this.raw` | `= raw.toString()` | ✅ |
| 注音 | `= NativeEngine.preedit(session)` | `= NativeEngine.preedit(session)` | ✅ |
| 日语 | `= Romaji.reading(raw)` | （安卓日文路径不同） | ✅ |

原实现误用 `rawPreview`（= raw），注音模式下会显示原始按键序列而非带声调注音、
日语模式显示原始罗马字而非读音，与 Android 不一致。已改为 `composer.preedit`。

`applyEdit` 时序重排：
- **预览同步先于 commit**（组字结束时预览区承载「nihao → 汉字」的替换，避免残留）
- 分词（commit 非空且仍组字）：`insertText(commit)` + 预览区更新为剩余串
- `previewSupported=false`（编辑框不支持预览）时组字结束的 commit 走 `insertText` 兜底上屏
- **commit 落地责任显式化**：只有「组字结束且支持预览」这一种情况，commit 由
  `syncComposingText` 的 setPreviewText+finishTextPreview 落地（`committedViaPreview =
  wasComposing && !nowComposing && previewSupported`）；其余一切情况（分词、不支持预览、
  非组字直接 commit）都走 `insertText`，保证汉字绝不静默丢失。

**退格删空的关键修正**（ACE 源码暴露的隐患）：

`finishTextPreview()` 在 ACE 层的实现（`FinishTextPreviewOperation`）是「把预览文本**固化**为正式文本」
（`hasPreviewText_=false` + `ReplaceSelectedValue(start,end,previewValue)`），**不是**「丢弃预览」。

安卓退格删空走 `commitText("", 1)` = **清空** composing（丢弃残留字符）。若鸿蒙直接
`finishTextPreview()`，会把退格后残留的最后一个字符（如「n」）固化上屏，导致退格删不掉。

故「组字结束无 commit」分支改为：先 `setPreviewText('', {-1,-1})` 把预览替换为空串，
再 `finishTextPreview()` 固化空 —— 等价于「丢弃预览」，对齐安卓 commitText("", 1)。

**清理**：移除全部 `MeowpuutTouch` / `MeowpuutPreview` / `MeowpuutDiag` 诊断 hilog，
`KeyTouches.ets` / `MeowpuutKeyboard.ets` / `KeyboardPage.ets` 恢复原状。

**验证**：hvigor `assembleHap` BUILD SUCCESSFUL（本机编译通过；真机验证由用户在鸿蒙
设备上执行，当前鸿蒙设备已离线，安卓设备 `10ACCM3A8A001PS` 在线作行为基准）。

### round 66：组字可见真机验证通过 + selectionChange 自回环根因修复（鸿蒙 56V0225905003230，API 12）

round 65 的代码在真机上首验失败：**每敲一个字母就把上一个字母替换掉**（输入框显示
`'n' → 'i' → 'ih'`，新字母替换旧字母而非累积）。

**根因（PV 诊断 hilog 铁证）**：`on('selectionChange')` 回调原本承担「用户移走光标时
清空组字」的职责，但 **`setPreviewText` 本身移动光标也会触发该回调**：

```
PV: preedit='n' wasC=false nowC=true cur=0     ← 第1键 n，开预览，光标 0→1
（selectionChange 触发 → composer.clear() 清掉 raw）
PV: preedit='i' wasC=false nowC=true cur=1     ← 第2键 wasC=false！raw 已被清空
```

第二键的 `wasC=false` 证明第一键的组字在两次按键之间被 selectionChange 处理器清掉了。
对照证据：日语模式（preedit 路径不同，不触发同样回调序列）下 nihao 能完整累积，
说明 `setPreviewText` 机制本身工作正常，bug 是拼音模式特有的 selectionChange 干扰。

**修复：时间窗抑制（取代一次性布尔标志）**

```typescript
// 预览 API 调用会移动光标并回调 selectionChange，打开自驱动抑制窗口。
// 一次按键可能触发多个回调（insert + 光标移动），布尔标志只能挡第一个，
// 时间窗（SELF_DRIVEN_MS=700ms）能覆盖整个回调序列。
private static readonly SELF_DRIVEN_MS: number = 700;
private lastPreviewAt: number = 0;

// selectionChange 处理器开头：
if (this.composer.composing && this.lastPreviewAt > 0 &&
    Date.now() - this.lastPreviewAt < MeowpuutAbility.SELF_DRIVEN_MS) {
  return;  // 预览自驱动的光标变化，不是用户移光标
}
```

用户真把光标移走（超时后 selectionChange 仍组字）时，先把预览 `finishTextPreview()`
落地成普通文本再清组字（对齐 Android composing 留在原处变非组字文本的行为），
避免预览悬空导致后续 `{-1,-1}` 更新作用在过期预览区上。

**修复 2：预览操作串行队列（previewChain）**

分词路径（nihao 选「你」剩 hao）是三步链 `setPreviewText(你)→finish→setPreviewText(hao)`，
若被下一键的 `setPreviewText` 插队，`{-1,-1}` 的「沿用当前预览范围」语义会作用在错误的
预览状态上。故每次按键的预览操作构造成配方数组，追加到 `previewChain` Promise 链上
严格串行执行；每步执行前刷新 `lastPreviewAt` 维持抑制窗口。

`applyEdit` 的 commit 落地责任随之扩展：`committedViaPreview = wasComposing && previewSupported`
（分词情形也交给预览链，不再走 insertText——预览区已在分词链里被正确重排）。

**真机验证结果（全部通过，hilog + uitest dumpLayout + qwen3.8-max 视觉复核三重取证）**：

| 场景 | 结果 |
|---|---|
| 拼音 nihao 组字 | `'n'→'ni'→'nih'→'niha'→'nihao'` 逐键累积 ✅ |
| 选候选替换 | nihao → 点候选「你好」→ 输入框变 `你好` ✅ |
| 上屏后再组字 | `你好` + 输入 hao → `你好hao`（新组字接在已上屏后）✅ |
| 退格删空 | `你好hao→ha→h→你好` 逐字回退，删空无残留 ✅ |
| 注音模式 | ㄡㄞㄨㄇㄢ 逐键累积，选候选上屏「偶爱物慢」✅ |
| 日语模式 | `ん→に→にh→には→にはお` 罗马字实时转假名 ✅ |
| 英文模式 | toggle 切换后字母直接追加 `にはおn→にはおni` ✅ |
| 跨应用（备忘录搜索框）| nihao 完整累积，候选「你好/逆号/妳好/你」正常 ✅ |

**组字下划线的平台真相（qwen 视觉复核 + ACE 源码 + SDK 签名三方确认）**：

- 预览文本在鸿蒙 API 12 **默认无下划线/高亮样式**（系统备忘录里同样裸文本）。
- ACE 源码 `GetPreviewTextStyle()` 默认 `PreviewTextStyle::NORMAL`；下划线
  （`PreviewTextStyle::UNDERLINE`）是**编辑框组件侧**的 paintProperty
  （`ReceivePreviewTextStyle`），由目标应用设置，**IME 侧 `setPreviewText(text, range)`
  签名无任何样式参数**（SDK `@ohos.inputMethodEngine.d.ts:1634` 铁证）。
- 即「带下划线」在鸿蒙 API 12 上是平台能力缺口而非输入法可实现项；核心需求
  「组字原始字符实时可见 + 选候选替换」已 100% 达成，与系统输入法行为一致。

**附带修复**：设置页删除「切换键盘」按钮（用户指示）——移除 `Button('切换键盘')` +
`imeDialog` CustomDialogController + `InputMethodListDialog` import，只保留
「打开键盘设置」跳系统页；ENABLED 文案改为引导用户去系统输入法页选择喵扑。
子类型切换仍可通过设置页「输入方式」下拉或键盘地球键完成。

## round 59：用户 9 条反馈逐项修复（离线收尾——真机已断开，构建通过 + 静态/像素取证）

> 背景：本轮起真机 56V0225905003230 USB 断开且不再可用。9 条修复全部完成代码、
> `build-harmony-hap.ps1` 构建通过（BUILD SUCCESSFUL），按「静态代码审查 + 历史
> 截图像素分析 + Python 枚举仿真」三级取证；**真机复验清单**见本节末尾，设备
> 恢复后逐条执行。

### (1) 九键拼音——真实 T9 引擎（鸿蒙独有增强，Android/iOS 均无九键）

- **核心 bug**：`Lexicons.open` 的 `const pinyin = mode === InputMode.PINYIN`
  只认全键拼音，九键加载的是注音词库——round 56 的九键「完全无候选」即源于此。
  已改为 `PINYIN || PINYIN9`。
- **架构**（Rust core 无法本地重编——无 cargo 工具链，T9 纯 ArkTS 实现）：
  - 新文件 `engine/T9.ets`：404 音节表 → 217 个数字编码；`splits()`（DP 可达性
    切分，SPLIT_CAP=12、短切分优先）；`combos()`（每段音节笛卡尔积，COMBO_CAP=24、
    短音节优先）；`preeditText()`（首选切分拼音分段提示）；`query()`（影子会话
    重放：clear → 逐字母 key → candidates，每组合 8 个候选）。
  - **候选排序**：先按「切分段数少 → 首候选 EXACT（引擎 kind=1）」对组合排序
    再合并去重（cap 64）——否则 `64426` 的 mi-gan 组合会淹没 ni-hao 的「你好」。
  - **影子会话**：`Lexicons` 用同一拼音词库 `sessionCreate` 第二个会话
    （`t9Shadow`），`Composer.attachT9Shadow()` 接线；主会话在九键模式下保持
    零输入（backspace/choose 都不触它）。
- **键盘布局**：`Keys.ets` `nineKeySet()` 经典 3×4——`1` 键=标点（点击上屏「。」，
  长按备选「，、？！…；：”…」），2-9 数字主标+角标字母组（`Key.sublabel` 新字段，
  绘制在 `MeowpuutKeyboard` 主标下方 0.38× 字号、alpha 0.66）；底行为标准
  符号/ABC/地球/空格/换行。
- **子类型**：`input_method_config.json` 注册 `MeowpuutPinyin9`（zh-CN/lower，
  label `ime_label_pinyin9`「喵扑输入法 九键拼音」）；`modeOfSubtype`、设置页
  输入方式下拉、`switchSubtype` 地球键循环（注音→全拼→九拼→日语）全链路接入；
  `switchCurrentInputMethodSubtype` 仍走系统通知（跨进程 preferences 不互通的
  既有结论）。
- **物理键盘**：九键态数字 2-9 直通 `typeEngine`；词库失败时数字直接上屏兜底。
- **Python 仿真验证**：`64426`→2 切分（mi-gan/ni-hao）；`926426`→9 切分；
  `7764`→0 切分（qq 非音节，回退数字串候选）；`726`→2 切分——枚举逻辑正确。

### (2) 悬浮键盘：显示不全 + 拖动不跟手

- **拖动不跟手（根因）**：`PanGesture.onActionUpdate` 的 `event.offsetX` 是
  **相对手势起点的总位移**而非增量，旧代码 `dragAccumX += offsetX` 会指数级
  累积漂移；且 24px 批量提交让面板一跳一跳。改为基线差分（`offsetX - 上次已提交`）
  **每帧 moveTo**（`KeyboardPage.ets`）。
- **显示不全（两处钳制错误）**：`dragPanel` 旧 clamp 是
  `nx ∈ [0, disp.width-24]`——按面板左上角而非右缘算，可把 1272px 宽的面板拖出
  屏外。改为按面板真实宽高 `nx ∈ [0, width-panelW]`、`ny ∈ [0, height-panelH]`；
  `applyPanelPosition` 初始位置同样保证 `y + panelH ≤ height - margin`。

### (3) 字母/猫咪候选区背景透明（悬浮态）

- `Look` 新增 `translucentPanel` 字段：悬浮态 `keyboardTop/Bottom` 由
  `#FF…`（不透明）降为 `#E6…`（90% alpha），候选栏与键区 Canvas 透出底层应用
  ——「浮在应用上的卡片」观感；贴底态保持不透明（对齐 Android `Theme.kt:62`）。
  组件根容器本就 `Color.Transparent`，无额外层。

### (4) 键帽与底板玻璃形态

- **底板**：`drawKeys`/`drawCandidateBar` 的背景由整块矩形改为**顶部按造型轮廓
  起伏**的路径（`glassTop(look.shape, x, …)` 逐点采样 48 段）：胶囊=平直圆角、
  波浪=S 形、云朵=鼓包——造型切换时整块键盘底板与候选玻璃连成一体。
- **键帽**：圆角随造型变化（WAVE=1.35×、CLOUD=1.18×，cap 到键高一半），
  胶囊保持默认——波浪/云朵造型下键帽更圆润，与候选玻璃呼应。

### (5) 长文本候选重叠（根因）

- `drawRow` 里 pill 宽度按 `shown`（截断后）算，但 `items.push` 存的是
  `c.text` **原文**——绘制时 `fillText(item.text)` 画出超宽原文，溢出 pill
  与相邻候选叠字。修复：`items.push(..., shown, ...)`，pill/文字/命中检测
  （`hitCandidate` 本就按 shown）三者一致。

### (6) 候选栏下拉收起键盘（鸿蒙增强）

- `barPress` 记录 `barDownY`；`barMove` 检测 `dy > 64 && dy > |dx|·1.5`（横向
  拖动仍是候选滚动）→ 新回调 `KeyboardCallbacks.onHide` →
  `MeowpuutAbility.hideByPullDown()` → `panel.hide()`（下次聚焦自动再弹）。

### (7)+(9) 深色药丸错位 & 快打不高亮在第一候选（同一族根因）

- **(9) 动画重定向**：`pillSlideX` 动画进行中目标变化时，旧代码让旧动画跑完
  （`pillToX` 未更新），胶囊短暂停在旧目标。改为检测 `|toX-pillToX|>0.5` 立即
  以当前插值位为 from 重启动画（easeOutCubic 接续，无跳变）。
- **(9) 滚动残留**：Android `CandidateBarView.update` 在 `newRow` 时 `scroll=0`，
  鸿蒙缺这个——打字加长候选后第一个候选被旧 scroll 推出屏，高亮「看起来不在
  第一个候选」。`refresh()` 现在按候选/预测行内容变化归零 `barScroll`。
- **(7)**：(5) 的 pill/文字错位修复同样消除深色下最显眼的错位；滑动动画时长
  240ms→150ms，错位窗口缩短近半。

### (8) 最下方灰底两个图标——已定位（像素取证），非我方绘制

- 历史截图像素分析：图标在 **y2011-2078**，左 `x133-192`、右 `x1127-1186`
  （各 60px），位于我方键区 Canvas 内容（自然键高排版至 ~y2020）之下的
  panel 底部条带——**globes（输入法切换）+ 齿轮/菜单（输入法设置）样式的系统
  工具条**，画在 IME 面板窗口的系统层，我方代码（Glyphs/Keys/KeyboardPage 全
  检索）无任何对应绘制路径。SDK `@ohos.inputMethod.Panel.d.ts` /
  `@ohos.inputMethodEngine.d.ts` 全文无 toolbar API。
- **处置**：系统 UI 无法由第三方 IME 移除；待设备恢复后以 `uitest dumpLayout`
  确认其不在应用窗口节点树（终局证据），并向用户说明这是系统级工具条。

### 真机复验清单（设备恢复后逐条执行并截图取证）

1. 设置页切「九键拼音」→ 备忘录打 `64426`：3×4 布局 + 角标字母组渲染；候选
   首位应为「你好」（mi-gan 不淹没）；打 `7764` 回退数字候选；`926426` 出
   「熊猫/王小明」类多切分候选；hilog 测逐键候选时延（96 组合最坏 case 上限 24）。
2. 悬浮模式拖动把手：连续画圈拖动——面板每帧跟手、无跳变；四缘钳制不越屏。
3. 悬浮态下开备忘录——键区/候选区透出底层应用 10% 底色。
4. 造型切波浪/云朵——底板上沿起伏 + 键帽圆角变化截图对比。
5. 长句组字（10+ 键）——候选无叠字、超宽候选中段省略号截断。
6. 候选栏指下滑 64px+ ——键盘收起。
7. 深色 + 快速连打——高亮始终居第一候选、动画 150ms 内到位。
8. `uitest dumpLayout` 确认底部两图标不在应用节点树（反馈 8 终局证据——已由
   用户侧确认为系统图标，本项从复验清单移除）。
9. 九键面板高度与 4 行布局的 `resizePanel` 数值核对（上次贴底实测 981px vs
   推算 945px 的 36px 差——用 hilog 打点 panel.resize 实参定位）。

## round 60：第二轮真机反馈 8 项修复（连删根因、悬浮钳制/单位、九键底行、全键盘下拉）

> 真机由用户侧验证（另一 AI 执行），本会话设备不可用；全部修复经构建通过 +
> 代码走查收尾。复验见本节末「round 60 复验清单」。

### (1) 设置页当前键盘状态不随系统切换刷新

- 现象：系统切到小艺输入法后，设置页状态行仍显示「当前使用的键盘是喵扑」。
- 根因：`updateStatus()` 只在 `aboutToAppear` 执行一次，无任何监听。
- 修复（`SettingsPage.ets`）：订阅 `inputMethod.getInputMethodSetting().on('imeChange')`
  （API 9+，`@ohos.inputMethod.d.ts:262`）回调重查；补 `onPageShow` 兜底；
  `aboutToDisappear` 注销。回调用实例箭头函数保持 `off` 引用一致。

### (2) 九键底行 UX + 「1」键长按备选条不可见

- 底行重排（`Keys.ets` `nineKeySet`）：`[符号][空格(弹性)][删除][换行]` 四键
  JUSTIFIED——原底行（符号/ABC/地球/空格/换行）**没有任何删除键**（九键下
  无法退格，也是反馈 6「连删没法用」的一半原因）；ABC/地球移出九键底行。
- 备选条/气泡 Z 层级（`Geometry.ets`）：`AlternatesStrip.fromKey` 与
  `KeyBalloon.bubble` 原固定画在按键**上方** 50/54vp——九键第 0 行
  （含「1」标点键、符号页首行）长按时 y<0 超出键区 Canvas 被裁，观感即
  「长按后看不到」。改为：上方放不下（`top-高度-4 < 4`）时翻转到按键
  **下方**绘制，永远留在 Canvas 内。

### (3) 悬浮「最底层被截断」+「拖拽很慢不跟手」

- 截断根因：悬浮把手行渲染在 KeyboardPage 顶部（32vp），但面板高度从未计入
  ——把手挤掉键盘内容高度，底行溢出面板被裁。修复（`MeowpuutAbility`）：
  新增 `floatingPanelHeight() = 键盘高 + 32vp×density`，`resizePanel` /
  `applyPanelPosition` / `dragPanel` 钳制三处统一使用。
- 拖慢根因：`PanGesture.onActionUpdate` 的 `event.offsetX/Y` 单位是 **vp**，
  `panel.moveTo` 单位是 **px**——不换算时密度 3 的机器面板只跟 1/3 速度。
  修复（`KeyboardPage.ets`）：提交前乘 `densityDPI/160`。

### (4) 背景透明（需求纠偏）

- 回退 round 59 的「悬浮态整块底板半透明」（`Look.translucentPanel` 字段、
  构造参数、悬浮分支取色、applyPanelPosition 联动全部还原）。
- 按用户澄清实现：**底部（常规）模式下候选栏（状态猫 + 字母区域）背景透明**——
  `drawCandidateBar` 不再铺 `keyboardTop` 底色，玻璃带/猫/候选直接浮在面板上
  （键区地板渐变不受影响）。不随深浅色变化、只动背景层。
- 风险注记：若 IME 面板窗口不支持逐像素透明，该区域会露出窗口默认底色
  （浅色白/深色黑）——真机复验第一优先确认项。

### (5) 下拉收起扩大到全键盘

- 原实现仅候选行内（64px、横向滚动把手小、命中区窄）。修复：键盘根 Column
  挂 `PanGesture(Vertical)`——起点不在任何按键上（`KeyTouches.anyPointerOnKey()`
  新查询，缝隙/候选栏空白/边距均可）、竖向下拉 >56vp 即 `panel.hide()`；
  一次手势只触发一次；展开面板（纵向滚动中）不触发。原候选栏路径保留。

### (6) 长按删除连续删除（真根因）

- 现象：连删只多触发一拍就停。
- 根因（`KeyTouches.ets`）：`deleteTick(runId)` 的守卫用**定时器 id**当
  runId——首次重发后 `deleteRepeat` 指向新定时器，闭包里捕获的旧 runId
  与之恒不等，第二拍直接 return，链断。
- 修复：改**世代计数器** `deleteRun`——`startDelete` 自增、`stopDelete`
  失活自增、tick 闭包校验世代；`deleteRepeat`（定时器 id）只用于 cancel，
  职责分离。按住即连删到松手（420ms 首延 + 83ms 间隔 + 26 拍后每 3 拍
  整词删除，与 Android 相同）。

### (7) 底部两个灰底图标

用户侧已确认为系统图标——停止处理，从复验清单移除。

### (8) 质感专项（绘画层，无几何改动）

- 键帽（`drawKey`）：crisp 底边叠加**软投影**（浅色紫灰 0.10/深色黑 0.22，
  blur 3 下偏 1.5）；常态补**上缘高光**（1.2dp 内嵌描边，顶部亮向下渐隐），
  按下态不画。
- 键区地板（`drawKeys`）：两段渐变改**三段**（顶 30% 保持顶色再向底色加深），
  更有整块材料的厚重感。

### round 60 复验清单（真机逐项截图取证）

1. 状态行：切小艺→回喵扑设置页（或等待事件）状态行应变为「已启用」提示；
   再切回喵扑恢复「当前使用」。
2. 九键：底行为 符号/空格/删除/换行；长按「1」备选条出现在按键下方且可见；
   长按删除键——420ms 后每 83ms 连删、2.6 秒后转整词删除，删到空为止。
3. 悬浮：底行完整可见（不再截断）；拖动跟手 1:1（每帧同速）。
4. 候选栏背景透明：浅色+深色各截图——猫/候选背后应透出备忘录内容而非
   纯色底（若露白/黑底色立即回报，窗口不支持透明需要回退方案）。
5. 全键盘下拉：手指从候选栏空白/猫身上/按键缝隙处下拉>56vp 键盘收起；
   从字符键/删除键/空格上下拉不收起；展开面板内滚动不误触。
6. 质感：键帽有落影+顶部高光；地板渐变上平下深。深浅色各一张。


## round 61：剪贴板（真机反馈「读不到剪切板的内容」）

- 现象：键盘没有任何剪贴板功能；用户预期至少能粘贴。
- 调研：`pasteboard.getData()` 需 `ohos.permission.READ_PASTEBOARD`——
  system_basic + user_grant + ACL 受限权限（`PermissionDefinitions.json`），三方
  输入法申请需 AGC 侧受限权限审批 + 签名 profile 含 `acls.requestPermissions`，
  签名链路不在本项目掌控（会直接导致安装失败），不走此路。
- 采用官方输入法通路：`InputClient.sendExtendAction(ExtendAction.PASTE)`
  （`@ohos.inputMethodEngine.d.ts`，API 10+）——输入法把 PASTE 动作发给聚焦的
  编辑框，粘贴由编辑框/系统侧完成，输入法零权限。文档注明：编辑框应用响应
  PASTE 需自身具备 READ_PASTEBOARD（系统组件已具备）。
- UI：预测行首位常驻「粘贴」芯片（CandidateItem kind=3，剪贴板小图标 +
  「粘贴」文案，浅底胶囊与预测词同风格）；仅非组字态显示（组字时候选优先，
  不掺入）。点击 → onPasteEvt → KeyboardCallbacks.onPaste →
  `pasteFromClipboard()` → sendExtendAction(PASTE)，失败仅记 hilog 静默。
- 新增：`Glyphs.clipboard`（板身+压夹+内容线描边图标）；hitCandidate 显式
  设定 ctx.font（原先依赖绘制残留，芯片宽度公式与 drawRow 严格一致）。
- 限制（记入验证预期）：粘贴动作由编辑框执行——支持程度取决于目标应用
  （备忘录等 ArkUI 输入框原生支持；部分自绘输入/网页可能忽略）。密码框
  系统侧会拒绝粘贴，属正常安全行为。

### round 61 复验清单

1. 备忘录输入一段文字 → 长按全选复制 → 清空 → 点开键盘：预测行第一位应出现
   剪贴板图标 +「粘贴」芯片 → 点击 → 剪贴板内容出现在光标处。
2. 组字中（拼音未上屏）芯片不显示；组字提交后回来。
3. 网页输入框/搜索框粘贴一次，记录是否生效（应用差异，非 bug）。
4. hilog grep MeowpuutIME：应见 `paste action accepted`。

## Round 62 — 内核更换为 Meowpuut-Core（hairkeeperonline fork @f8e5993）

用户要求：把输入内核更换成 https://github.com/hairkeeperonline/Meowpuut-Core（新 Rust 引擎）。

### 同步范围（fork → monorepo，保留全部 HarmonyOS 客户端代码）
- `crates/` 全量替换：meowpuut-core 0.8.0（新 english.rs / abbrev.rs / pets.rs、改进的 decoder / fallback / latin / lexicon / api）、meowpuut-ffi（头文件新增原生九键会话、英文引擎、MPPets、皮肤包接口）、新增 meowpuut-pets / meowpuut-skin / meowpuut-skin-abi 三个 crate。
- `DataSources/`、`Resources/Lexicon/` 全量替换（改进的数据，mimo-english 新增）。
- 根 `Cargo.toml` + `Cargo.lock`、`THIRD_PARTY.md`、核心脚本（compile-native-lexicon.py、mimo_en_binary.py、mimo_english.py、blocked_terms.py、build-lexicon.sh、eval-*.py、check-no-volunteer.py、copy-lexicon-notices.py 等）、`Tests/`（golden / eval / pets-moments.json / skin-vectors 并入）。
- 保留 monorepo 客户端：harmony/、Android/、iOS/、客户端脚本（build-harmony.sh、convert-script.py 等）。

### 构建链路适配（Windows）
- Rust 1.100.0 + ohos 双 target（aarch64 / x86_64-unknown-linux-ohos），.build/rust/harmony/<abi>/libmeowpuut_ffi.a 重编完成。
- 词库全量重建（本地无 iOS/Generated 快照）：converter 改为 `.build/convert-script.bat`（OpenCC convert-script.py 包装，CreateProcess 可执行、cygpath 纯反斜杠路径回显），产物 staging 到 rawfile：mimo_base.bin（65.6MB，compact 后 -12MB）、mimo_pairs.bin、**mimo_en.bin（4.4MB，5 万词 / 56.6 万词对 / 11.3 万 next-words）**、native-japanese.tsv、mimo_jp.bin。
- build-harmony.sh：LEXICON_FILES 加 mimo_en.bin；mimo_en_binary.py 纳入构建与 LEXICON_SOURCES。

### NAPI 桥（napi_init.cpp + index.d.ts + NativeEngine.ets）
新增导出：nineKeySessionCreate、inputText、textNoSuggest、attachEnglish、englishOpen / englishClose / englishWordCount、englishComplete / englishCorrect / englishPredict / englishNineKey（查询内部建/销毁 MPNEnglishQuery，返回 [text,kind,...] 平铺数组）、englishIsBlocked。englishOpen 用 copy=1（无 release 回调，不钉 ArrayBuffer）。

### 九键重写（ArkTS T9 展开层退役，删除 T9.ets）
- Lexicons：PINYIN9 会话改为 `nineKeySessionCreate`（数字 2-9 直接进组字）；复用守卫加 loadedNineKey（全键↔九键切换必重建会话）；拼音词库在建会话前 `attachEnglish(mimo_en.bin)`；t9Shadow 删除。
- Composer：typePinyin9 会话化（key→takeCommitted→syncRaw→rebuild）；rebuild 走引擎候选（coreIndex 指向引擎列表，preedit = 引擎渲染的解码拼音 + 首选候选拼写）；choose 支持部分消耗（选词后剩余数字继续组字）；backspace 驱动会话；takeLiteral= 数字串。
- 物理键盘数字 2-9 自动进九键会话；词库加载失败时仍直接上屏数字。

### 英文引擎（ABC 模式，P1 范围）
- Lexicons 另开独立 MPNEnglish 句柄（同一 mimo_en.bin，copy=1）。
- MeowpuutAbility.updateEnglishRow：光标在词中 → englishComplete + englishCorrect 补全/纠错 chips（点选替换光标前词，deleteBackward 后 commit）；空格后 → englishPredict 下一词（commit 前自动补空格）；shift/caps 状态传 ENGLISH_SHIFT / ENGLISH_CAPS_LOCK flags。
- updatePredictions 分流：english 模式走英文行；字母提交 / 空格 / 退格 / 标点 / 点选后各自刷新。

### 遗留（P2，后续轮次）
- MPPets（2884 字节状态机 moments）与皮肤包（meowpuut-skin-abi）已编进 .so 但 ArkTS 未接线；现有宠物进度走旧 ArkTS 规则。
- 九键模式 ABC 页未接 englishNineKey（拼音九键已能通过 attach_english 出英文词候选）。
- textNoSuggest 已暴露未接学习词过滤。

### 产物
- HAP 86.7MB（原 93.8MB）：libmeowpuut_napi.so 含全部新符号（mpn_nine_key_session_create / mpn_english_open / mpn_lexicon_attach_english 等，arm64+x86_64），rawfile 含 mimo_en.bin，modules.abc 含新 ArkTS 标记（nineKeySessionCreate / updateEnglishRow / englishReplace / loadedNineKey）。
- 验证：全 crate 经 ohos 双 target 交叉编译（aarch64 / x86_64）；check-lexicon.py PASS（465,287 读音 / mimo_base 65.6MB / 853,302 词对 / never-volunteer 1,324 词 / 双原生索引核对）；宿主 cargo test 因本机无 MSVC link.exe 无法执行（纯工具链限制，非代码问题）。

## Round 62 后续 — 分支重组

- **harmonyOS 分支**（本分支）：去除非 HarmonyOS 部分，只保留 `harmony/` + Rust 引擎（crates/）+ 词库数据（DataSources/ + Resources/Lexicon）+ 核心脚本 + 猫/节日贴图资源 + 引擎测试；其余客户端（Android / iOS / Windows / macOS Sources / Modules）与平台脚本、iOS 商店文档、macOS 资源包全部移除。构建链验证：build-harmony.sh --prepare + HAP 打包全通过，产物与重组前逐字节一致。
- **main 分支**：已同步远端主干（03ceae4，Engine 子模块 = Meowpuut-Core f8e5993，与我们同步的核心一致）并清理过时引用（build-rust.sh 注释），提交 7cadad5 推送。
- 本分支保持自包含布局（crates/ 在仓库根），不采用 main 的 Engine 子模块结构——Windows 构建机克隆即用、无需 submodule init。

