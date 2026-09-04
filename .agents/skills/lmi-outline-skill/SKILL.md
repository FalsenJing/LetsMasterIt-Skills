---
name: lmi-outline-skill
description: "指导生成知识图谱大纲 knowledge_graph.json（有向无环图模式，含概念词典、依赖关系、成就追踪）。当用户开始学习新科目或需要重新规划学习路径时使用。"
---

# 强制执行
>[!important]
>调用该技能时，**必须**调用平台的"拷问"功能与用户对齐信息（例如：`/grill-me`）

---

# 知识图谱大纲生成技能 (Knowledge Graph Outline Skill)

此技能指导 AI 为新科目生成有向无环图 (DAG) 形式的知识图谱 `knowledge_graph.json`，取代传统的线性大纲。

核心机制遵循 **“AI 语义生成 ➔ 脚本严格校验 ➔ 纯 JSON 协议通信 ➔ 模型结构化自审闭环”** 原则。在生成过程中，**三个阶段之间无需打扰用户**，脚本的所有输出均为**纯 JSON 结构体**，模型直接解析脚本返回的 JSON 对象执行决策流。

---

## 🎯 核心职责

### 一、权威教材来源约束

1. **必须以权威国际教科书为依据**生成大纲，偏好学术教材，**而非**备考书籍
2. **显式标注来源**：在 `knowledge_graph.json` 的 `meta.references` 字段中标注参考教材
3. **用户指定优先**：若用户指定了特定教材，以用户指定的为准
4. 如果用户指定了某教材，则以该教材的章节结构为骨架生成节点

### 二、/grill-me 信息对齐（强制）

在进入三步生成流程前，**必须**通过 `/grill-me` 互动工具与用户对齐以下维度：

| 对齐项 | 说明 | 示例 |
|--------|------|------|
| **学科与教材** | 学什么？用什么教材？ | "概率论，浙大版第五版" |
| **学习范围** | 全书还是特定章节？ | "只学前四章" |
| **学习目标** | 应试/科研/工程应用？ | "期末考试" |
| **⭐ 节点粒度** | 每个节点大约对应多长的学习时间？ | "每节点约 20-30 分钟" |
| **已有基础** | 哪些知识已经掌握？ | "高中数学、集合论基础" |

> [!important]
> **节点粒度**是必须显式询问的关键参数。它决定知识点的分割细度，直接影响图谱的节点数量和依赖密度。

### 三、教材原版大纲收集与概念映射（应试目标触发 · 子代理并发指派）

> [!important]
> **触发条件严格限定**：
> - **IF 用户的学习目标是解决考试（应试导向，如期末考试、考研、考证、升学等）**：**必须触发**本模块。应试场景高度依赖指定教材或官方考纲教材的章节覆盖度，因此必须指派子代理收集教材原版二级大纲，建立“章节-概念”双轨映射。
> - **ELSE IF 用户的目标是非应试（如科研探索、自主兴趣学习、工程落地、技术攻关等）**：**无需触发**本模块，不生成 `textbook_outline.json`，图谱构建与成就追踪 100% 聚焦于知识点本身的 DAG 概念网络。

当学习目标为**应试**时，主代理**异步指派子代理**自主收集原版大纲，主代理**同时并发执行自身图谱主线构建**：
1. **极简指派与并发执行**：
   - 主代理无需操心大纲收集细节，也无需给子代理提供概念体系。
   - 主代理明确教材（若用户在 `/grill-me` 中已指定则采用指定书籍；若未指定则采用该应试学科最通用的权威教材，如“同济版高等数学”、“浙大版概率论”等）。
   - 主代理调用 `invoke_subagent`（Role: `教材大纲调研员`，Model: `flash`），**仅向子代理传递「书籍名称」与「输出规范」**。
   - 指派完成后，**主代理不等待子代理，立即并行启动自身的阶段一（提取节点与概念）**。
2. **子代理自主收集与格式约束**：
   - 子代理独立联网或检索该书籍真实原版目录（严格约束至两级：章 -> 节，禁止第三级小节）。
   - 子代理将目录写入 `textbook_outline_raw.json`，并执行 PowerShell 格式约束校验命令：
     ```powershell
     powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/build_textbook_outline.ps1 -InputFile textbook_outline_raw.json -OutputFile textbook_outline.json
     ```
   - 校验成功生成规范的 `textbook_outline.json` 后，子代理自动清理临时 raw 文件，并向主代理发送完成消息。
3. **教材原版大纲概念赋标产出**：
   - 主代理完成知识图谱（`knowledge_graph.json`）与全局概念词典（`concept_dictionary`）的构建后，读取子代理产出的 `textbook_outline.json`。
   - 将概念标签批量映射赋标到教材大纲的每个二级子章节（`concepts: ["C001", "C002", ...]`），规范输出 `knowledge_graphs/<学科名称>/textbook_outline.json`。

---

## 🔄 纯 JSON 通信协议流水线（执行决策流）

