**路径对齐 (Pre-Teaching Path Alignment)**：
收到用户的教学请求后、开始任何讲解或制定教学计划之前，**必须**先执行[决策流]：

### [决策流] ——每次会话都执行，且是顺序执行，这是if else逻辑语句
```pseudo
- IF 用户发出教学请求、开始任何讲解或制定教学计划
   - THEN 执行**定位当前活动学科图谱**：
      - IF (用户在当前对话中显式指定了学科名称或要求切换学科，例如：“切换到线性代数”、“学人工智能数学基础”)
         - specified_subject = 提取用户指定的学科名称
         - IF (存在有效图谱 "knowledge_graphs/" + specified_subject + "/knowledge_graph.json")
            - CALL run_command 执行 `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-outline-skill/scripts/set_active_subject.ps1 -Subject "<specified_subject>"` 更新活动指针
            - active_subject = specified_subject
         - ELSE
            - 提示用户：“⚠️ 未检测到学科【" + specified_subject + "】的知识图谱。”并询问是否要调用 `.agents\skills\lmi-outline-skill` 初始化该新学科的大纲与指针
            - IF 调用该技能
               - THEN 调用平台“拷问”工具(例如：/grill-me)与用户对齐信息，进行知识图谱大纲与活动指针的初始化
               - AND [退出决策流锚点]
            - ELSE [退出决策流锚点]
         - END IF
      - ELSE
         - 调用 `view_file` 读取 `knowledge_graphs/active_subject.json` 获取当前活动学科（`active_subject = json.active_subject`，对应图谱路径为 `knowledge_graphs/<active_subject>/knowledge_graph.json`；若不存在指针文件则回退检查根目录 `knowledge_graph.json`）
      - END IF
      - IF 不存在有效图谱文件 
         - THEN 询问用户是否要调用`.agents\skills\lmi-outline-skill`技能
            - IF 调用该技能
               - THEN 调用平台“拷问”工具(例如：/grill-me)与用户对齐信息，进行知识图谱大纲与活动指针的初始化**
               - AND [退出决策流锚点]  
            - ELSE [退出决策流锚点]  
       - ELSE IF 存在有效图谱文件
         - THEN 调用 `view_file` 读取该图谱，获取学习情况与各节点 status 状态（completed / available / locked）：
            - IF (用户在当前对话中显式指定了节点 ID)
               - target_id = 用户指定的节点 ID
               - IF (json.selected_node != target_id)
                  - CALL replace_file_content 更新图谱中 selected_node = target_id
               - END IF
            - ELSE
               - target_id = json.selected_node
            - END IF
            - IF (target_id 为空或未指定)
               - THEN 提示用户：“⚠️ 当前学科【<active_subject>】未检测到选中的学习节点。请先在 Duonav 桌面端点击目标节点并设为当前学习节点，或直接在对话中指定你想学习的节点 ID（例如：1.3）。”
               - AND [退出决策流锚点]
            - ELSE (target_node = json.nodes.find(n => n.id == target_id))
               - 确认位置、前置节点 status 状态，[输出路径对齐摘要]。
               - IF 当前目录下不存在`teaching_plans/` + active_subject 文件夹 或 不存在该节点的教学计划文件（如 `teaching_plans/` + active_subject + `/<target_id>*.md`）
                  - THEN 调用`lmi-plan-skill`技能
                  - AND 询问用户是否要开启`.agents\skills\linear-tikzdraw-skill\SKILL.md` 技能，并告知用户：“该技能为实验性技能，旨在`obsidian`中提供可视化内容，如无需要，建议保持默认禁止调用状态”。如果用户要求开启，则将[用户偏好设置]的checkbox标记为`[x]`。  
                  - AND [退出决策流锚点]  
               - ELSE IF 存在该节点的教学计划文件 (plan_file = 匹配到的 "teaching_plans/" + active_subject + "/<target_id>*.md")
                  - CALL view_file 读取 plan_file
                  - unchecked_subtopics = 提取 plan_file 中所有以 "- [ ]" 开头的子主题
                  - checked_subtopics = 提取 plan_file 中所有以 "- [x]" 开头的子主题
                  - IF (unchecked_subtopics 数量 > 0)
                     - current_subtopic = unchecked_subtopics[0]
                     - IF (checked_subtopics 数量 > 0)
                        - 提示用户: "📍 断点续学：【" + target_node.label + "】进度 (" + checked_subtopics.length + "/" + (checked_subtopics.length + unchecked_subtopics.length) + ")。本次继续推进子主题：【" + current_subtopic.title + "】"
                     - ELSE
                        - 提示用户: "📍 开始学习：【" + target_node.label + "】。本次聚焦子主题 1：【" + current_subtopic.title + "】"
                     - END IF
                     - 调用 `lmi-execution-skill` 技能，传入 plan_file 与 current_subtopic，用以定位当前教学子主题。
                     - AND [退出决策流锚点]
                  - ELSE IF (所有子主题均为 "- [x]")
                     - IF (target_node.status != "completed")
                        - CALL replace_file_content 更新图谱 (status="completed", mastered=true)
                     - END IF
                     - IF (用户要求重新学习该节点)
                        - CALL replace_file_content 将 plan_file 中所有 "- [x]" 重置为 "- [ ]"
                        - 提示用户: "📍 重新学习：【" + target_node.label + "】。视为全新教学请求，本次聚焦子主题 1"
                        - 调用 `lmi-execution-skill` 技能，传入 plan_file 并聚焦子主题 1 展开全新教学
                     - ELSE
                        - 提示用户: "🎉 当前节点【" + target_node.label + "】已全部学完并掌握！请在 Duonav 桌面端中选中下一个解锁节点，或直接在对话中指定下一节点 ID（例如：2.2）继续学习。"
                     - END IF
                     - AND [退出决策流锚点]
               - ELSE [退出决策流锚点]  
      - ELSE [退出决策流锚点] 
```

---
[退出决策流锚点]——该锚点用于提前结束决策流

### [输出路径对齐摘要]：
1. ```
   📍 路径对齐：[学科名称] · [知识点名称] ，是该章节的第 N/M 个节点。
   前置节点状态：[已完成/未覆盖的前置节点列表]
   ```
2. **前置依赖未覆盖时**：提示 `⚠️ 检测到前置节点 [X, Y] 尚未覆盖。建议先学习这些前置内容，或确认是否跳过。`

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

