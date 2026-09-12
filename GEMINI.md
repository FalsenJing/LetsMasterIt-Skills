**路径对齐与教学调度 (Pre-Teaching Routing Gateway)**：
收到用户的教学请求后、开始任何讲解或制定教学计划之前，**必须**先执行以下调度流程：

### [决策流] —— 每次会话都执行，顺序执行
```pseudo
- IF (用户发出教学请求、开始任何讲解、制定教学计划或要求切换学科/节点)
   - subject_arg = (用户在当前对话中显式指定了学科名称, 如 “切换到线性代数”、“学人工智能数学基础”) ? ("-Subject \"" + 提取的学科名称 + "\"") : ""
   - node_arg = (用户在当前对话中显式指定了节点 ID, 如 “学 1.3” 或 “制定 2.1 计划”) ? ("-NodeId \"" + 提取的节点ID + "\"") : ""
   - replan_arg = (用户显式表达 “重新制定计划 / 重新规划 / 修改计划 / 调整大纲”) ? "-Replan" : ""
   - non_math_arg = (用户显式表达 “非数学 / 通用教学 / 免教案 / 直接讲”) ? "-NonMath" : ""

   - CALL run_command 执行 `powershell -ExecutionPolicy Bypass -File .agents/scripts/route_teaching.ps1 <subject_arg> <node_arg> <replan_arg> <non_math_arg>`
   - route = PARSE_JSON(stdout)

   - 提示用户: route.display_message

   - SWITCH (route.action):
      - CASE "ROUTE_TO_OUTLINE":
         - 提示用户: "未检测到学科【" + route.active_subject + "】的知识图谱大纲。是否调用 lmi-outline-skill 初始化该学科的大纲与指针？(回复【确认】开始构建，或在客户端/对话中切换学科)"
         - 等待用户输入
         - IF (用户确认调用)
            - 调用 `.agents/skills/lmi-outline-skill` 技能初始化知识图谱大纲与活动指针
         - ELSE
            - 提示用户: "已取消初始化。您可以在 Duonav 桌面端选择已有学科，或在对话中输入【切换到 <学科名>】继续。"
         - END IF
         - AND [退出决策流锚点]

      - CASE "PROMPT_SELECT_NODE":
         - STOP_CALLING_TOOLS (等待用户在 Duonav 桌面端点击选中节点，或在对话中指定节点 ID)
         - AND [退出决策流锚点]

      - CASE "ROUTE_TO_GENERAL_TEACHING":
         - 针对非数学/通用学科，无需制定二级大纲教案或开展严格三段式数学推演。
         - AI 直接以 route.target_node 为主题，结合其传授概念 (route.teaches_concepts) 与前置背景 (route.requires_concepts) 展开生动通俗的启发式教学讲解。
         - 讲解完成后与用户互动答疑；待用户确认掌握后：
            - CALL run_command 执行 `powershell -ExecutionPolicy Bypass -File .agents/skills/lmi-execution-skill/scripts/settle_lesson.ps1 -Subject route.active_subject -NodeId route.target_node.id -DirectComplete`
            - 提示用户结算与解锁结果
         - AND [退出决策流锚点]

      - CASE "ROUTE_TO_PLAN":
         - 调用 `lmi-plan-skill` 技能，传入 route.active_subject 与 route.target_node.id
         - AND [退出决策流锚点]

      - CASE "ROUTE_TO_EXECUTION":
         - 调用 `lmi-execution-skill` 技能，传入 route.active_subject, route.target_node.id 与 route.plan_file 启动课堂教学
         - AND [退出决策流锚点]
```

---
[退出决策流锚点]——该锚点用于提前结束决策流

---

### 用户偏好设置
- [ ]——这是一个checkbox,用于维护是否支持调用`.agents/skills/linear-tikzdraw-skill/SKILL.md`技能，**如果为空，则禁止一切调用技能`.agents/skills/linear-tikzdraw-skill/SKILL.md`的方法。**

- 语言设置：使用用户输入的语言作为输出的语言（例如用户输出中文：输出简体中文，除非用户另有要求）




### agent偏好设置

***禁止***：
- 子代理禁止调用子代理
- 在调用`lmi-outline-skill`时，禁止任何调用`lmi-plan-skill`和`lmi-execution-skill`技能的方法
