# 喵扑鸿蒙版下一阶段计划（Round 65 候选池）

> 状态：纯计划，未施工。基于 round 64 终态（性能优化+布局对齐+真机联调 8 项修复全部落地）。
> 事实核查已完成：Rust 侧 `meowpuut-skin`（.mpskinb 验证/信任/归档，含 ffi C ABI）与 `meowpuut-pets`（猫时刻）crate **已在鸿蒙分支工作区**（随引擎同步带入）；`napi_init.cpp` 尚无皮肤/宠物的胶水绑定；main 分支有完整安卓参照实现（SkinKeystore/SkinVault/SkinGallery/BundledSkins/PaperTokens/PetMoments）。

---

## 第一部分：鸿蒙独有特性适配

### 1.1 折叠屏形态（中优）
- 现状：`resolveIdiom` 只有 PHONE / PHONE_LANDSCAPE / TABLET 三档，靠屏幕高度推算；折叠/展开切换会走 onAreaChange → rebuild（链路已有），但无「折叠态」专属策略。
- 计划：
  - 展开态（宽屏平板档）：九键 `maximumWidth=460` 居中已有 ✓——补全键 QWERTY 的双手分体布局调研（或维持居中单块+加大键距，先验证观感）。
  - 折叠态窄屏：验证 current 布局在 cover 屏（~6.9" 附近宽高比）无溢出；底行弹性空格按比例收缩。
  - 折叠/展开瞬间：onAreaChange 已失效 pxRatio 缓存 ✓（round 64 加的），需真机验证切换无撕裂/闪烁。
- 验证：模拟器折叠态 + 真机（若有）截图视觉比对。

### 1.2 多窗口 / 自由窗口 / 平行视界（中优）
- 现状：面板宽度跟随 onAreaChange ✓；自由窗口拖角变宽、分屏 1/2 宽未验证。
- 计划：小窗（< 全宽）场景下九键 referenceColumns=10 自适应 + 底行不溢出；分屏时面板出现在正确窗口侧；悬浮键盘钳制按窗口而非全屏（当前用 disp.width/height 全屏值——分屏下会钳错）。
- 风险：`display.getDefaultDisplaySync()` 拿的是全屏尺寸，窗口尺寸需从 panel/组件 area 取——钳制数学要换成窗口坐标。

### 1.3 无障碍：逐键虚拟节点（高优，上架加分）
- 现状：整块 `accessibilityGroup` + 一句「喵扑输入键盘」；PARITY 挂账「需叠加透明语义层 + 真机读屏验证」。
- 计划：
  - 对照 Android `VirtualAccessibility`（accessibleKeys：coveredHeight 过滤、spoken/label/enabled/longClick、Rect 坐标）在 Canvas 上叠透明语义层。
  - 每键 node 朗读 spoken（简繁/中英标签已有）；展开面板态朗读候选格。
  - 真机验证：鸿蒙读屏（设置→无障碍→屏幕朗读）逐键焦点浏览 + 双击激活。
- 价值：华为应用市场无障碍合规与评分。

### 1.4 系统字号缩放跟随（低优）
- 现状：键帽/候选字号全硬 vp；系统「显示大小」调大后键盘不变。
- 计划：监听配置变更取 fontSizeScale，仅放大候选文字与 spoken 相关字号（键帽不动，防溢出——对照安卓 maxFontScale 策略）。

### 1.5 端侧 AI 联想（远期可选，隐私敏感）
- 方向：HarmonyOS AI Foundation（意图/纠错/润色）做 opt-in「智能联想」：默认关闭、设置页明示、纯端侧推理。
- 前置：与项目隐私基线（PRIVACY.md 纯本地）对齐的产品决策——先立项讨论再动工。

### 1.6 安全输入（中优）
- 现状：numericField 检测存在（符号页自动回正用过 AUTO_RETURN + numericField 判断）。
- 计划：密码框（inputType 检测）自动切九键数字页/收面板提示；对齐安卓安全键盘行为。

---

## 第二部分：键鼠适配

> 现状盘点（已落地）：`hardwareKeyEvent` 处理 ESC（清组字 ✓ round 64 修）、DEL、SPACE/ENTER 组字收尾、DPAD 左右移候选高亮、物理字母/数字直通（typeHardware，含九键 T9 数字、拼音分词'）、Ctrl/Alt/Meta 组合交还系统、onDestroy 反注册 ✓。

