---
name: lmi-plan-skill
description: "以 knowledge_graph.json 为知识拓扑与概念覆盖基准，读取用户当前选中的学习节点（selected_node），为该单一最小知识节点制定规范的二级大纲与概念完备性教学清单，并等待用户审批。"
---

# 教学计划制定技能 (Teaching Plan Skill)

以 `knowledge_graph.json` 为**知识拓扑与概念覆盖基准**，为当前选中的单一最小知识节点（`selected_node`）制定**二级大纲与教学完备性清单（Secondary Syllabus & Checklist Contract）**，作为该节点课堂教学实施的唯一交付与验收依据。

> [!IMPORTANT]
> ### 核心设计原则与边界
> 1. **教科书大纲范式（纯粹性）**：本技能**只规划“讲什么”，不规划“怎么讲”**。遵循权威学术教科书大纲规范，**仅列出概念、定理、引理与小节名称，严禁在大纲中写出具体数学公式或展开代数推导**。
> 2. **概念完备性（Concept Completeness）**：大纲的完备性以**概念全覆盖**为唯一检验标尺——必须 100% 覆盖图谱中声明的 `target_node.teaches` 概念，确保本节点所含概念全部被二级大纲吸收承载。
> 3. **三段式教学粒度对齐**：每一个子主题的体量，**必须且只能支撑一轮完整的自底向上三段式推演（[现实具象] ➔ [图像表征] ➔ [严谨教学]）独立认知闭环**。既不可拆得过碎导致具象化牵强，也不可合得过粗导致单轮无法讲透。
> 4. **教科书命名规范**：子主题标题必须采用**客观、凝炼的学术名词或并列短语**，完全贴近真实权威教科书节内小标题。

---

## 🎯 核心职责与执行流程

收到制定计划指令时，智能体**必须顺序执行以下伪代码决策流**：

```pseudo
START:
- [步骤 1: 定位学科与图谱路径]
    - CALL view_file 读取 "knowledge_graphs/active_subject.json"
    - IF "knowledge_graphs/active_subject.json" 存在:
        - active_subject = json.active_subject
        - graph_path = "knowledge_graphs/" + active_subject + "/knowledge_graph.json"
    - ELSE:
        - active_subject = "默认学科"
        - graph_path = "knowledge_graph.json"
    - CALL view_file 读取 graph_path

- [步骤 2: 目标节点解析与状态落盘 (Target Resolution)]
    - IF (用户在当前对话中显式指定了节点 ID, 如 "学 1.3" 或 "制定 2.1 计划"):
        - target_id = 用户指定的节点 ID
        - IF (json.selected_node != target_id):
            - CALL replace_file_content 将 graph_path 中的 selected_node 更新为 target_id (落盘持久化)
        - END IF
    - ELSE:
        - target_id = json.selected_node
        - IF (target_id == null 或 target_id == ""):
            - 提示用户: "⚠️ 在当前学科【" + active_subject + "】中未检测到已选学的节点。请直接在对话中指定你想学习的节点 ID（例如：1.3）。"
            - STOP_CALLING_TOOLS (退出，等待用户输入)
        - END IF
    - END IF
    - target_node = json.nodes.find(n => n.id == target_id)

- [步骤 3: 提取概念体系与约束 (Context Extraction)]
    - teaches_concepts = []
    - FOR EACH cid IN target_node.teaches:
        - concept = json.concept_dictionary.find(c => c.id == cid)
        - teaches_concepts.add(concept)
    - END FOR
    - requires_concepts = []
    - FOR EACH cid IN target_node.requires:
        - concept = json.concept_dictionary.find(c => c.id == cid)
        - edge = json.edges.find(e => e.to == target_id && e.via_concept == cid && e.type == "prerequisite")
        - edge_reason = (edge && edge.reason) ? edge.reason : ("[" + target_node.label + "] requires [" + concept.canonical + "]")
        - requires_concepts.add({ concept: concept, reason: edge_reason })
    - END FOR
    - references = json.meta.references
    - IF (存在 "knowledge_graphs/" + active_subject + "/textbook_outline.json"):
        - CALL view_file 读取教材大纲作为结构与学术命名参考
    - END IF

- [步骤 4: 构建二级大纲与完备性校验 (Syllabus Construction)]
    - 按照由浅入深的认知递进，将 teaches_concepts 分解为若干个不可再分的原子子主题
    - 校验完备性: 确保 ∪(各子主题承载概念) == target_node.teaches (100% 概念全覆盖)
    - 明确声明本节范畴 (In-Scope) 与严禁提前引入的后置工具/超纲代数方法 (Out-of-Scope / 禁区)
    - 提炼各子主题下的核心定理、公理、引理或判定准则的标准学术名称 (不写具体数学公式)

- [步骤 5: 产物落盘与中立交付 (Persistence & Handover)]
    - plan_path = "teaching_plans/" + active_subject + "/" + target_id + " " + target_node.label + "-计划.md"
    - CALL write_to_file 将符合标准化格式的 Markdown 写入 plan_path
    - 输出计划摘要 (包含子主题、承载概念与核心定理名) 供用户审查
    - 提示用户: "📋 教学计划（二级大纲）已生成至 " + plan_path + "。请审查大纲内容与范围边界：如需调整子主题请指出；若确认无误，可随时基于本计划启动课堂教学。"
    - STOP_CALLING_TOOLS (严格等待用户显式确认)
```

---

## 📐 教学计划标准化格式规范

教学计划 Markdown 文件必须严格包含以下三个标准化板块，杜绝任何结构重复：

```markdown
# 教学计划：[节点ID] [节点名称]

## 一、🎯 概念目标与教学边界
- **所属模块**：[所属章节 · 模块名称]
- **本节教授概念 (Teaches)**：
  - `[概念ID]`【[概念标准名]】（别名：[别名1, 别名2...]）
- **前置依赖概念 (Requires)**：
  - `[概念ID]`【[概念标准名]】（依赖原因：[提取自 edges 的 reason]）
- **教学边界与禁区 (Boundary)**：
  - ✅ **本节范畴**：[说明本节点聚焦的核心推演范畴]
  - 🚫 **本节禁区**：[明确指出严禁提前超纲调用的后置概念、算法或代数工具]

---

## 二、📋 二级大纲与核心定理清单
*(本节共划分 N 个子主题，每个子主题支撑一轮完整的 [现实具象 ➔ 图像表征 ➔ 严谨教学] 三段式闭环)*

- [ ] **1. [子主题 1 学术规范名称]**
   - **承载概念**：`[概念ID]`
   - **核心范畴**：[说明本子主题聚焦的内涵与认知跃迁目标]
   - **核心定理/准则名**：[本子主题下必须覆盖的核心公理/定理/引理/准则的纯学术名称，不写公式]

- [ ] **2. [子主题 2 学术规范名称]**
   - **承载概念**：`[概念ID]`
   - **核心范畴**：[说明本子主题聚焦的内涵与认知跃迁目标]
   - **核心定理/准则名**：[纯学术名称，不写公式]

---

## 三、⚠️ 认知断点与典型考查方向
- **高频认知陷阱与反例**：
  - [陷阱/反例 1：切中该概念伪直觉或边界断点的典型情形]
  - [陷阱/反例 2：...]
- **掌握验收方向**：
  - [侧重定理条件检验、反例构造、几何意象辨析等维度，说明课后练习与掌握度检验的重点]
```

