# Round 65 P0 真机验收手册

> 本文档对应 commit `1eaba7a`（Round 65 收尾）产出的 HAP。
> 四项功能代码已完成并通过离线仿真（`node tools/verify-round65.mjs`，170 项断言），
> 但**真机验收全部未做**——设备 `56V0225905003230` 在整个开发期间持续离线。

---

## 0. 前置：安装 HAP

```powershell
$HDC = "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"

& $HDC list targets          # 确认设备在线，应列出序列号
& $HDC install -r "E:\WTY\Meowpuut-Round65-P0.hap"
```

签名失败或版本冲突时：

```powershell
& $HDC uninstall com.krysta1ll.meowpuut.ohos
& $HDC install "E:\WTY\Meowpuut-Round65-P0.hap"
```

**包信息**：`com.krysta1ll.meowpuut.ohos`，v0.8.0 (80000)，debug 构建，phone/tablet/2in1。
签名已用 `hap-sign-tool verify-app` 验证：`Digest verify result: true` / `verify-app success`。

---

## 1. 启用输入法

1. 打开喵扑 App（桌面图标"喵扑"），至少启动一次
2. **设置 → 系统和更新 → 语言和输入法 → 输入法**
3. "更多输入法"里打开 **喵扑输入**
4. 返回，把"当前输入法"切为 **喵扑输入**

或直接跳转到设置页：

```powershell
& $HDC shell aa start -a SettingsAbility -b com.krysta1ll.meowpuut.ohos
```

---

## 2. ⚠️ 第一步：验证手指打字（最高优先级）

打开任意输入框（备忘录/浏览器地址栏），**用指尖点几个字母**。

| 结果 | 含义 | 处理 |
| --- | --- | --- |
| ✅ 正常输入 | 手指路径正常 | 继续下一节 |
| ❌ 完全没反应 | `SourceType.Mouse` 过滤过宽，把手指也拦了 | **立即反馈**，改为仅过滤右键 |

**为什么这一条排第一**：Round 65 的 ④ 在 `handleKeysTouch` 顶部加了
`if (event.source === SourceType.Mouse) return;` 以避免鼠标事件被 `onMouse` 与
`onTouch` 双重投递。若某些触屏面板把手指上报为 `Mouse`，会导致**整个键盘无法用
手指输入**——比鼠标不工作严重得多。修复方式是改用 `MouseEvent.button` 判别右键，
而不是按 `source` 判别。

---

## 3. 日志采集

新开一个 PowerShell 窗口常驻：

```powershell
$HDC = "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $HDC shell hilog -r
& $HDC hilog | Select-String -Pattern "MeowpuutGlass|MeowpuutMouse|MeowpuutIME|FaultThread"
```

无 `hilog` 子命令时改用：

```powershell
& $HDC shell "hilog | grep -E 'MeowpuutGlass|MeowpuutMouse|MeowpuutIME'"
```

---

## 4. ① 玻璃静态层离屏缓存

### 4.1 关键日志

首次绘制后出现一次：

```
MeowpuutGlass  glass cache rendered: vp=360x56 bmp=1080x168 k=3
```

- `vp=360x56` 是画布逻辑尺寸，`bmp=1080x168` 是位图像素尺寸
- `k=3` 是像素比，**两者应成 3 倍关系**。若不是 3 倍，说明 `transferToImageBitmap`
  的尺寸语义与预期不符，`drawImage` 回贴会缩放，需要调整

此后每 10 秒：

```
MeowpuutGlass  glass stats: hit=N direct=M render=R
```

### 4.2 判据

| 观察 | 结论 |
| --- | --- |
| `render` 停留在个位数，`hit` 持续增长到数百/数千 | ✅ 缓存生效 |
| `render` 与 `hit` 同步增长 | ❌ 缓存每帧失效，① 未达成 |
| `direct` 持续增长 | ❌ 离屏路径失败，一直在回退直绘 |

**重要**：`glassHitFrames` 计的是"位图回贴成功的帧"，衰减实现里 hit 照样增长。
**必须以 `render << hit` 判定，不能只看 hit 非零。**

### 4.3 其余验收项

- **空闲**：停止操作 30 秒，`render` 不再增长
- **视觉零回归**：与升级前截图对比，玻璃带/猫爪阴影/节日装扮应肉眼无差别
  （边缘 ±1 LSB 属离屏合成固有量化代价，非缺陷）
- **打字跟手**：快速连打一段文字，无明显掉帧或输入延迟

---

## 5. ② 逐键无障碍虚拟节点

### 5.1 dumpLayout

```powershell
& $HDC shell uitest dumpLayout -p /data/local/tmp/layout.json
& $HDC file recv /data/local/tmp/layout.json E:\WTY\layout.json
```