### 2.1 Shift / CapsLock 状态同步（高优，小工作量）
- 现状：软键盘 shift 键有 ONCE/LOCKED 视觉；物理键盘 Shift 按下时软键盘 shift 键不亮。
- 计划：KEYCODE_SHIFT_L/R 的 DOWN/UP → `caps.tap()` + refreshKeyboard（物理 shift 单击=ONCE、双击窗口内=LOCKED，对齐软键盘手感）；字母大写直通已有 ✓。

### 2.2 方向键与 Tab 扩展（中优）
- 上下方向键：候选高亮上/下移动（DPAD 左右已有）；展开面板态 = 滚动一行。
- Tab：面板内候选间移动（或交还系统焦点——按安卓行为对照后定）。
- Home/End：候选栏滚到头/尾。

### 2.3 词级删除与编辑组合键（中优）
- Ctrl+Backspace：删前一个词（onDelete(word=true) 已有，物理键盘未接）。
- Ctrl+Z 撤销最近上屏（引擎侧无 undo 栈——新增轻量 undo buffer，纯 ArkTS）。

### 2.4 鼠标（高优——键鼠共享/平板场景刚需）
- **hover 高亮**：ArkUI hover 事件 → 按键描边/亮起（当前触控无 hover 态）；玻璃反光随 hover 键移动的「质感彩蛋」可选。
- **滚轮**：候选栏横向滚 + 展开面板纵向滚（wheel 事件接 Canvas）。
- **右键**：按键右键 = 直接弹长按备选气泡（alternates，现有 KeyBalloon 复用）。
- **悬浮拖拽**：把手之外整块候选栏可拖（鼠标用户习惯），触屏仍限把手。

### 2.5 键鼠共享跨设备真机矩阵（中优）
- 华为 PC（键鼠共享）→ 手机：键盘事件 ✓（delegate 已注册）+ 鼠标 hover/滚轮（2.4 落地后）+ 光标渲染验证。
- 外接蓝牙键盘：连发退格节奏（硬件 repeat 事件流 vs DeleteRepeat 定时器——避免双重连删）。

---

## 第三部分：iOS/Android 借鉴 + 美化计划

### A. 从 main 分支移植（最高价值——引擎侧已就位）

#### A1. 皮肤系统（高优，大件）
- 参照：安卓 `SkinKeystore`（签名信任根+吊销）、`CustomSkin/CustomSkinLoader`（验证安装 .mpskinb）、`SkinVault`（已装清单）、`SkinGallery`（皮肤库页）、`BundledSkins`（随包内置皮肤，如 sakura_tea）、`SkinRedeemer`（兑换码，安卓 only——鸿蒙先不做收货侧）。
- Rust 侧 `meowpuut-skin` + `meowpuut-ffi/src/skin.rs`（C ABI：verify/list/remove，JSON 出参，test-keys 特性区分 Debug/Release 信任）**已在工作区**。
- 鸿蒙施工面：① `napi_init.cpp` 补 skin 绑定（按 ffi ABI 逐函数）② ArkTS SkinLoader/SkinVault（对齐 CustomSkin 数据面：palette light/dark、keys 三色、猫贴图替换）③ `Look` 增加皮肤覆盖层（现有 palette/pill/键色字段直接被皮肤值覆盖，Theme.ets 构造期注入——round 64 已把 Look 派生色全部构造期预算，正好无缝）④ 设置页皮肤库 UI（复用现有卡片体系）。
- 内置 1-2 张皮肤首发（sakura_tea 的 .mpskinb 在 main 分支 debug 资产里）。

#### A2. 纸主题（Paper，高优，中件）
- 参照：`PaperTokens`（六主题 rose/ocean/sage/lavender/amber/graphite × light/dark 全色板：paper/paper2/ink/pill/stamp/tapeA/tapeB/grain/shadowWarm）+ `PaperSurfaces` + paper 字体（Round/Serif 两套 ttf）+ 纸纹贴图。
- 鸿蒙施工面：六主题色板作为 `Look` 新 palette 组（Theme.ets 加 PaperPalette 映射）；纸纹/胶带/印章绘制进 GlassPainter/PillPainter；字体 ttf 入 resources + 候选行选配纸字体开关。
- 与 A1 关系：皮肤是「外部覆盖」，纸主题是「内置主题」——先做 A2 打底，A1 皮肤值直接覆盖纸主题。

