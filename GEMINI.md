**路径对齐 (Pre-Teaching Path Alignment)**：
收到用户的教学请求后、开始任何讲解或制定教学计划之前，**必须**先执行[决策流]：

### [决策流] ——每次会话都执行，且是顺序执行，这是if else逻辑语句
```pseudo
- WORKSPACE_ROOT = 本文件 (GEMINI.md) 所在目录的绝对路径

- IF 用户发出教学请求、开始任何讲解或制定教学计划
   - THEN 执行**学科与节点状态探测**：
      - active_subject = ""
      - IF (用户在当前对话中显式指定了学科名称或要求切换学科，例如：“切换到线性代数”、“学人工智能数学基础”)
         - specified_subject = 提取用户指定的学科名称
         - IF (存在有效图谱 WORKSPACE_ROOT + "/knowledge_graphs/" + specified_subject + "/knowledge_graph.json")
            - CALL run_command 执行 `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/set_active_subject.ps1 -Subject "<specified_subject>"` 更新活动指针
            - active_subject = specified_subject
         - ELSE
            - 提示用户：“⚠️ 未检测到学科【" + specified_subject + "】的知识图谱。”并询问是否要调用 `.agents\skills\lmi-outline-skill` 初始化该新学科的大纲与指针
            - IF 调用该技能
               - THEN 调用平台“拷问”工具(例如：/grill-me)与用户对齐信息，进行知识图谱大纲与活动指针的初始化
               - AND [退出决策流锚点]
            - ELSE [退出决策流锚点]
         - END IF
      - END IF

      - node_arg = ""
      - IF (用户在当前对话中显式指定了节点 ID，例如 “学 1.3” 或 “制定 2.1 计划”)
         - target_node_id = 提取用户指定的节点 ID
         - node_arg = "-NodeId \"" + target_node_id + "\""
      - END IF

      - subject_arg = ""
      - IF (active_subject != "")
         - subject_arg = "-Subject \"" + active_subject + "\""
      - END IF
      - CALL run_command 执行 `powershell -ExecutionPolicy Bypass -File .agents/scripts/get_knowledge_graph.ps1 <subject_arg> <node_arg>`
      - probe = PARSE_JSON(stdout)

      - IF (probe.success == false)
         - IF (probe.error == "GRAPH_NOT_FOUND")
            - 提示用户：“⚠️ 未检测到学科【" + probe.active_subject + "】的知识图谱。”并询问是否要调用 `.agents\skills\lmi-outline-skill` 初始化该学科
            - IF 调用该技能
               - THEN 调用平台“拷问”工具(例如：/grill-me)与用户对齐信息，进行知识图谱大纲与活动指针的初始化
               - AND [退出决策流锚点]
            - ELSE [退出决策流锚点]
         - ELSE IF (probe.error == "NO_SELECTED_NODE")
            - 提示用户: probe.message
            - AND [退出决策流锚点]
         - ELSE IF (probe.error == "NODE_NOT_FOUND")
            - 提示用户: probe.message
            - AND [退出决策流锚点]
         - ELSE
            - 提示用户: probe.message
            - AND [退出决策流锚点]
         - END IF
      - END IF

      - active_subject = probe.active_subject
      - target_node = probe.node
      - target_id = probe.target_id
      - has_plan = probe.plan.has_plan
      - plan_file = probe.plan.plan_file

      - IF (!has_plan)
         - THEN 提示用户: "📍 路径对齐：" + target_node.position_summary + "。正在制定教学计划..."
         - AND 调用 `lmi-plan-skill` 技能，传入 active_subject 与 target_id
         - AND 询问用户是否要开启`.agents\skills\linear-tikzdraw-skill\SKILL.md` 技能，并告知用户：“该技能为实验性技能，旨在`obsidian`中提供可视化内容，如无需要，建议保持默认禁止调用状态”。如果用户要求开启，则将[用户偏好设置]的checkbox标记为`[x]`。
         - AND [退出决策流锚点]
      - ELSE IF (用户在当前对话中显式表达“重新制定计划 / 重新规划 / 修改计划 / 调整大纲”) # 特殊情况：教案已存在但用户主动要求重制或调整
         - THEN 提示用户: "📍 重新规划：【" + target_node.label + "】。正在重新制定教学计划..."
         - AND 调用 `lmi-plan-skill` 技能，传入 active_subject 与 target_id
         - AND 询问用户是否要开启`.agents\skills\linear-tikzdraw-skill\SKILL.md` 技能，并告知用户：“该技能为实验性技能，旨在`obsidian`中提供可视化内容，如无需要，建议保持默认禁止调用状态”。如果用户要求开启，则将[用户偏好设置]的checkbox标记为`[x]`。
         - AND [退出决策流锚点]
      - ELSE
         - CALL view_file 读取 plan_file
         - unchecked_subtopics = 提取 plan_file 中所有以 "- [ ]" 开头的子主题
         - checked_subtopics = 提取 plan_file 中所有以 "- [x]" 开头的子主题
         - IF (unchecked_subtopics 数量 > 0)
            - current_subtopic = unchecked_subtopics[0]
            - IF (probe.prerequisites.is_locked || !probe.prerequisites.all_completed)
               - THEN 提示用户: "💡 检测到节点【" + target_node.label + "】的前置依赖尚未全部掌握。已开启【跳级旁听模式】：本次教学将默认具备相关基础直接展开推演；为保证图谱真实性，学完后暂不点亮完成状态与解锁后置节点。"
            - ELSE
               - 确认位置、前置节点 status 状态，[输出路径对齐摘要]。
            - END IF
            - IF (checked_subtopics 数量 > 0)
               - 提示用户: "📍 断点续学：【" + target_node.label + "】进度 (" + checked_subtopics.length + "/" + (checked_subtopics.length + unchecked_subtopics.length) + ")。本次继续推进子主题：【" + current_subtopic.title + "】"
            - ELSE
               - 提示用户: "📍 开始学习：【" + target_node.label + "】。本次聚焦子主题 1：【" + current_subtopic.title + "】"
            - END IF
            - 调用 `lmi-execution-skill` 技能，传入 plan_file 与 current_subtopic，用以定位当前教学子主题。
            - AND [退出决策流锚点]
         - ELSE IF (所有子主题均为 "- [x]")
            - IF (probe.prerequisites.all_completed)
               - IF (target_node.status != "completed")
                  - target_node.status = "completed"
                  - FOR EACH cid IN target_node.teaches:
                     - c = json.concept_dictionary.find(x => x.id == cid)
                     - IF (c != null) c.mastered = true
                  - END FOR
                  - downstream_edges = json.edges.filter(e => e.from == target_id && e.type == "prerequisite")
                  - FOR EACH edge IN downstream_edges:
                     - post_node = json.nodes.find(n => n.id == edge.to)
                     - IF (post_node != null && post_node.status == "locked"):
                        - p_edges = json.edges.filter(e => e.to == post_node.id && e.type == "prerequisite")
                        - can_unlock = p_edges.every(pe => json.nodes.find(n => n.id == pe.from).status == "completed")
                        - IF (can_unlock) post_node.status = "available"
                     - END IF
                  - END FOR
                  - json.meta.last_updated = CURRENT_ISO_TIME
                  - CALL replace_file_content 更新图谱持久化 (status="completed", concept.mastered, 解锁后置节点, last_updated)
               - END IF
               - IF (用户要求重新学习该节点)
                  - CALL replace_file_content 将 plan_file 中所有 "- [x]" 重置为 "- [ ]"
                  - 提示用户: "📍 重新学习：【" + target_node.label + "】。视为全新教学请求，本次聚焦子主题 1"
                  - 调用 `lmi-execution-skill` 技能，传入 plan_file 并聚焦子主题 1 展开全新教学
               - ELSE
                  - 提示用户: "🎉 当前节点【" + target_node.label + "】已全部学完并掌握！请在 Duonav 桌面端中选中下一个解锁节点，或直接在对话中指定下一节点 ID（例如：3.4）继续学习。"
               - END IF
            - ELSE
               - 提示用户: "🎉 当前节点【" + target_node.label + "】所有子主题已学完！因前置依赖节点尚未在图谱中全部完成，暂不解锁后置节点；待前置节点全部学完后，本节点将自动认证通关。"
            - END IF
            - AND [退出决策流锚点]
         - END IF
```

