---
name: lmi-plan-skill
description: "运行脚本 get_node_info.ps1 获取制定输出产物`教学计划`所需的信息，为该单一最小知识节点制定规范的二级大纲与概念完备性教学清单"
---

# 教学计划制定技能 (Teaching Plan Skill)

本技能的目标是制定规范的“教学计划”。通过运行脚本 get_node_info.ps1 获取目标节点（node.label）的必要上下文信息，并据此生成该节点的二级大纲与教学完备性清单（本技能的唯一交付与验收依据）。[脚本输出产物解释表]展示了对脚本输出字段的具体消费方式与教案模板映射规则


> [!IMPORTANT]
> ### 核心设计原则与边界
> 1. **教科书大纲范式（纯粹性）**：本技能**只规划“讲什么”，不规划“怎么讲”**。遵循权威学术教科书大纲规范，聚焦纯学术文本命名与定理核心内涵规划；具体代数变形、数值计算与定理推导完全留待课堂执行阶段（execution）展开。
> 2. **概念完备性契约（Concept Completeness）**：大纲的完备性以**概念全覆盖**为唯一检验标尺——必须 100% 覆盖探测脚本返回的 `teaches_concepts` 概念，确保本节点所含概念全部被二级大纲各子主题承载吸收。
> 3. **三段式教学粒度对齐**：每一个子主题的划分标准，以能够独立支撑一轮完整的自底向上三段式推演闭环（[现实具象] ➔ [图像表征] ➔ [严谨教学]）为唯一健康体量。
> 4. **教科书命名规范**：子主题标题必须采用**客观、凝炼的学术名词或并列短语**，完全贴近真实权威教科书节内小标题。

---

## 脚本输出产物解释表

运行脚本 `get_node_info.ps1` 返回的标准 JSON 结构各字段在教学计划模板中的消费与映射规则如下：

| 字段路径 (`context.*`)                    | 数据类型     | 业务内涵                                      | 教案模板注入与生成策略                                                    |
| :------------------------------------ | :------- | :---------------------------------------- | :------------------------------------------------------------- |
| `success`                             | boolean  | 脚本执行状态                                    | 若为 `false`，直接向用户展示 `message` 报错并终止，提示在客户端选择节点                  |
| `action`                              | string   | 操作动作标识 (`"get_node_info"`)                | 验证接口协议版本与来源                                                    |
| `active_subject`                      | string   | 当前活动学科名称                   | 用于输出路径对齐摘要，确认当前教案所属学科环境                                        |
| `selected_node_id`                    | string   | 选中的目标节点 ID                 | 用于构建教案一级标题及子主题编号依据                                             |
| `persisted_update`                    | boolean  | 图谱选中状态是否发生持久化更新                           | 若为 `true`，表明用户通过参数显式切换了节点并已持久化                                 |
| `suggested_plan_path`                 | string   | 标准化教案存储相对路径                               | `write_to_file` 写入的目标路径 |
| `node.id`                             | string   | 节点唯一编号                                    | 写入教案标题 `# 教学计划：[node.id] [node.label]`                         |
| `node.label`                          | string   | 节点标准学术名称                                  | 写入教案标题及确认核心推演范畴                                                |
| `node.safe_label`                     | string   | 文件名安全字符的节点名称                              | 供路径与文档锚点安全使用（已过滤非法特殊字符）                                        |
| `node.module`                         | string   | 节点所属章节/模块名称                               | 写入教案 `## 一、🎯 概念目标与教学边界` 中的 `- **所属模块**`                       |
| `node.position_summary`               | string   | 格式化后的学科与章节进度摘要                            | 在会话交互中输出路径对齐信息                  |
| `teaches_concepts`                    | object[] | 本节点负责传授的核心概念列表 (完备性契约)                    | 写入教案 `## 一、` 的 `**本节教授概念 (Teaches)**`；**二级大纲必须 100% 覆盖吸收**     |
| `teaches_concepts[].id`               | string   | 概念唯一标识符 | 二级大纲各子主题条目中的 `- **承载概念**` 声明，供课堂执行追踪                           |
| `teaches_concepts[].canonical`        | string   | 概念的标准学术中文名                                | 用于二级大纲子主题提炼、学术命名与核心定理关联                                        |
| `teaches_concepts[].aliases`          | string[] | 概念别名与英文对照                                 | 在教案概念清单中使用括号标注，丰富术语上下文                                         |
| `requires_concepts`                   | object[] | 本节点的前置依赖概念及溯源                             | 写入教案 `## 一、` 的 `**前置依赖概念 (Requires)**`                         |
| `requires_concepts[].id`              | string   | 前置概念唯一标识符                                 | 标注前置依赖列表                                                       |
| `requires_concepts[].canonical`       | string   | 前置概念学术中文名                                 | 标注前置依赖中文名称                                                     |
| `requires_concepts[].taught_by`       | string   | 传授该前置概念的前置节点 ID                           | 标明知识溯源路径                                                       |
| `requires_concepts[].from_node_label` | string   | 传授该前置概念的前序节点名称                            | 在前置条目中展示 `（来源：[from_node_label]）`                              |
| `requires_concepts[].edge_reason`     | string   | 图谱拓扑中声明的具体依赖因果理由                          | 填充条目中的 `依赖原因：[edge_reason]`，明确承上启下的逻辑切入点                       |

### 失败响应 Schema

当 `success` 为 `false` 时，脚本通过 `exit 1` 输出以下 JSON 结构：

```json
{
  "success": false,
  "action": "get_node_info",
  "error": "<ErrorType>",
  "message": "<人类可读的错误描述>",
  // ...可能包含附加上下文字段（如 active_subject, target_path 等），因错误类型而异
}
```