打开 `E:\WTY\layout.json`，搜索键名（`q` / `空格` / `删除` / `大写` 等）。

### 5.2 判据（5 条，缺一不可）

1. 节点数 = 键数（常态），或 = 底行键数 + 可见候选格数（展开组字态）
2. 每个节点 `bounds` 与键的 `frame` 一致（±1vp 容差）
3. `text` 字段等于键的 `spoken`（非空时）或 `label`
4. **展开面板滚动一格后**，候选格节点 `bounds.top` 应整体下移一格高度
5. 键被禁用时对应节点应呈现禁用态

### 5.3 失败判据

若 **dumpLayout 里完全找不到这些节点**，说明 `accessibilityVirtualNode` 的占位
组件未被 a11y 树接纳（即 `accessibilityLevel('yes')` 未生效），**② 判定为未达成**，
需要改用 `Stack` 叠加真实透明组件的方案。

辅助验证：开启 TalkBack，摸键听是否逐键朗读。

---

## 6. ③ 物理 Shift / CapsLock 同步

**前提**：有蓝牙或 USB 物理键盘（或 PC 模式）。

### 6.1 注入验证单击

```powershell
& $HDC shell uitest uiInput keyEvent 2047    # KEYCODE_SHIFT_LEFT
& $HDC shell uitest screenCap -p /data/local/tmp/s1.png
& $HDC file recv /data/local/tmp/s1.png E:\WTY\s1.png
```

预期：截图里软键盘 shift 键呈**点亮态**；随后按字母应输出大写。

### 6.2 双击锁定只能手动验

`uitest uiInput keyEvent` 注入的是 **DOWN+UP 一对**，两次注入之间的间隔不可控，
**无法用它测双击→LOCKED**。必须手动在物理键盘上快速双击 Shift。

预期：双击后 Shift 常亮（LOCKED），连续输入多个字母均为大写。

### 6.3 其他用例

| 操作 | 预期 |
| --- | --- |
| 单击 Shift 后松手，再打字 | 小写（不残留大写）|
| 按住 Shift 连续打字母 | 全部大写 |
| CapsLock 键 | 切换锁定态 |
| 锁定态再按 Shift | 解除锁定 |

---

## 7. ④ 键鼠适配

**前提**：USB 或蓝牙鼠标。

| 操作 | 预期行为 |
| --- | --- |
| 鼠标划过键盘 | 经过的键出现强调色描边 |
| 候选栏滚轮 | 候选行左右滚动 |
| 展开面板滚轮 | 候选格上下滚动 |
| 右键点有备选的字母键（`a`/`e`/`o` 等）| 弹出备选气泡条 |
| 在气泡条上左右移动 | 高亮跟随移动 |
| 左键点气泡条某格 | 输入对应字符 |
| 再次右键 | 气泡条关闭（**不能重新打开**）|
| 左键点普通键 | 与手指点击行为一致 |
| 按住左键拖过删除键 | 连续删除 |

### 已知风险

- **滚轮方向**：`getVerticalAxisValue()` 的符号与内容滚动方向的关系 SDK 未说明，
  目前按"正值 = 向下"实现。若方向相反，改
  `MeowpuutKeyboard.WHEEL_DIRECTION` 为 `-1` 即可，无需改其他代码。
- **滚轮步长**：一格 48vp，可能偏快或偏慢，需手感确认。

---

## 8. 故障采集

**崩溃**：

```powershell
& $HDC hilog | Select-String -Pattern "FaultThread|Reason:|Error message"
```

**性能**：连续采样几行 `glass stats` 贴回。

**其他**：直接把相关日志段落贴出，无需整理。

---

## 9. 离线仿真（不需要设备）

```bash
node tools/verify-round65.mjs
```

五套仿真、170 项断言 + 30.8 万采样点。任一失败整体返回非 0。
覆盖：命中测试几何、① 缓存键/失效/位图生命周期、② 节点生成/展开裁剪/签名去重、
③ Shift 状态机、④ 鼠标事件路由。

**注意**：仿真只证明逻辑正确，**证明不了** `OffscreenCanvas` 实际像素、
`drawImage` 点播语义、a11y 树接纳、事件真实投递、GC 曲线与你关心的手感。

---

## 10. 反馈清单

请按以下格式回报，便于逐项销账：

| 项 | 结果 | 依据 |
| --- | --- | --- |
| 安装 | 成功/失败 | 错误信息 |
| **手指打字** | **正常/失灵** | —— |
| ① 缓存 | 通过/不通过 | `glass stats` 采样 |
| ① 视觉 | 一致/有差异 | 截图对比 |
| ② 无障碍 | 通过/不通过 | dumpLayout 片段 |
| ③ Shift | 通过/不通过 | 截图 |
| ④ 键鼠 | 逐条结果 | 说明 |
