**路径对齐 (Pre-Teaching Path Alignment)**：
收到用户的教学请求后、开始任何讲解或制定教学计划之前，智能体**必须**先执行[决策流]：

### [决策流] ——每次会话都执行，且是顺序执行，这是if else逻辑语句
- IF 用户发出教学请求、开始任何讲解或制定教学计划
   - THEN 执行**读取 `study_plan.md`**：调用 `view_file` 获取章节拓扑结构与各节点 checkbox 状态
      - IF 不存在`study_plan.md`文件 
         - THEN 询问用户是否要调用`.agents\skills\lmi-outline-skill`技能
            - IF 调用该技能
               - THEN 调用平台“拷问”工具(例如：`/grill-me`)与用户对齐信息，进行`study_plan.md`教学大纲的初始化**
               - AND [退出决策流锚点]  
            - ELSE [退出决策流锚点]  
      - ELSE IF 存在`study_plan.md`
         - THEN **定位知识点拓扑位置**：确认所属阶段/子模块、序号位置、前置节点 checkbox 状态，[输出路径对齐摘要]。
            - IF 当前目录下不存在`teaching_plans`文件夹
               - THEN 调用`lmi-plan-skill`技能
               - AND 询问用户是否要开启`.agents\skills\linear-tikzdraw-skill\SKILL.md` 技能(**在调用技能`lmi-execution-skill`时无视该规则**)，并告知用户：“该技能为实验性技能，旨在`obsidian`中提供可视化内容，如无需要，建议保持默认禁止调用状态”。如果用户要求开启，则将[用户偏好设置]的checkbox标记为`[x]`。  
               - AND [退出决策流锚点]  
            - ELSE IF 存在`teaching_plans`文件夹  
               - IF 用户要求学习已标记为 `[x]` 的节点     
                  - THEN 忽略已完成状态，调用`lmi-execution-skill`技能，引用该节点的[x教学计划.md]，视为全新教学请求，从零开始完整讲解。
                  - AND [退出决策流锚点]  
               - ELSE 调用`lmi-execution-skill`技能，引用最新的[x教学计划.md]
            - ELSE [退出决策流锚点]  
      - ELSE [退出决策流锚点] 
                  

---
[退出决策流锚点]——该锚点用于提前结束决策流

### [输出路径对齐摘要]：
1. ```
   📍 路径对齐：[知识点名称] 位于 [阶段/子模块]，是该模块的第 N/M 个节点。
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
- 在调用`lmi-outline-skill`时，禁止任何调用`lmi-plan-skill`和`lmi-excution-skill`技能的方法