| `error` 值 | 触发条件 | 附加字段 |
|:-----------|:---------|:--------|
| `GRAPH_NOT_FOUND` | 知识图谱文件不存在 | `active_subject`, `target_path`, `workspace_root` |
| `INVALID_GRAPH_DATA` | 图谱文件损坏或缺少 `nodes` | `workspace_root` |
| `NO_SELECTED_NODE` | 无活跃学习节点 | `active_subject` |
| `NODE_NOT_FOUND` | 指定节点 ID 在图谱中不存在 | `active_subject`, `target_id` |

---

## 🎯 核心职责与执行流程

收到制定计划指令时，智能体**必须顺序执行以下伪代码流程**：

```pseudo
START:
- [步骤 1: 运行教案上下文探针 (Context Extraction)]
    - subject_arg = (已传入 active_subject 且非空) ? ("-Subject \"" + active_subject + "\"") : ""
    - node_arg = (已传入 target_node_id 且非空) ? ("-NodeId \"" + target_node_id + "\"") : ""
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-plan-skill/scripts/get_node_info.ps1 <subject_arg> <node_arg>`
    - context = PARSE_JSON(stdout)
    - IF (context.success == false):
        - 提示用户: context.message
        - STOP_CALLING_TOOLS (退出并提示错误信息)
    - END IF
    - active_subject = context.active_subject
    - target_node = context.node
    - teaches_concepts = context.teaches_concepts
    - requires_concepts = context.requires_concepts
    - plan_path = context.suggested_plan_path

- [步骤 2: 参考原版教材结构 (可选)]
    - IF (存在 "knowledge_graphs/" + active_subject + "/textbook_outline.json"):
        - CALL view_file 读取教材大纲作为结构与学术命名参考
        - 消费方式：该文件为教材目录的 JSON 表示，包含章节层级结构（chapters → sections）与各节标准学术名称。仅用于参考子主题的学术命名与认知排序，不强制约束二级大纲的划分方式
    - END IF

- [步骤 3: 构建二级大纲与完备性校验 (Syllabus Construction)]
    - 按照由浅入深的认知递进，将 teaches_concepts 分解为若干个不可再分的原子子主题
    - 校验完备性: 确保 ∪(各子主题承载概念) 覆盖所有 teaches_concepts (100% 概念全覆盖)
    - 明确声明本节范畴 (In-Scope) 与教学禁区:
        - 明确界定留待后续章节学习的后置概念、算法或超纲代数工具
    - 提炼各子主题下的核心定理、公理、引理或判定准则的标准学术名称 (严禁预写具体公式与数值推导)

- [步骤 4: 产物落盘与偏好对齐交付 (Persistence & Handover)]
    - CALL write_to_file 将符合标准化格式规范的 Markdown 写入 plan_path
    - 输出计划摘要 (包含子主题、承载概念与核心定理名) 供用户审查
    - 提示用户: "📋 教学计划（二级大纲）已生成至 " + plan_path + "。请审查大纲内容与范围边界：如需调整子主题请指出；若确认无误，可随时基于本计划启动课堂教学。"
    - STOP_CALLING_TOOLS (严格等待用户显式确认)
```

---

## 📐 教学计划标准化格式规范

教学计划 Markdown 文件必须严格包含以下三个标准化板块，杜绝任何结构重复：

```markdown
# 教学计划：[node.id] [node.label]

## 一、🎯 概念目标与教学边界
- **所属模块**：[node.module]
- **本节教授概念 (Teaches)**：
  - `[teaches_concepts[i].id]`【[teaches_concepts[i].canonical]】（别名：[别名1, 别名2...]）
- **前置依赖概念 (Requires)**：
  - `[requires_concepts[i].id]`【[requires_concepts[i].canonical]】（来源：[requires_concepts[i].from_node_label]，依赖原因：[requires_concepts[i].edge_reason]）
- **教学边界与禁区 (Boundary)**：
  - ✅ **本节范畴**：[说明本节点聚焦的核心推演范畴，结合 node.label 与 teaches_concepts]
  - 🚫 **本节禁区**：[明确界定留待后续章节学习的后置概念、算法或超纲代数工具]

---

## 二、📋 二级大纲与核心定理清单
*(本节共划分 N 个子主题，每个子主题支撑一轮完整的 [现实具象(通过现实问题映射到数学空间寻找解决办法) ➔ 图像表征(抽象到纯粹数学空间寻找普适规律) ➔ 严谨教学(总结归纳数学操作)] 三段式闭环)*

- [ ] **1. [子主题 1 学术规范名称]**
   - **承载概念**：`[关联的 teaches_concepts[i].id]`
   - **核心范畴**：[说明本子主题聚焦的内涵与认知跃迁目标]
   - **核心定理/准则名**：[本子主题下必须覆盖的核心公理/定理/引理/准则的纯学术名称，不写公式推导]

- [ ] **2. [子主题 2 学术规范名称]**
   - **承载概念**：`[关联的 teaches_concepts[i].id]`
   - **核心范畴**：[说明本子主题聚焦的内涵与认知跃迁目标]
   - **核心定理/准则名**：[纯学术名称，不写公式推导]

---

## 三、⚠️ 认知断点与典型考查方向
- **高频认知陷阱与反例**：
  - [陷阱/反例 1：切中该概念伪直觉或边界断点的典型情形]
  - [陷阱/反例 2：...]
- **掌握验收方向**：
  - [侧重定理条件检验、反例构造、几何意象辨析等维度，说明课后练习与掌握度检验的重点]
```
