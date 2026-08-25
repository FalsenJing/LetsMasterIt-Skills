---
name: lmi-outline-skill
description: "指导生成学习大纲 study_plan.md（含进度 checkbox、错题档案、疑难点记录）。当用户开始学习新科目或需要重新规划学习路径时使用（关键词：新科目/学习计划/大纲/规划；new subject, study plan, outline）。"
---

# 强制执行
>[!important]
>调用该技能时，**必须**调用平台的“拷问”功能，与用户对齐信息（例如：`\grill-me`）

---

# 学习大纲生成技能 (Study Outline Skill)

此技能指导 AI 为新科目生成结构化的学习大纲 `study_plan.md`，并等待用户审批。

---

## 🎯 核心职责

### 一、权威教材来源约束

1. **必须以权威国际教科书为依据**生成大纲，偏好学术教材（如 Sheldon Axler《Linear Algebra Done Right》、Gilbert Strang《Introduction to Linear Algebra》等），**而非**备考书籍。
2. **显式标注来源**：在 `study_plan.md` 文件开头必须标注主要参考教材的完整书名和作者。
3. **用户指定优先**：若用户指定了特定教材，以用户指定的为准。

### 二、大纲结构规范

1. **自顶向下组织**：从宏观模块逐步细分到具体知识点(树状结构)
2. **逻辑生长性**：显式标明高层级定理由哪些底层公理"推导生长"而来
3. **信息分级**：区分公理定义、定理推论与计算法则

### 三、文件结构

生成的 `study_plan.md` 必须包含以下区段：

```markdown
# 📚 《科目名称》学习计划

> 📖 主要参考教材：[书名] — [作者]

---

## 📅 阶段学习进度表

### [阶段1名称]
- [ ] [子阶段1名称/知识节点]
    - [ ] [知识节点 1]
    - [ ] [知识节点 2]
    - [ ] ....
- [ ] [ 子阶段2名称]
    - [ ] ...
- [ ] ....
### [阶段2名称]
- [ ] [子阶段1名称]
    - [ ] [知识节点 1]
    - [ ] [知识节点 2]
- [ ] [ 子阶段2名称]
    - [ ] ...
- [ ] ....
### [阶段....]
- [ ] ...

---

## ❌ 错题档案记录
| 错题ID | 关联章节 | 题目内容简述 | 错误原因分析 | 状态 |
| :--- | :--- | :--- | :--- | :--- |

---

## 💡 概念疑难点记录
| 序号 | 章节 | 疑难点 | 解答要点 | 状态 |
| :--- | :--- | :--- | :--- | :--- |
```

### 四、强制审批

生成 `study_plan.md` 后，智能体**必须停下**，询问用户是否需要调整。并明显地提示用户：“该[科目名称]大纲已经生成完毕，如果无需更改，建议开启新的聊天窗口，启用`lmi-plan-skill`技能进行具体学习计划制定”。

### 五、脚本支持（PowerShell 优先）

1. **优先运行 PowerShell 脚本**：`powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -InputFile <json_path>`
2. **均无可用环境时自动降级**：利用 `write_to_file` 工具参照 `templates/study_plan_template.md` 手动生成
3. 模板中的 `<!-- PHASE_TABLE -->` 是脚本的插入锚点，手动生成时替换为实际内容

---

## 📁 文件结构

```
.agents/skills/lmi-outline-skill/
├── SKILL.md               # 本文件
├── templates/
│   └── study_plan_template.md
└── scripts/
    └── build.ps1          # PowerShell 版本（推荐）
```
