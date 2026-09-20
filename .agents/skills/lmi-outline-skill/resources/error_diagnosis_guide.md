# LMI 图谱大纲校验错误诊断与自愈操作手册 (Error Diagnosis & Self-Healing Guide)

> **使用说明**：当执行大纲阶段校验脚本（`step1_validate_nodes.ps1`、`step2_validate_concepts.ps1`、`step3_build_graph.ps1`、`build_textbook_outline.ps1`）返回 `success: false` 时，请按照脚本返回的 `errors` 数组中的 `type` 字段，在此手册中查找对应的自愈操作规范。
> 所有操作均为**确定性原语**，严禁臆测字段或篡改未报错的结构。

---

## 阶段一：节点列表校验错误自愈 (`step1_validate_nodes.ps1`)

对应操作目标文件：`step1_nodes_raw.json`

| 错误代码 (`type`) | 触发原因 | 确定性操作原语与修复规范 |
| :--- | :--- | :--- |
| `JSON_SYNTAX_ERROR` | JSON 语法解析失败（如漏逗号、多逗号、单双引号混用） | 检查整个 JSON 文件语法。排查项：1. 键名与字符串值是否全为标准英文双引号 `"`；2. 数组或对象末项之后严禁存在多余的尾随逗号；3. 大括号/中括号是否正确闭合。 |
| `FILE_NOT_FOUND` | 输入文件不存在 | 确保在当前工作目录正确定位并写入了 `step1_nodes_raw.json`。 |
| `STRUCTURE_ERROR` | 顶层结构不合法 | 修正文件顶层结构为标准对象形式：`{ "nodes": [ ... ] }`。 |
| `EMPTY_NODES` | `nodes` 数组为空 | 在 `nodes` 数组内至少添加一个符合规范的节点对象。 |
| `INVALID_NODE_OBJECT` | `nodes` 数组中的某一项不是有效对象 | 定位到 `index` 指示的项（1-based），将其改写为键值对完整的节点对象 `{ ... }`。 |
| `MISSING_FIELD` | 节点对象缺少必填字段（如 `id`、`label`、`module`） | 定位到报错的 `index`（或 `node_id`）节点对象，新增缺失的字段键值对，例如 `"[field]": "<该字段的学术规范值>"`。 |
| `INVALID_ID_FORMAT` | 节点 ID 格式不符合纯数字点分层级规范 | 定位到 `node_id` 对应的节点，将其 `id` 值修正为满足正则表达式 `^\d+(\.\d+)+$` 的格式（如 `"1.1"`、`"2.3"`，严禁包含汉字、英文前缀如 `"ch1"`）。 |
| `DUPLICATE_ID` | 存在重复的节点 ID | 检查整个 `nodes` 数组，为报错的节点赋予全局唯一的层级 ID。 |
| `INVALID_TEACHES` | 节点的 `teaches` 不是数组 | 定位到 `node_id` 对应的节点，将 `teaches` 字段改写为字符串数组：`"teaches": [ "<该节点所传授核心概念1的定义名称>", ... ]`。 |
| `EMPTY_TEACHES` | 节点的 `teaches` 数组为空 | 定位到 `node_id` 对应的节点，在 `teaches` 数组中添加至少 1 个 `<该节点所传授核心概念的定义名称>` 字符串。 |
| `EMPTY_TEACHES_ITEM` | `teaches` 数组中存在空字符串 | 定位到 `node_id` 对应的节点，移除 `teaches` 中的空字符串或空白项，或填充为具体的概念名称。 |
| `INVALID_REQUIRES` | 节点的 `requires` 字段不是数组 | 定位到 `node_id` 对应的节点，将 `requires` 修正为数组格式；若该节点无前置依赖，显式写为 `"requires": []`，严禁使用 `null` 或省略该字段。 |
| `INVALID_BLACKBOX_TERMS` | `blackbox_terms` 字段不是数组 | 定位到 `node_id` 对应的节点，将 `blackbox_terms` 修正为数组格式；若无黑盒术语，显式写为 `"blackbox_terms": []`。 |
| `INVALID_BLACKBOX_ITEM` | 黑盒术语对象缺少 `term` 或 `purpose` | 定位到 `node_id` 节点的 `blackbox_terms` 下标为 `index` 的对象，补齐非空键值对：`{ "term": "<术语名称>", "purpose": "<当前阶段用途说明>", "target_node": null }`。 |

---

## 阶段二：概念归一化校验错误自愈 (`step2_validate_concepts.ps1`)

对应操作目标文件：`step2_concepts_raw.json`

