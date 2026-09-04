---
name: lmi-plan-skill
description: "以 knowledge_graph.json 为唯一可信来源，读取用户在 Duonav 桌面端中选中的当前学习节点（selected_node），为该最小知识节点制定详细教学计划并等待用户审批。"
---

# 教学计划制定技能 (Teaching Plan Skill)

此技能指导 AI 以 `knowledge_graph.json` 为**唯一可信来源**，读取用户在 Duonav 桌面端中选中的当前学习节点（`selected_node`），为该单一最小知识节点制定教学计划，并等待用户审批。

> [!IMPORTANT]
> 本技能**只规划“讲什么”，不规划“怎么讲”**。严禁在计划阶段展开详细数学公式推导或进行正文教学。

---

## 🎯 核心职责与决策流

### 一、节点获取决策流 (Node Selection Decision Flow)

收到制定计划指令时，智能体**必须顺序执行以下决策流**：

```pseudo
- CALL view_file 读取 "knowledge_graphs/active_subject.json"
- IF "knowledge_graphs/active_subject.json" 存在:
    - active_subject = json.active_subject
    - graph_path = "knowledge_graphs/" + active_subject + "/knowledge_graph.json"
- ELSE:
    - active_subject = "默认学科"
    - graph_path = "knowledge_graph.json"
- CALL view_file 读取 graph_path
- IF graph_path 文件不存在:
    - 提示用户: "未检测到知识图谱大纲，请先调用 lmi-outline-skill 生成知识图谱"
    - STOP_CALLING_TOOLS (退出)
- ELSE:
    - target_id = json.selected_node
    - IF (target_id == null 或 target_id == ""):
        - 提示用户: "⚠️ 在当前学科【" + active_subject + "】中未检测到已选学的节点。请先在 Duonav 桌面端中点击目标节点并选择「⭐ 设为当前学习节点」（桌面端会自动落盘写回 JSON），或直接在对话中指定你想学习的节点 ID（例如：1.3）。"
        - STOP_CALLING_TOOLS (退出，等待用户选择)
    - ELSE:
        - target_node = json.nodes.find(n => n.id == target_id)
        - [执行前置依赖检查]
            - prereq_edges = json.edges.filter(e => e.to == target_id && e.type == "prerequisite")
            - uncompleted_prereqs = []
            - FOR EACH edge IN prereq_edges:
                - from_node = json.nodes.find(n => n.id == edge.from)
                - IF (from_node.status != "completed"):
                    - uncompleted_prereqs.add(from_node)
                - END IF
            - END FOR
            - IF (uncompleted_prereqs.length > 0):
                - 输出提示: "⚠️ 检测到前置节点 [列表] 尚未完成学习。建议先学习这些前置内容，或确认是否跳过前置直接学习当前节点。"
                - (若用户未明确说明跳过，暂停等待用户确认；若用户要求跳过或前置已全完成，则继续)
            - END IF
        - [进入教学计划生成阶段]
    - END IF
- END IF
```

---

## 📐 教学计划生成规范

教学计划必须保存至：`teaching_plans/<节点ID> <节点名称>-计划.md`（例如：`teaching_plans/1.3 概率的公理化定义-计划.md`）。

计划文件必须严格包含以下五个标准化区段：

### 1. 📋 [内容大纲]
- 本节点的完整标题、所属模块
- **子主题划分**：将该节点自然分解为若干个原子级子主题（根据知识内涵灵活划分，不设硬性数量限制）
  - **原子性**：每个子主题对应一个不可再分的独立概念或解题模型
  - **逻辑递进**：子主题之间存在清晰由浅入深的推演关系
  - **完备性**：子主题并集完全覆盖该节点教材内容

### 2. 📐 核心公式与定理清单
- 列出本节将要出现的核心公式、性质与定理名称及类型（**仅列名，不展开推导，严禁写出具体数学公式**）
- 列出特色模式/经典题型的公式解决方法名称

### 3. 🔗 概念与前置知识依赖
- **本节教授概念 (Teaches)**：读取 `target_node.teaches` 中的概念 ID，对照 `concept_dictionary` 查出其标准名（`canonical`）与别名（`aliases`）
- **前置概念依赖 (Requires)**：读取 `target_node.requires` 中的概念，并提取 `edges` 中关于本节点的 `reason`（依赖原因）
- **前置已掌握节点回顾**：说明理解本节需要调用之前哪些节点的直觉

### 4. 🏷️ 分节教学路线
- 只列出子主题名称与概要内容，采用 Markdown checkbox 格式，供后续教学时追踪进度：
```markdown
- [ ] **子主题 1：[名称]**
  - 内容概要：[说明]
- [ ] **子主题 2：[名称]**
  - 内容概要：[说明]
```

### 5. ✍️ 配套练习预告
- **高频陷阱针对性**：预告切中该知识点“伪直觉”或概念混淆断点的题目类型
- **杜绝低效死算**：侧重定理条件检验、反例构造、几何意象辨析的考题类型
- **错题闭环机制说明**：讲完后引导自主作答，若答错将自动记入 `knowledge_graph.json` 的 `error_log` 中

---

## 🏁 强制审批与后续引导

教学计划生成至 `teaching_plans/` 目录下后，智能体**必须停下**，向用户呈现：

1. 告知用户计划已生成：`teaching_plans/<节点ID> <节点名称>-计划.md`
2. 输出计划概要（子主题路线与核心概念）供用户审查
3. **严格等待用户确认**：
   - 用户若回复「调整 X」：修改计划文件后重新等待确认
   - 用户确认满意后，提示：“教学计划已锁定。若开始学习，建议开启新的聊天窗口，调用 `lmi-execution-skill` 技能并引用该计划文件开始详细教学。”
4. **严禁**在用户显式确认前开始任何正文教学。
