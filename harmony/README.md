# 喵撲（Meowpuut）HarmonyOS 输入法

这是喵撲输入法的 HarmonyOS（鸿蒙 NEXT / OpenHarmony）客户端，功能与 Android 版对齐：在
注音、拼音、日语之间混合输入而无需切换，拥有玻璃质感的候选栏与米米莫、莫莫两只猫咪，
支持简繁切换、展开候选面板、按住删除/移动光标等完整手势。

## 架构

喵撲是三层结构，本目录只新增**平台层**，核心引擎与词库数据完全复用：

```
crates/                         # ① Rust 核心引擎（零拷贝解码，禁 unsafe）
  meowpuut-core / lexicon / client / ffi
  meowpuut-ffi/include/meowpuut.h   # C ABI，HarmonyOS 直接调用，不改一行
iOS/Generated 或 scripts 编译    # ② 词库数据（mimo_base.bin / mimo_pairs.bin …）
harmony/                        # ③ 本目录：HarmonyOS 平台层
  entry/src/main/
    cpp/napi_init.cpp           #     NAPI 桥（对应 Android meowpuut_jni.c）
    ets/engine/                 #     ArkTS 引擎封装（对应 Android engine/）
    ets/ui/                     #     ArkUI 键盘（对应 Android ime/）
    ets/entryability/           #     InputMethodExtensionAbility 主服务
```

对照关系：

| Android                          | HarmonyOS                                |
| -------------------------------- | ---------------------------------------- |
| `meowpuut_jni.c`（JNI）          | `cpp/napi_init.cpp`（NAPI / node-api）   |
| `engine/NativeEngine.kt`         | `ets/engine/NativeEngine.ets`            |
| `engine/Composer.kt` 等          | `ets/engine/Composer.ets / Romaji.ets / …` |
| `ime/MeowpuutIME.kt`             | `ets/entryability/MeowpuutAbility.ets`   |
| `ime/KeysView.kt` 等自定义绘制    | `ets/ui/MeowpuutKeyboard.ets`（ArkUI Canvas） |

## 目录结构

```
harmony/
├── AppScope/
│   ├── app.json5
│   └── resources/base/element/string.json
├── build-profile.json5            # 顶层工程配置（compatibleSdkVersion 5.0.0）
├── hvigorfile.ts                  # 顶层 hvigor 脚本
├── hvigor/hvigor-config.json5
├── oh-package.json5
└── entry/
    ├── build-profile.json5        # externalNativeOptions → CMakeLists.txt
    ├── hvigorfile.ts
    ├── oh-package.json5
    └── src/main/
        ├── module.json5           # InputMethodExtensionAbility 注册
        ├── cpp/
        │   ├── CMakeLists.txt
        │   ├── napi_init.cpp      # NAPI 桥
        │   └── types/libmeowpuut/index.d.ts
        ├── ets/
        │   ├── engine/            # NativeEngine / Composer / Romaji / JapaneseWords …
        │   ├── ui/                # Geometry / GlassOutline / Keys / Theme / Cats …
        │   ├── pages/KeyboardPage.ets
        │   └── entryability/MeowpuutAbility.ets
        └── resources/
            ├── base/profile/      # input_method_config.json, main_pages.json
            ├── base/element/string.json
            └── rawfile/           # lexicon/ cats/ festivals/（由 build-harmony.sh 生成）
```

## 构建

### 前提

- **DevEco Studio**（HarmonyOS NEXT，API 12 / compatibleSdkVersion 5.0.0）
- **OpenHarmony SDK**（装 DevEco 时自带的 native toolchain，含 `native/llvm/bin/clang` 与
  `native/sysroot`）
- **Rust**（rustup），加上两个 ohos target（脚本会自动 `rustup target add`）

### 步骤

```bash
# 1. 交叉编译 Rust 引擎，并把词库/猫咪/节日资产拷进 rawfile
OHOS_SDK=/path/to/OpenHarmony/Sdk bash scripts/build-harmony.sh --prepare

# 2. 用 DevEco Studio 打开 harmony/ 目录，签名后构建 run 到设备
```

`build-harmony.sh` 做的事：

1. 为 `aarch64-unknown-linux-ohos` 与 `x86_64-unknown-linux-ohos` 生成 clang 包装脚本
   （`-target aarch64-linux-ohos --sysroot=<sdk>/native/sysroot -D__MUSL__`），并
   `cargo rustc --release -p meowpuut-ffi --crate-type staticlib`；