| 错误代码 (`type`) | 触发原因 | 确定性操作原语与修复规范 |
| :--- | :--- | :--- |
| `MISSING_FIELD` (顶层) | 缺少 `concept_dictionary` 或 `nodes` | 确保顶层同时包含两个数组：`{ "concept_dictionary": [ ... ], "nodes": [ ... ] }`。 |
| `INVALID_CONCEPT_OBJECT` | `concept_dictionary` 中某项不是对象 | 定位到下标 `index`（1-based）的条目，将其规范为概念对象结构 `{ ... }`。 |
| `DUPLICATE_CONCEPT_ID` | 概念词典中存在重复的概念 ID | 检查报错的 `concept_id`（如 `C005`），为其中一个概念分配未被占用的全新概念编号（如递增为 `C010`）。 |
| `DUPLICATE_CANONICAL_NAME` | 概念词典中存在多个同名概念（`canonical` 重复） | 1. 在 `concept_dictionary` 中保留首个概念对象；2. 将重复概念对象的别名与规范名并入首个对象的 `aliases` 数组；3. 删除多余的概念对象；4. 在 `nodes` 列表中将所有引用已删除概念 ID 的地方全部替换为保留的首个概念 ID。 |
| `MISSING_FIELD` (概念) | 概念对象缺少 `id`、`canonical` 或 `taught_by` | 定位到报错的 `concept_id` 对象，补齐缺失字段：`"id": "<编号>"`, `"canonical": "<规范名>"`, `"taught_by": "<节点ID>"`。 |
| `INVALID_TAUGHT_BY_NODE` | 概念的 `taught_by` 引用了不存在的节点 ID | 检查该概念的 `taught_by`，将其修改为 `nodes` 列表中真实存在的某个节点的 `id`。 |
| `INVALID_ALIASES` | 概念的 `aliases` 不是数组 | 将该概念对象的 `aliases` 改写为字符串数组；若无别名，显式写为 `"aliases": []`。 |
| `UNRESOLVED_TEACHES_CONCEPT` | 节点的 `teaches` 包含了未在词典中注册的概念 ID | 定位到 `node_id` 节点的 `teaches`，排查 `concept_id`：若为拼写错误则更正为词典已有 ID；若确实遗漏，在 `concept_dictionary` 中新增一条以该 ID 为标识的概念条目。 |
| `TAUGHT_BY_MISMATCH` | 节点声明传授某概念，但词典中 `taught_by` 登记为其他节点 | **双向一致性修正（二选一）**：<br>1. 若该概念应由当前节点主讲：将 `concept_dictionary` 中该概念的 `taught_by` 字段值更新为当前节点的 `id`；<br>2. 若该概念应由其他节点主讲：从当前节点的 `teaches` 数组中移除该 `concept_id`。 |
| `UNRESOLVED_REQUIRES_CONCEPT` | 节点的 `requires` 包含了未在词典中注册的概念 ID | 检查 `node_id` 节点 `requires` 中的 `concept_id`。在 `concept_dictionary` 中补充该前置概念对象（并指明其 `taught_by`），或修正拼写错误。 |
| `SELF_DEPENDENCY` | 节点既教又需要同一个概念（自依赖闭环） | 定位到 `node_id` 节点，从该节点的 `requires` 数组中移除该 `concept_id`。 |

---

## 阶段三：拓扑连边与环检测错误自愈 (`step3_build_graph.ps1`)

对应操作目标文件：`step2_concepts.json`

| 错误代码 (`type`) | 触发原因 | 确定性操作原语与修复规范 |
| :--- | :--- | :--- |
| `CYCLE_DETECTED` | 节点依赖形成了有向死锁闭环（违背 DAG 拓扑） | 1. 查看报错输出中的 `cycle_nodes` 数组（例如 `["1.2", "1.3"]`）；<br>2. 打开 `step2_concepts.json`，检查这几个节点在概念层面的前置依赖关系；<br>3. 寻找构成反向回环的前置概念，从下游节点的 `requires` 数组中删除该概念 ID（或者将循环概念调整为后续扩展节点再引入）；<br>4. 重新运行阶段三脚本直至拓扑排序成功。 |

---

## 教材大纲结构校验错误自愈 (`build_textbook_outline.ps1`)

对应操作目标文件：`textbook_outline_raw.json`

| 错误代码 (`type`) | 触发原因 | 确定性操作原语与修复规范 |
| :--- | :--- | :--- |
| `MISSING_TITLE` | 缺少顶层 `title` 字段 | 在顶层添加 `"title": "<教材全名规范字符串>"`。 |
| `MISSING_CHAPTERS` | 缺少顶层 `chapters` 数组或为空 | 添加非空数组 `"chapters": [ { "id": "...", "title": "...", "sections": [ ... ] } ]`。 |
| `MISSING_CHAPTER_TITLE` | 某章对象缺少 `title` | 定位到 `chapter_index`（0-based）的章对象，添加 `"title": "<章标题规范字符串>"`。 |
| `EMPTY_SECTIONS` | 某章对象的 `sections` 数组为空 | 定位到 `chapter_id` 的章对象，在 `sections` 数组中添加至少 1 个节对象。 |
| `MISSING_SECTION_TITLE` | 某节对象缺少 `title` | 定位到 `section_index` 的节对象，添加 `"title": "<节标题规范字符串>"`。 |
| `EXCEEDED_LEVEL_LIMIT` | 节对象内嵌套了第三级子项（如 `subsections`） | 移除所有第三级嵌套，严格展平或收敛为纯二级结构（`chapters -> sections`）。 |
