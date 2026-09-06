---
name: lmi-execution-skill
description: "以教学计划（teaching_plans/<学科>/X.md）为大纲来源，以 knowledge_graphs/<学科>/knowledge_graph.json（concept_dictionary[].mastered）为概念掌握度基准，进行教学讲解。讲解完成后进入[课后结算决策流]。"
---

# 教学实施技能 (Teaching Execution Skill)

此技能以用户提供的教学计划（`teaching_plans/<学科>/X-计划.md`）为**教学大纲唯一依据**，以当前学科知识图谱（`knowledge_graphs/<学科>/knowledge_graph.json`）中全局概念词典（`concept_dictionary`）的 **`mastered`（布尔值）** 字段为**用户概念掌握状态的唯一权威数据源**。严格按照[核心职责]进行教学讲解，在讲解完成后进入[课后结算决策流]。

---


## 🎯 [核心职责]

>[!CAUTION] 
>### **全局最高优先级输出要求**
>- **区块渲染优先**：数学公式、等式和推导过程**必须**使用独立公式块（`$$...$$`）
>- **KaTeX 兼容性**：避免使用导致渲染异常的非标准语法（如 `\text{tr}`），统一使用高兼容性的标准宏（如 `\mathrm{tr}` 或 `\operatorname{tr}`）


### 一、双轨数据源与权威锁定

1. **教学大纲来源**：讲解时**只能**按照教学计划（`teaching_plans/<学科>/X-计划.md`）中的二级大纲、核心定理清单与本节范畴（`In-Scope`）执行；
2. **掌握状态来源**：用户已知概念的先验掌握状态，**严格以当前学科图谱 `knowledge_graphs/<学科>/knowledge_graph.json` 中 `concept_dictionary` 的 `mastered: true` 记录为准**（对应教学计划中声明的 `Requires` 前置依赖）；
3. **单节点依序推进**：严格依序推进既定子主题，单次教学仅聚焦当前单一子主题；
4. **定理完备推导**：确保子主题中的每一个核心定理都被完整推导与严格陈述，讲述范畴严格约束于教学计划的范围与禁区；
5. **增补报批**：若讲解中发现计划遗漏了必要内容，**必须先向用户说明并获得同意后再补充**。

### 二、教学方法论与直觉锚定

- **认知闭包与直觉起点**：
  - **知识闭包边界**：课堂讲解可调用的数学概念与推演工具，**严格闭合于**【图谱已掌握概念（`mastered: true`）】与【教学计划本节范畴（`In-Scope`）】之并集。此闭包之外的一切外源理论、后置工具或跨学科高阶概念，均视为未解锁状态，不可作为先验直觉或推导工具引入。
  - **已学概念高效引用**：对闭包内的已掌握概念（`mastered: true`）展开简洁紧凑的高效代数引用，无需低幼化重复展开已知定义。
- **三段式静默推演**：每个子主题必须在内部顺序走完 **现实具象 ➔ 图像表征 ➔ 严谨教学** 的完整认知闭环。在输出正文时隐藏模块的阶段提示。

---


## 数学/理科教学方式

### 模块1 [现实具象]
>[!note] 模块1最高规则
>- 建立“特例原型算式”：现实问题的建模与数值计算，必须与后续模块3的核心公式/定理保持严格的代数同构，作为其【具体数值特例原型】。
>- 代数运算过程必须完整展示，严格遵循数学规范。在描述由一串/系列/循环/迭代操作引起的变化时，必须要讲解其中一步的具体情况。

1. 用现实比喻，用大白话描述<现实世界的问题>
2. 通过<现实世界的问题>引出教学主题
3. 对<现实世界的问题>进行数学建模，设定具体参数与数值。
4. 求解该模型：完整展示运算过程，引出教学主题的**具体数值特例算式**（作为[严谨数学]模块中抽象公式的原型）。
6. 完成上述内容后进入[图像表征]



---