### [大纲生成决策流] —— 顺序执行，这是 if else / loop / switch 逻辑语句

```pseudo
START:
- EXECUTE /grill-me 与用户交互，对齐 (学科, 教材, 范围, 目标, 节点粒度, 已有基础)
- IF (学习目标为“解决考试 / 应试导向”):
    - [异步并发指派子代理收集教材大纲] 主代理调用 invoke_subagent，仅传入书籍名称与输出规范：
        - invoke_subagent(
            Role="教材大纲调研员", TypeName="research", Model="flash",
            Prompt="书籍名称: 《<指定书籍或权威应试教材>》\n任务目标: 自行检索收集该教材原版两级目录大纲（严格约束为两级：章 -> 节，严禁包含第三级小节）。\n输出规范: 先写入 textbook_outline_raw.json，再执行 PowerShell 格式约束脚本输出到学科专属目录：\npowershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/build_textbook_outline.ps1 -InputFile textbook_outline_raw.json -OutputFile knowledge_graphs/<学科名称>/textbook_outline.json\n完成后清理 raw 临时文件并向主代理汇报完成。"
          )
    - [主代理不等待子代理，同时立即并发推进自身图谱任务] -> 进入 PHASE_1
- ELSE:
    - [非应试目标（如科研/自学/工程应用等）]: 无需收集教材大纲，主代理直接进入 PHASE_1
- END IF

PHASE_1 [阶段一: 提取节点与概念]:
- WHILE (阶段一未通过):
    - AI 根据对齐信息提炼节点列表，写入 "step1_nodes_raw.json"
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/step1_validate_nodes.ps1 -InputFile step1_nodes_raw.json -OutputFile step1_nodes.json`
    - response = PARSE_JSON(stdout)
    - IF (response.success == true):
        - 阶段一校验通过，确认生成标准规范文件 "step1_nodes.json"
        - BREAK WHILE -> [进入 PHASE_2]
    - ELSE:
        - FOR EACH err IN response.errors:
            - SWITCH (err.type):
                - CASE "MISSING_FIELD": AI 补全节点缺失字段 (如 id, label, module)
                - CASE "EMPTY_TEACHES": AI 为节点补充教授的核心概念
                - CASE "INVALID_ID_FORMAT": AI 调整为规范格式 (如 1.1, 2.3)
                - DEFAULT: AI 读取 err.message 修复相应 JSON 数据
            - END SWITCH
        - END FOR
        - 重新写回 "step1_nodes_raw.json" 并重试
    - END IF
- END WHILE

PHASE_2 [阶段二: 概念归一化与词典构建]:
- WHILE (阶段二未通过):
    - AI 读取 "step1_nodes.json"
    - AI 执行全局语义归一化：构建 concept_dictionary (含 canonical, aliases, taught_by)，将所有节点 teaches/requires 转为概念 ID
    - 写入草稿 "step2_concepts_raw.json"
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/step2_validate_concepts.ps1 -InputFile step2_concepts_raw.json -OutputFile step2_concepts.json`
    - response = PARSE_JSON(stdout)
    - IF (response.success == true):
        - 阶段二校验通过，确认生成标准规范文件 "step2_concepts.json"
        - BREAK WHILE -> [进入 PHASE_3]
    - ELSE:
        - FOR EACH err IN response.errors:
            - SWITCH (err.type):
                - CASE "DUPLICATE_CANONICAL_NAME": AI 合并重复概念，将多余名称转入 aliases
                - CASE "TAUGHT_BY_MISMATCH": AI 修正 concept.taught_by 与 node.teaches 声明的一致性
                - CASE "UNRESOLVED_REQUIRES_CONCEPT": AI 检查缺失概念，在词典中补全或修正 ID
                - CASE "SELF_DEPENDENCY": AI 解除节点的自依赖
                - DEFAULT: AI 读取 err.message 修复相应 JSON 数据
            - END SWITCH
        - END FOR
        - 重新写回 "step2_concepts_raw.json" 并重试
    - END IF
- END WHILE

PHASE_3 [阶段三: 自动连边、拓扑验算与图谱组装]:
- WHILE (阶段三未通过):
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/step3_build_graph.ps1 -InputFile step2_concepts.json -OutputFile "knowledge_graphs/<学科名称>/knowledge_graph.json" -Subject "<学科名称>"`
    - response = PARSE_JSON(stdout)
    - IF (response.success == true):
        - 图谱拓扑验证无误，确认生成 "knowledge_graphs/<学科名称>/knowledge_graph.json"
        - [活动学科指针规范创建]:
          RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/set_active_subject.ps1 -Subject "<学科名称>"`
        - RUN `powershell -ExecutionPolicy Bypass -Command "Remove-Item 'step1_nodes_raw.json', 'step1_nodes.json', 'step2_concepts_raw.json', 'step2_concepts.json' -ErrorAction SilentlyContinue"`
        - IF (存在 "knowledge_graphs/<学科名称>/textbook_outline.json"):
            - 主代理读取 "knowledge_graphs/<学科名称>/textbook_outline.json" 与 "knowledge_graphs/<学科名称>/knowledge_graph.json"
            - 主代理为每个二级子章节匹配赋标 concepts 概念标签
            - 主代理写回带概念标签的 "knowledge_graphs/<学科名称>/textbook_outline.json"
        - END IF
        - BREAK WHILE -> [进入 PHASE_4]
    - ELSE:
        - FOR EACH err IN response.errors:
            - SWITCH (err.type):
                - CASE "CYCLE_DETECTED":
                    - AI 提取 err.cycle_nodes (死锁成环的节点列表)
                    - AI 反思打破逻辑闭环所需解除的概念依赖
                    - AI 修改 "step2_concepts.json" 移除或调整成环的 requires 概念
                - DEFAULT:
                    - AI 读取 err.message 修复相关数据
            - END SWITCH
        - END FOR
        - 重试阶段三脚本
    - END IF
- END WHILE

PHASE_4 执行阶段4[最终交付与强制审批]
```