#### A3. 宠物时刻（PetMoments，中优）
- 参照：`NativePets` + `PetMoments` + Rust `meowpuut-pets/moments.rs`（已在工作区）。
- 内容：猫的情境动画时刻（引擎时机驱动：组字提交后的满足、长空闲打盹、连打兴奋……把现有 lean/toast 体系升级成状态机）。
- 施工面：napi 绑定 + 动画帧资源 + MeowpuutKeyboard 猫绘制接入（drawCatImage 已有缓存 ✓）。

### B. iOS 交互借鉴（按性价比排序）
1. **触控板模式升级**（小件）：长按空格进 cursor mode ✓ 已有——把「键盘全域」变成触控板（按住任意区域滑动移光标，iOS 2 代体验），KeyTouches 已有光标模式骨架。
2. **单手键盘**（小件）：布局整体左/右移 + 收窄（悬浮钳制已支持任意落位，补一个设置项+双击 shift 切换的手势）。
3. **捏合切悬浮**（小件）：两指捏合手势 → 悬浮态；展开 → 回贴底（对齐 iOS 浮动键盘手势）。
4. **滑行输入 glide**（远期大件）：Rust 核心无滑行解码（纯新增）；先立项调研词库 lattice 复用可行性，不承诺。
5. 已对齐无需再做：长按空格移光标、双空格句号、句首自动大写、气泡预览。

### C. 美化计划
1. **玻璃静态层离屏缓存**（P0——round 64 遗留的性能+顺滑双赢）：GlassPainter shadow/body + pawShadows + 节日簇 ~2800 Point2D/帧 → OffscreenCanvas 按 (宽, Look ref, 猫开关, 节日贴图) 缓存，脏了才重画。
2. **按键按压质感升级**：现有 squash（缩 2-3%）+ 加按压涟漪/键帽微光扩散（Canvas 一次性动画，不常驻）。
3. **猫动画升级**：idle 呼吸、眨眼、睡觉 Zzz 粒子（与 A3 共用状态机，A3 落地前的纯前端版本）。
4. **节日系统扩展**：docs/FESTIVALS.md 节日表持续接入（贴图+键帽点缀+候选栏饰簇），已跑通一套（loadFestivalArt）。
5. **键音包**：SOUNDS.md 音色体系多套包（钢琴/机械/水滴），设置页试听（KeySounds 已有 release ✓）。
6. **首次启用 onboarding**（P1）：输入法启用/设为默认的引导页（真机调试吃过「系统键盘弹出来不是喵扑」的亏——引导用户到系统输入法设置页的「打开键盘设置」按钮已有，包一页向导+权限/隐私说明）。

---

## 优先级与执行建议（供拍板）

| 档 | 内容 | 理由 |
|---|---|---|
| **P0（下轮）** | 玻璃离屏缓存、逐键无障碍、Shift 同步、鼠标 hover/滚轮/右键 | 性能收尾+合规+键鼠刚需，工作量中 |
| **P1** | 纸主题、皮肤系统（napi 胶水+ArkTS 加载+设置页）、折叠/分屏验证矩阵、键鼠共享真机 | 视觉大升级，Rust 侧零新增 |
| **P2** | 宠物时刻、触控板模式升级、单手/捏合、onboarding、安全输入 | 体验锦上添花 |
| **P3（远期调研）** | 滑行输入、端侧 AI 联想、手写页 | 依赖立项决策 |

## 依赖与风险
- 皮肤/纸/宠物：Rust+FFI 已就位（工作区 crates）——主要风险是 napi 胶水量大（skin ABI 十余函数）与皮肤包资产版权（sakura_tea 仅 debug 资产，发布需授权确认）。
- 无障碍逐键：需真机读屏联调（用户的另一 AI 可配合）。
- 滑行/AI：纯新增能力，先出调研报告再排期。
- 验证方法论已成熟：hdc + uitest 坐标注入 + dumpLayout/输入框文本 + qwen3.8-max 视觉子代理读截图 + 像素扫描定谳 + hilog 取证——新特性全走这套流水线。