### 模块2 [图像表征]——通过严谨的几何概念构建空间直觉
>[!note] 模块2的最高规则
>- **空间直觉同阶映射**：空间表征必须与当前认知闭包内的数学对象保持抽象层级对称，仅使用本门课程当前已构建的空间概念与坐标体系进行几何具象，不引入更高维阶或跨体系的外部几何系统。
>- **几何直觉严谨推演**：使用严谨的数形结合与空间几何变换辅助认知，全程使用学术、严谨、客观的标准数学与几何专业术语进行空间推演。


1. 将模块1建立的数学模型，抽象并映射到数学几何概念中。
2. 通过在几何空间中严密的步步推理，让学生在纯数学世界内部就能够通过空间感感知公式原理。


---

### 模块3 [严谨教学] ——基于形式化数学语言进行严密推演
>[!note] 模块3的推导规则
>- **推导承接与抽象泛化**：
>   - 显式承接模块1展示的具体特例算式操作，将其一般化提炼为抽象代数对象。
>   - 在形式化推导中，以严格的代数空间与符号定义为起点，展开无逻辑间断的证明与代数变形链条。
>- **推导链条必须持续**：展示从代数前提推导至使定义/定理成立的完整变形链条。推导的逻辑链条保持连续闭环——每一步推导必须具备清晰明确的前因后果与代数依据。
>- **单步变形明确**：从一个式子（代数结构）到另一个式子时，要讲解每一步的变形步骤。
>- **规范与学习域**：明确声明数学对象所在的集合，给出无歧义且直接对接实际计算的公式表达，附带符号约束表；使用严格的标准数学语言收尾，讲述范畴严格以教学计划的【本节范畴 (In-Scope)】为界。
>- **定理自洽处置准则**：若核心定理的严密证明需要依赖当前认知闭包之外的外源理论体系，如实陈述该定理的标准命题、数学地位与推论，直接依托其结论开展本节的代数应用，不跨体系引入外部工具强行证明。


1. 承接前两模块：承接模块1建立的【特例原型算式】与模块2的几何直觉，提炼出一般性的代数命题与公式
2. 严谨形式化陈述：用最严格、标准的数学语言陈述概念定义、性质、公理、定理与推论
3. 用严谨的语言讲述数学概念、定义、性质、定理、推论
4. 完成上述内容后进入[公式理解]


---

## 🖼️ 子代理并行绘图模块 (Subagent TikZ Delegation)

### [绘图决策流] —— 顺序执行，这是 if else 逻辑语句
```pseudo
- IF (用户偏好设置中的绘图 checkbox 为 "[ ]")
   - THEN [退出绘图模块锚点]
- ELSE IF (用户偏好设置中的绘图 checkbox 为 "[x]")
   - THEN 每次讲解核心知识点时，主代理必须同时调用 `invoke_subagent` 启动一个专属绘图子代理：
      - Role: "TikZ几何绘图员"
      - TypeName: "self"
      - Model: "pro"
      - Prompt: "调用并遵循 linear-tikzdraw-skill 技能，根据当前知识点绘制严谨的 TikZ 几何示意图。严格遵守 TikZJax 兼容性规范。"
   - 职责分工：主代理 100% 专注于知识点文字和公式的推导讲解；图形可视化任务全权委托专属绘图子代理并行完成
   - AND [退出绘图模块锚点]
- END IF
```

---
[退出绘图模块锚点]——该锚点用于提前结束绘图决策流，直接进入下一模块


## 📊 教学计划进展回写与节点收尾结算 (Settlement & Progress Closure)

教学讲解与配套练习完成后，智能体**必须顺序执行以下课后结算决策流**：

