---
name: lmi-outline-skill
description: "为新学科或教材建立知识图谱大纲、规划课程知识网络、重新生成学科 DAG 结构时使用。指导生成包含概念词典、拓扑依赖与活动指针的 knowledge_graph.json。"
---

# 知识图谱大纲生成技能 (Knowledge Graph Outline Skill)

本技能负责为学科生成有向无环图 (DAG) 形式的知识图谱 `knowledge_graph.json`。

核心机制遵循 **“语义生成 ➔ 脚本严格校验 ➔ 纯 JSON 协议通信 ➔ 结构化自审闭环”** 原则。三个阶段之间无需打扰用户，脚本的所有输出均为**纯 JSON 结构体**；若校验失败，智能体按需调阅外部诊断手册与脚本返回的确定性建议自愈收敛。

---

## 🎯 核心职责与任务背景

### 一、权威教材来源约束

1. **必须以权威学术教科书为依据**生成大纲，偏好经典学术教材，**而非**速成备考书籍；
2. **显式标注来源**：在 `knowledge_graph.json` 的 `meta.references` 字段中标注参考教材；
3. **用户指定优先**：若用户指定了特定教材，以用户指定的教材目录结构为骨架生成节点。

### 二、/grill-me 信息对齐（强制）

在进入三步生成流程前，**必须**通过 `/grill-me` 互动工具与用户对齐以下维度：

| 对齐项 | 说明 | 接口型规范说明 |
|--------|------|------|
| **学科与教材** | 学习学科与权威参考教材 | `<学科名称>` 与 `<权威参考教材全名>` |
| **学习范围** | 全书学习还是指定章节 | `<完整范围或具体起止章节>` |
| **学习目标** | 应试检验、科研探索或工程落地 | `<应试导向 / 科研应用 / 工程实践 / 兴趣自学>` |
| **节点粒度** | 单个节点适宜推演时长 | 15-25 分钟 或 30-45 分钟 |
| **已有基础** | 学习者已掌握的前置知识背景 | `<已掌握的数学或先验学科基础概念>` |

### 三、教材原版大纲收集与概念映射（应试目标触发 · 子代理并发指派）

>[!IMPORTANT]
>- IF 用户的学习目标是解决考试（应试导向，如期末考试、考研、考证、升学等）：
>   - THEN **必须**触发本模块。指派子代理收集教材原版二级大纲，建立“章节-概念”双轨映射。
>- ELSE IF 用户的目标是非应试（如科研探索、自主兴趣学习、工程落地、技术攻关等）：
>   - THEN **无需触发**本模块，直接跳出本模块至 [原版大纲退出锚点]。

当学习目标为**应试**时，主代理**异步指派子代理**自主收集原版大纲，主代理**同时并发执行自身图谱主线构建**：
1. **极简指派与并发执行**：
   - 主代理明确教材名称后，调用 `invoke_subagent`（Role: `教材大纲调研员`，Model: `flash`），传递书籍名称与输出规范。
   - 指派完成后，**主代理不等待子代理，立即并行启动自身的阶段一（提取节点与概念）**。
2. **子代理自主收集与格式约束**：
   - 子代理独立联网或检索该书籍真实原版目录（严格约束至两级：章 -> 节，禁止第三级小节）。
   - 子代理将目录写入 `textbook_outline_raw.json`，并执行 PowerShell 格式约束校验命令：
     ```powershell
     powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/build_textbook_outline.ps1 -InputFile textbook_outline_raw.json -OutputFile knowledge_graphs/<学科名称>/textbook_outline.json
     ```
   - 校验成功生成规范的 `textbook_outline.json` 后，子代理自动清理临时 raw 文件，并向主代理发送完成消息。
3. **教材原版大纲概念赋标产出**：
   - 主代理完成知识图谱（`knowledge_graph.json`）与全局概念词典（`concept_dictionary`）的构建后，读取子代理产出的 `textbook_outline.json`。
   - 将概念标签批量映射赋标到教材大纲的每个二级子章节（`concepts: ["C001", "C002", ...]`），规范输出 `knowledge_graphs/<学科名称>/textbook_outline.json`。

---

[原版大纲退出锚点]

## 🔄 [执行决策流]