---
[退出决策流锚点]——该锚点用于提前结束决策流

### [输出路径对齐摘要]：
- **前置依赖已全部掌握时**：
  ```
  📍 路径对齐：[学科名称] · [知识点名称] ，是该章节的第 N/M 个节点。
  前置节点状态：[已完成的前置节点列表]
  ```
- **前置依赖未覆盖/节点为 locked 时（跳级旁听模式）**：
  提示 `💡 检测到节点【[知识点名称]】的前置依赖尚未全部掌握。已开启【跳级旁听模式】：本次教学将默认具备相关基础直接展开推演；为保证图谱真实性，学完后暂不点亮完成状态与解锁后置节点。`

---

### 用户偏好设置
- [ ]——这是一个checkbox,用于维护是否支持调用`.agents\skills\linear-tikzdraw-skill\SKILL.md`技能，**如果为空，则禁止一切调用技能`.agents\skills\linear-tikzdraw-skill\SKILL.md`的方法。**

- 语言设置：使用用户输入的语言作为输出的语言（例如用户输出中文：输出简体中文，除非用户另有要求）




### agent偏好设置
>[!important] 输出规范
>- **数学公式用公式块**

***禁止***：
- 子代理禁止调用子代理
- 在调用`lmi-outline-skill`时，禁止任何调用`lmi-plan-skill`和`lmi-execution-skill`技能的方法
