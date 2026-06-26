# reverse-skill 对 KSSMA 字段值域恢复的可行性分析, 2026-06-25

## 结论

能，但不是“直接自动算出值”。`reverse-skill` 可以把“schema 已知但值未知”从手工猜测升级成可重复流程，前提是把它当作工具路由和执行框架，再加一层 KSSMA 专用适配：

1. 用 KSSMA schema card 固定字段存在性和 native owner。
2. 用 `reverse-skill` 的 APK/native 路由选择 `apk-reverse`、`radare2`、`ida-reverse`。
3. 对 `librooneyj.so` 做字符串、xref、调用图和资源命名 helper 追踪。
4. 对 bundle XML、sdcard dump、base zip 做结构化枚举，抽取字段样例和资源文件名。
5. 把 native 消费路径和文件存在性合并成候选值表，按证据强弱排序。
6. 只把最高置信候选交给后续 ARM19 runtime 做单变量验证。

缺口是：`reverse-skill` 本身没有 KSSMA 协议语义、没有 schema-card 读取器、没有 `MainMenuTagData` / `InfomationTagData` 到资源名的专用规则，也没有现成的 XML 字段值域推断脚本。它提供的是可复用工具链和方法论，不是 KSSMA 值域恢复器。

## 可直接使用的能力

- 任务路由：`skills/routing.md` 明确把 APK/Android 任务路由到 `apk-reverse`，`.so` 核心逻辑分流到 `ida-reverse` 或 `radare2`。这正好匹配 KSSMA：Java 层只是 bootstrap，主要协议和 parser 在 `work/million_cn/apktool/lib/armeabi/librooneyj.so`。
- APK 产物入口：`apk-reverse` 的 `decode.ps1` 能统一产出 jadx/apktool 目录和摘要。KSSMA 已经有 `work/million_cn/jadx` 与 `work/million_cn/apktool`，所以当前不需要重跑，但这个脚本可作为新样本重新落盘的标准入口。
- Native 快速侦察：`radare2/scripts/recon.ps1` 封装 `rabin2 -I/-S/-i/-E/-zz`，适合对 `librooneyj.so` 做字符串、导出、节区和轻量函数概览。用于查 route string、field string、resource helper 字符串很合适。
- 深入 native 分析：`ida-reverse` 描述了 `idapro_find_regex`、`idapro_xrefs_to`、`idapro_decompile`、`idapro_trace_data_flow`、`idapro_callgraph` 等能力，正对应 KSSMA schema card 需要的 parser ownership、字段 compare、结构体 offset、model copy 和 UI consumer 路径。
- Android/native 方法论：`apk-reverse/references/android-advanced.md` 与 `reverse-engineering/languages-platforms.md` 覆盖 Android `.so`、JNI、Frida、IDA/Ghidra/radare2 的分工。虽然 KSSMA 当前不需要动态 hook，这些文档能约束“Java 不够就看 native”的路线。
- 报告模板：`docs-generator` 可以作为最终报告结构参考，但本轮报告按 KSSMA 要求直接写入 `work/`。

注意：`reverse-skill/skills/tool-index.md` 当前不存在，只有模板。其 README/RULES 要求刷新 tool-index、写全局规则、回写 field-journal；这些都会产生写操作，和本轮“只读分析，只写 KSSMA 报告”的边界冲突，所以本轮没有执行。

## 需要适配的能力

- 需要一个 KSSMA schema-card 输入层：读取 `work/*schema-card*.md`，抽出 route、parent、confirmed fields、candidate fields、native owner、parser path、open questions。`reverse-skill` 没有这个格式的解析逻辑。
- 需要一个值源枚举层：结构化扫描 `work/million_cn/apktool/assets/bundle/`、`work/million_cn/jadx/resources/assets/bundle/`、`work/million_cn/sdcard_dump/`、`base/com.square_enix.million_cn-140330.zip`。`reverse-skill` 只有通用 APK 解包能力，没有 KSSMA 资源目录和命名约定。
- 需要资源命名规则适配：例如当前 mainmenu infomation 的 `fairy_pose/fairy_face` 不是直接文件名，而是走 `rooney::res::getAdvCharaFileName` / `getAdvCharaImage`，三参数 helper 将 `(chara_id << 16) | (pose << 8) | face` 编成资源 id。这个规则来自 KSSMA native 证据，不在 reverse-skill 中。
- 需要候选排序器：把“parser 读字段”“UI/model 消费字段”“资源文件存在”“bundle XML 有同格式样例”“runtime 负例”合成置信度。`reverse-skill` 不自带这种跨证据评分。
- 需要只读安全封装：`decode.ps1` 会写输出目录，`recon.ps1` 在缺工具时会自动 bootstrap，`ida-reverse` 会启动服务/建立数据库。KSSMA 的静态 pass 应先检查工具存在，再决定是否允许这些副作用；本轮不能直接调用。

## 不适合/不能解决的点