### [大纲生成决策流]
```pseudo
START:
- EXECUTE /grill-me 与用户交互，对齐 (学科, 教材, 范围, 目标, 节点粒度, 已有基础)
- IF (学习目标为“解决考试 / 应试导向”):
    - THEN [异步并发指派子代理收集教材大纲] 调用 invoke_subagent，传入书籍名称与输出规范：
        - invoke_subagent(
            Role="教材大纲调研员", TypeName="self", Model="flash",
            Prompt="书籍名称: 《<教材全称>》\n任务目标: 自行检索收集该教材原版两级目录大纲（严格约束为两级：章 -> 节，严禁包含第三级小节）。\n输出规范: 先写入 textbook_outline_raw.json，再执行 PowerShell 格式约束脚本输出到学科专属目录：\npowershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/build_textbook_outline.ps1 -InputFile textbook_outline_raw.json -OutputFile knowledge_graphs/<学科名称>/textbook_outline.json\n完成后清理 raw 临时文件并向主代理汇报完成。"
          )
    - AND 不等待子代理，同时立即并发推进自身图谱任务 -> 进入 [PHASE_1]
- ELSE:
    - 进入 [PHASE_1]
- END IF

[PHASE_1] [阶段一: 提取节点与概念]:
- WHILE (阶段一未通过):
    - 根据对齐信息提炼节点列表，写入 "step1_nodes_raw.json"
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/step1_validate_nodes.ps1 -InputFile step1_nodes_raw.json -OutputFile step1_nodes.json`
    - response = PARSE_JSON(stdout)
    - IF (response.success == true):
        - 阶段一校验通过，确认生成标准规范文件 "step1_nodes.json"
        - BREAK WHILE -> [进入 PHASE_2]
    - ELSE:
        - CALL view_file 查看 ".agents/skills/lmi-outline-skill/resources/error_diagnosis_guide.md"
        - 结合 response.errors 中各错误的 type、定位与 suggestion，严格按手册确定性原语修正 "step1_nodes_raw.json"
        - 重试阶段一校验脚本
    - END IF
- END WHILE

[PHASE_2] [阶段二: 概念归一化与词典构建]:
- WHILE (阶段二未通过):
    - 读取 "step1_nodes.json"
    - 执行全局语义归一化：构建 concept_dictionary (含 canonical, aliases, taught_by)，将所有节点 teaches/requires 转为概念 ID
    - 写入草稿 "step2_concepts_raw.json"
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/step2_validate_concepts.ps1 -InputFile step2_concepts_raw.json -OutputFile step2_concepts.json`
    - response = PARSE_JSON(stdout)
    - IF (response.success == true):
        - 阶段二校验通过，确认生成标准规范文件 "step2_concepts.json"
        - BREAK WHILE -> [进入 PHASE_3]
    - ELSE:
        - CALL view_file 查看 ".agents/skills/lmi-outline-skill/resources/error_diagnosis_guide.md"
        - 结合 response.errors 中各错误的 type、定位与 suggestion，严格按手册确定性原语修正 "step2_concepts_raw.json"
        - 重试阶段二校验脚本
    - END IF
- END WHILE

[PHASE_3] [阶段三: 自动连边、拓扑验算与图谱组装]:
- WHILE (阶段三未通过):
    - RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/step3_build_graph.ps1 -InputFile step2_concepts.json -OutputFile "knowledge_graphs/<学科名称>/knowledge_graph.json" -Subject "<学科名称>"`
    - response = PARSE_JSON(stdout)
    - IF (response.success == true):
        - 图谱拓扑验证无误，确认生成 "knowledge_graphs/<学科名称>/knowledge_graph.json"
        - [活动学科指针规范创建]:
          RUN `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/set_active_subject.ps1 -Subject "<学科名称>"`
        - RUN `powershell -ExecutionPolicy Bypass -Command "Remove-Item 'step1_nodes_raw.json', 'step1_nodes.json', 'step2_concepts_raw.json', 'step2_concepts.json', 'knowledge_graphs/<学科名称>/tmp/*' -Recurse -Force -ErrorAction SilentlyContinue"`
        - IF (学习目标为应试导向):
            - 等待子代理发送完成消息或使用 Test-Path 校验 "knowledge_graphs/<学科名称>/textbook_outline.json" 就绪
            - IF (存在 "knowledge_graphs/<学科名称>/textbook_outline.json"):
                - 读取 "knowledge_graphs/<学科名称>/textbook_outline.json" 与 "knowledge_graphs/<学科名称>/knowledge_graph.json"
                - 为每个二级子章节匹配赋标 concepts 概念标签
                - 写回带概念标签的 "knowledge_graphs/<学科名称>/textbook_outline.json"
            - END IF
        - END IF
        - BREAK WHILE -> [进入 PHASE_4]
    - ELSE:
        - CALL view_file 查看 ".agents/skills/lmi-outline-skill/resources/error_diagnosis_guide.md" 中 CYCLE_DETECTED 章节
        - 根据 response.errors 中的 cycle_nodes 列表，在 "step2_concepts.json" 中解除环路 requires 依赖
        - 重试阶段三脚本
    - END IF