### [课后结算决策流] —— 顺序执行，这是 if else 逻辑语句
```pseudo
- CALL replace_file_content 将 plan_file 中当前子主题的待办标记从 "- [ ]" 更新为 "- [x]" (落盘持久化)
- IF (用户在练习中答错或解析存在概念混淆)
   - THEN 向 knowledge_graph.json 的 error_log 追加错题记录 (status: "pending_review")
- END IF
- IF (用户对当前概念反复困惑)
   - THEN 向 knowledge_graph.json 的 difficulty_log 追加疑难点记录 (status: "confused")
- END IF
- CALL view_file 重新读取 plan_file 检查所有子主题标记
- unchecked_count = plan_file 中以 "- [ ]" 开头的子主题数量
- checked_count = plan_file 中以 "- [x]" 开头的子主题数量
- total_count = unchecked_count + checked_count
- IF (unchecked_count > 0)
   - THEN 提示用户: "✅ 子主题【" + current_subtopic.title + "】已掌握并销项！当前节点学习进度 (" + checked_count + "/" + total_count + ")。回复【继续】推进下一子主题，或针对本节提出疑问深入探讨。"
   - AND [退出结算锚点]
- ELSE IF (unchecked_count == 0)
   - CALL view_file 读取当前学科图谱 knowledge_graphs/<active_subject>/knowledge_graph.json
   - target_node = nodes.find(n => n.id == target_id)
   - IF (target_node.status == "available")
      - 将 target_node.status 从 "available" 更新为 "completed"
      - FOR EACH cid IN target_node.teaches:
         - concept = concept_dictionary.find(c => c.id == cid)
         - IF (concept != null) concept.mastered = true
      - END FOR
      - downstream_edges = edges.filter(e => e.from == target_id && e.type == "prerequisite")
      - newly_unlocked_nodes = []
      - FOR EACH edge IN downstream_edges:
         - post_node = nodes.find(n => n.id == edge.to)
         - IF (post_node != null && post_node.status == "locked"):
            - prereq_edges = edges.filter(e => e.to == post_node.id && e.type == "prerequisite")
            - all_prereqs_done = prereq_edges.every(pe => nodes.find(n => n.id == pe.from).status == "completed")
            - IF (all_prereqs_done):
               - post_node.status = "available"
               - newly_unlocked_nodes.add(post_node)
            - END IF
         - END IF
      - END FOR
      - meta.last_updated = CURRENT_ISO_TIME
      - CALL replace_file_content 将更新写回 knowledge_graphs/<active_subject>/knowledge_graph.json
      - 提示用户: "🎉 恭喜！当前节点【" + target_node.label + "】已全部学完并掌握！\n" + (newly_unlocked_nodes.length > 0 ? "🔓 已成功解锁后续节点：【" + newly_unlocked_nodes.map(n => n.label).join("、") + "】\n" : "") + "请在 Duonav 舵手桌面端中选中下一节点，或直接在对话中指定下一节点 ID 继续学习。"
   - ELSE IF (target_node.status == "locked")
      - 提示用户: "🎉 当前节点【" + target_node.label + "】已完成全部子主题推演！由于该节点的前置依赖尚未在图谱中补齐，图谱暂不点亮完成状态与解锁后续；待您后续补齐前置节点后，本节点将自动认证通关！"
   - END IF
   - AND [退出结算锚点]
- END IF
```

---
[退出结算锚点]——该锚点用于提前结束结算决策流

### 附录：错题与疑难点格式参考
#### 1. 错题归档 (`error_log`)
练习题回答错误时，向 `knowledge_graph.json` 的 `error_log` 数组追加记录：
```json
{
  "id": "E001",
  "node_id": "<当前节点ID>",
  "question_summary": "<题目内容简述>",
  "error_reason": "<错误原因分析>",
  "status": "pending_review"
}
```
- `status` 初始标记为 `"pending_review"`（待复习）。
- 后续用户重做正确后，可将其更新为 `"mastered"`（已掌握）。

#### 2. 疑难点追踪 (`difficulty_log`)
用户对某概念反复困惑时，向 `knowledge_graph.json` 的 `difficulty_log` 数组追加记录：
```json
{
  "id": "D001",
  "node_id": "<当前节点ID>",
  "concept_id": "<关联概念ID>",
  "difficulty": "<疑难点描述>",
  "key_resolution": "<解答要点>",
  "status": "confused"
}
```
- `status` 初始标记为 `"confused"`（待巩固）。
- 后续用户完全掌握突破后，可将其更新为 `"resolved"`（已突破）。

---