---

## 📋 各阶段 JSON 格式规范与协议参考

### 阶段一：节点数据格式参考 (`step1_nodes_raw.json`)
```json
{
  "nodes": [
    {
      "id": "1.3",
      "label": "概率的公理化定义",
      "module": "第一章 · 概率论基础",
      "teaches": ["概率公理", "可列可加性", "概率性质"],
      "requires": ["事件运算"],
      "blackbox_terms": [
        {
          "term": "测度",
          "purpose": "将概率推广为一种对集合大小的度量方式",
          "target_node": null
        }
      ]
    }
  ]
}
```

### 阶段二：归一化数据格式参考 (`step2_concepts_raw.json`)
```json
{
  "concept_dictionary": [
    {
      "id": "C005",
      "canonical": "事件运算",
      "aliases": ["事件的并交补", "集合运算", "德摩根律"],
      "taught_by": "1.2",
      "mastered": false
    }
  ],
  "nodes": [
    {
      "id": "1.3",
      "label": "概率的公理化定义",
      "module": "第一章 · 概率论基础",
      "teaches": ["C006", "C007"],
      "requires": ["C005"],
      "blackbox_terms": [...]
    }
  ]
}
```

### 阶段三：最终产出指标结构 (`response.metrics`)
```json
{
  "success": true,
  "step": 3,
  "output_file": "knowledge_graph.json",
  "metrics": {
    "node_count": 8,
    "edge_count": 7,
    "is_dag": true,
    "critical_path_length": 5,
    "critical_path": ["1.1", "1.2", "1.3", "1.4", "1.5"],
    "parallelism": 1.6,
    "is_healthy": true,
    "isolated_nodes": []
  }
}
```

---

## 🏁 [最终交付与强制审批]

流水线全部自动执行完毕并完成大纲与指针落盘后，模型**必须执行以下动作**：

1. **呈现图谱核心指标摘要**（直接读取阶段三 JSON 的 `metrics`）：
   - 节点数量、有向边数量、DAG 有向无环有效性
   - 关键学习路径长度及链路顺序
   - 并行度与图谱健康度评估
2. **确认交付文件清单**：
   - 核心知识图谱：`knowledge_graphs/<学科名称>/knowledge_graph.json`
   - 教材目录大纲（若生成）：`knowledge_graphs/<学科名称>/textbook_outline.json`
   - 活动学科指针：`knowledge_graphs/active_subject.json`
3. **交互指引与后续审批**：
   - 提示用户：“知识图谱大纲与活动追踪指针已成功建立。若无需调整，请确认审批通过；后续可调用 `lmi-plan-skill` 为具体知识节点制定教学计划。”
   - **停下调用工具，等待用户审批。**

---

## 📁 模块与目录清单

```
工作区根目录/
├── knowledge_graphs/                          ← 统一知识库大纲目录 (复数命名)
│   ├── active_subject.json                    ← 活动学科指针文件
│   └── <学科名称>/                            ← 学科子文件夹包 (支持中文，如：高等数学、线性代数)
│       ├── knowledge_graph.json               ← 核心知识图谱数据文件
│       └── textbook_outline.json              ← 教材原版两级大纲（含概念标签，可选）
└── .agents/skills/lmi-outline-skill/
    ├── SKILL.md                              ← 本技能规范
    └── scripts/
        ├── step1_validate_nodes.ps1          ← 脚本一：节点与字段规范校验 (输出结构化 JSON)
        ├── step2_validate_concepts.ps1       ← 脚本二：概念归一化与引用校验 (输出结构化 JSON)
        ├── step3_build_graph.ps1             ← 脚本三：自动连边、拓扑验算与图谱组装 (输出结构化 JSON)
        ├── build_textbook_outline.ps1        ← 脚本四：教材二级章节格式约束校验与组装 (输出结构化 JSON)
        └── set_active_subject.ps1            ← 脚本五：规范创建与更新活动学科指针 active_subject.json (输出结构化 JSON)
```