- END WHILE

[PHASE_4] 执行阶段4 [最终交付与完成收尾]
```

---

## 📋 各阶段 JSON 格式规范与协议参考（接口型抽象）

### 阶段一：节点数据格式参考 (`step1_nodes_raw.json`)
```json
{
  "nodes": [
    {
      "id": "<纯数字点分层级编号，如1.1>",
      "label": "<当前知识节点的学术规范名称>",
      "module": "<所属课程模块或章节名称>",
      "teaches": [
        "<该节点所传授核心概念1的定义名称>",
        "<该节点所传授核心概念2的定义名称>",
        "<……>"
      ],
      "requires": [
        "<该节点直接依赖的前置概念定义名称，无前置时填空数组[]>"
      ],
      "blackbox_terms": [
        {
          "term": "<预留黑盒术语名称>",
          "purpose": "<黑盒术语在当前阶段的辅助解释用途说明>",
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
      "id": "<概念唯一编号，格式如C001>",
      "canonical": "<该概念的标准学术规范名称>",
      "aliases": [
        "<该概念的同义学术别名或规范英文名，无别名时填空数组[]>"
      ],
      "taught_by": "<传授该概念的节点ID编号>",
      "mastered": false
    }
  ],
  "nodes": [
    {
      "id": "<节点ID编号>",
      "label": "<当前知识节点的学术规范名称>",
      "module": "<所属课程模块或章节名称>",
      "teaches": [
        "<已归一化的概念ID编号，如C001>"
      ],
      "requires": [
        "<已归一化的概念ID编号，如C002>"
      ],
      "blackbox_terms": []
    }
  ]
}
```

### 教材大纲数据格式参考 (`textbook_outline_raw.json`)
```json
{
  "title": "<权威教材全名规范字符串>",
  "author": "<主编/作者署名规范字符串>",
  "edition": "<版次规范字符串>",
  "chapters": [
    {
      "id": "<章编号，如Chapter 1>",
      "title": "<章标题规范字符串>",
      "sections": [
        {
          "id": "<节编号，如1.1>",
          "title": "<节标题规范字符串>"
        }
      ]
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

## 🏁 [最终交付与完成收尾]

流水线全部自动执行完毕并完成大纲与指针落盘后，模型**必须执行以下动作**：

1. **呈现图谱核心指标摘要**（直接读取阶段三 JSON 的 `metrics`）：
   - 节点数量、有向边数量、DAG 有向无环有效性
   - 并行度与图谱健康度评估
2. **确认交付文件清单**：
   - 核心知识图谱：`knowledge_graphs/<学科名称>/knowledge_graph.json`
   - 教材目录大纲（若生成）：`knowledge_graphs/<学科名称>/textbook_outline.json`
   - 活动学科指针：`knowledge_graphs/active_subject.json`
3. **独立交付指引**：
   - 提示用户：“学科【<学科名称>】的知识图谱大纲与活动追踪指针已成功建立。后续您可以直接调用 `lmi-plan-skill` 为目标知识节点制定教学计划，或在客户端中查看图谱结构。”
   - **收尾退出，不再做未经请求的后续跨技能调用。**

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
    ├── resources/
    │   └── error_diagnosis_guide.md          ← 外部资源：校验错误代码诊断与自愈操作手册
    └── scripts/
        ├── step1_validate_nodes.ps1          ← 脚本一：节点与字段规范校验 (输出结构化 JSON)
        ├── step2_validate_concepts.ps1       ← 脚本二：概念归一化与引用校验 (输出结构化 JSON)
        ├── step3_build_graph.ps1             ← 脚本三：自动连边、拓扑验算与图谱组装 (输出结构化 JSON)
        ├── build_textbook_outline.ps1        ← 脚本四：教材二级章节格式约束校验与组装 (输出结构化 JSON)
        └── set_active_subject.ps1            ← 脚本五：规范创建与更新活动学科指针
```