2. 把 `libmeowpuut_ffi.a` 放到 `.build/rust/harmony/<abi>/`；
3. 把 `mimo_base.bin / mimo_pairs.bin / native-japanese.tsv` 拷到
   `harmony/entry/src/main/resources/rawfile/lexicon/`；
4. 把 `Resources/Cats/*.png`、`Resources/Festivals/*.png`、`festivals.json` 拷到
   `rawfile/cats/` 与 `rawfile/festivals/`（原图保留版权，原样复用）。

DevEco 构建时，`entry/build-profile.json5` 的 `externalNativeOptions` 会调用
`CMakeLists.txt`，把 `libmeowpuut_ffi.a` 与 `napi_init.cpp` 链成 `libmeowpuut_napi.so`。

> 注：本仓库原本**没有** HarmonyOS/ohos 相关脚手架；以上全部为本次新增。

## 词库读取

HarmonyOS 的 rawfile 无法像 Android 的 `AssetManager.openFd` 那样拿到可直接 mmap 的 fd，
因此 ArkTS 侧用 `resourceManager.getRawFileContentSync` 把词库读成 `Uint8Array`，NAPI 桥用
`napi_create_reference` 钉住底层 `ArrayBuffer` 后交给 `mpn_lexicon_create_from_base_in_place`
原地读——既零拷贝，又保证引擎在期间不会因 GC 失效。

## 复刻保真点

为保证与 Android「逐像素一致」，以下全部原样照搬（数值见对应 `.ets` 内注释）：

- 几何：标识（PHONE / PHONE_LANDSCAPE / TABLET）判定、`scale = clamp(width/393, 0.9, 1.15)`、
  候选栏高度（phone 82/46）、KeyMetrics、行排布、命中区铺满、KeyBalloon / AlternatesStrip；
- 玻璃轮廓：capsule / wave / cloud 三种形状的圆弧/正弦/云朵数学（`GlassOutline.ets`）；
- 配色：六套 Palette（ROSE/OCEAN/SAGE/LAVENDER/AMBER/GRAPHITE）的 pill/color 精确值、
  `Look` 的全部派生色、`lighten/darken/withAlpha/parseColor`；
- 猫咪：`CatSpriteData.ets` 8 张贴图（anchor/cut/paw 分数）、`CatSeats.ends` 落座与
  `rise` 曲率、`CatAffection`（5 次/1.6s 切简繁）、`CatMotion` 时序数组；
- 触控 FSM：`KeyTouches.ets` 的 ALTERNATES_DELAY=450、CURSOR_DELAY=400、CURSOR_STEP=9、
  多指 rollover、Shift 滑键、删除重复（INITIAL_DELAY=420 / INTERVAL=83 / 26 次后整词）；
- 候选：拼音的「中文在前、一个日语靠前、原始字母在可及处」合并顺序、
  收合列 `collapsed()` 只留一个日语、`PAW_GAP` 爪印间距；
- 键盘：注音 4 行键位与字符码、`ZHUYIN_KEYS`、`QUICK_MARKS`、重音/符号长按备选表、
  罗马字→假名全表、中文语义词表。

## 说明与局限

- 本机没有 Rust 工具链与 DevEco Studio，代码为可编译交付物，需在 DevEco 里完成最终编译与
  签名验证；编写时已按官方 API 与 OpenHarmony 文档逐条核对（如 `getInputMethodAbility`、
  `createPanel`、`insertTextSync`、`getEditorAttributeSync`、`moveCursorSync`、`Direction`
  等 API 9/10+ 口径）。
- `moveCursor` 与 `getEditorAttribute` 在 API 9 是 Promise；代码优先用 API 10 的
  `*Sync` 变体并回落到异步接口。
- 图标：`module.json5` 引用 `$media:icon` / `$media:app_icon`；`build-harmony.sh` 会优先用
  Android 的 `ic_launcher_foreground.png`，否则需自行放置。
- 猫咪/节日 PNG 与图标为「保留所有权利」资产，本仓库只原样引用、不重新生成。

## 更多文档

- 引擎与词库架构：`docs/ENGINE.md`
- 四平台共享设计（玻璃形状/猫咪落座/配色/动效/性能预算）：`docs/DESIGN.md`
- 节日皮肤：`docs/FESTIVALS.md`