- 不能替代 KSSMA native schema skill。字段存在性仍必须以 `librooneyj.so` parser 证据为准，bundle XML 或文件名只能作为值源，不能证明字段存在。
- 不能自动证明运行时视觉结果。`fairy_pose=2/fairy_face=1` 这种候选即使资源存在，也仍需要后续 ARM19 单变量截图或 logcat 验证。
- 不能解决动态状态问题：WebView timing、scene callback、模型 completion flag、当前 client storage 等都超出静态值域分析。
- 不适合直接生成 server patch。KSSMA 当前规则要求先有 schema/value 证据，再只改一个变量；`reverse-skill` 的默认完成链还会生成报告、图和 field-journal，对本仓库边界太宽。
- 不适合处理已排除问题：模拟器切换、音频、face/mainbg 黑屏泛查、资源大预载等都不应因引入 reverse-skill 重新打开。

## 针对 mainmenu infomation 的具体使用路径

当前已知事实：

- `<body><mainmenu>` 是已验证 parent。
- `_MainMenuTagParser::parse` 读取 typo 节点 `infomation`，并把第一子节点传给 `_InfomationTagParser::parse`。
- `_InfomationTagParser::parse` 确认字段：`fairy_pose`、`fairy_face`、`focus`、`link`、`imagefile`、`message`。
- `_MessageTagParser::parse` 确认 `text`、`color`、`size`。
- `TownModel +0x88/+0x8c` 暴露为 `fairy_pose/fairy_face`。
- 旧的直接 `<mainmenu><fairy_pose>` 与 `<mainmenu><fairy_face>` runtime 试验已失败，不能重复。

可重复静态路径：

1. 以 `work/mainmenu-infomation-schema-card-20260625.md` 为输入，只处理 confirmed 字段，不新增 shape。
2. 用 `ida-reverse` 或现有 disasm 证据锁定 `_AnmPixie::updateFairyImage` 到 `rooney::res::getAdvCharaFileName/getAdvCharaImage` 的调用链，记录函数地址和参数含义。
3. 用 `radare2` 或普通文件枚举扫描资源名：`save/download/image/adv/adv_chara111*`、bundle `rule_resource*.xml`、pack alias。当前已知资源集支持 `adv_chara111_2_1` 到 `adv_chara111_2_12`，未见 `adv_chara111_1_1`。
4. 扫描 bundle XML 中所有 `message/color/size` 样例。当前已有 `local_gachaselect.xml` 和 `local_gachacomp.xml` 支持 `0xFFFFFF`、`0xFD7C79`、`0xFF0000` 这类 RGB hex 字符串，以及 `12/14/16/18/20` 字号。
5. 生成候选表：
   - `fairy_pose=2`、`fairy_face=1`：资源 backed，最高优先级。
   - `fairy_pose=1`、`fairy_face=1`：native 默认值，但资源未 backed，低优先级，且不应作为下一次 runtime 首选。
   - `message/color=0xFFFFFF`、`size=20`、普通 text：bundle 格式 backed，可作为最小 dialogue 值。
6. 输出一个只读候选报告，不改 `server/bootstrap-server.js`。后续 runtime handoff 只测试一条候选：在既有 `current_bgfile/previous_bgfile` 下添加一个 `<infomation>`，而不是直接添加 fairy 字段。

最小候选仍是：

```xml
<body>
  <mainmenu>
    <current_bgfile>mainbg_an</current_bgfile>
    <previous_bgfile>mainbg_an</previous_bgfile>
    <infomation>
      <fairy_pose>2</fairy_pose>
      <fairy_face>1</fairy_face>
      <message>
        <text>Welcome back.</text>
        <color>0xFFFFFF</color>
        <size>20</size>
      </message>
    </infomation>
  </mainmenu>
</body>
```

这不是本轮要 patch 的内容，只是后续 runtime 单变量验证的候选。

## 下一步最小试验

本轮建议的下一步不是启动模拟器，也不是改 server，而是做一个只读脚本化 proof：

1. 输入：
   - `work/mainmenu-infomation-schema-card-20260625.md`
   - `work/mainmenu-infomation-value-candidates-20260625.md`
   - `work/million_cn/sdcard_dump/`
   - `base/com.square_enix.million_cn-140330.zip`
2. 检查：
   - 枚举 `adv_chara111*`，证明 `pose=2, face=1..12` 有文件 backing，`pose=1, face=1` 无 backing。
   - 枚举 bundle XML 中 `message/color/size` 实例，证明候选格式来自样例而非手写猜测。
   - 输出一张 `field -> native evidence -> value source -> candidate -> missing proof` 表。
3. 产物：
   - `work/mainmenu-infomation-value-proof-20260625.md`
4. 最小 observable：
   - 不需要 server 或 emulator。
   - 报告中必须能重新推出 `2/1` 比 `1/1` 更适合做第一次 `<infomation>` runtime trial。

如果这个 proof 成立，后续才进入 `kssma-re-runtime` 单变量验证：只加一个 `<infomation>` entry，期望截图中 pixie face/pose 或 information message 区域出现可定位变化；如果没有变化，再回到 native consumer 路径，而不是继续猜值。

