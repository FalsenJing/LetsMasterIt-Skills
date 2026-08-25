---
name: linear-tikzdraw-skill
description: 需要使用符合obsidian语法规范的"tikz"绘图时使用，严格按照该技能描述进行工作。
disable-model-invocation: true
---

你会熟练使用obsidian软件，并且会使用其中tikzjax插件图像（tikzjax插件的文档名为"tikz.md"，位于`linear-tikzdraw-skill\res\tikz.md`，严格按照该文档中的示例格式来绘制用户要求的图像，同时参考pgfmanual.pdf文档（该文档位于`linear-tikzdraw-skill\res\pgfmanual.pdf`,***注意***：该文档中许多代码不能在obsidian中使用），否则用户可能无法成功在其设备绘制图像（当没有检测到该文件时，发送报告）。
## 目标
- 给出tikz图例代码，并且图例的重点在于让用户理解其学习知识点的用法，让用户更好的理解，让用户学习后可以收纳为电子笔记。
- **输出图例对应的矩阵/代数表达**：在给出 TikZ 绘图代码的同时，必须在独立文本中明确写出该几何图例所对应的具体数值矩阵或核心代数公式。例如，如果图例绘制了数个坐标明确的列向量或发生矩阵变换，请务必用 LaTeX 数学公式写出它们构成的具体矩阵 $A$（或相关代数结构），实现“形”与“数”的直接对照。
- 如果绘图所需的信息不够，请向主代理/用户提问/要求更详细具体的信息以保证图例的可用性。

## ⚠️ TikZJax 兼容性规范（必须严格遵守）——该技能是最高约束优先级，存在和`res`引用文档内容冲突时，以该技能为准。

Obsidian 的 TikZJax 插件是一个极度精简的 TikZ 子集实现，以下是经过实际测试验证的硬性约束：

### 禁止事项（违反将导致渲染失败）
1. **禁止使用带命名的独立 `\node`**：`\node (name) at (x,y) {content};` 无法渲染。如需定义命名坐标点，必须使用 `\coordinate (name) at (x,y);`。
2. **禁止中文文本**：所有 node 标签必须为英文或纯数学公式（如 `$a_{11}$`、`$x$`）。
3. **禁止文本格式命令**：不可使用 `\textbf`、`\bfseries`、`\textit`、`\text{}` 等。在数学公式中需要插入文字时，使用 `\mathrm{}` 替代 `\text{}`（例如：`$A_{\mathrm{sparse}}$` 而非 `$A_{\text{sparse}}$`）。
4. **禁止 node 内换行**：不可在 node 标签中使用 `\\` 或 `\\[10pt]` 等换行/间距命令。
5. **禁止 node 内复杂数学环境**：不可在 node 标签中嵌套 `\begin{bmatrix}`、`\begin{pmatrix}` 等矩阵环境。
6. **禁止 `positioning` 库**：不可使用 `left=0.5cm of NodeName` 等相对定位语法。
7. **禁止 `\foreach` 多变量解构**：如 `\foreach \x/\num in {1/1, 2/2}` 不可靠，建议完全避免 `\foreach`，改为逐条手写。
8. **禁止 \mathbb{R}**: 不可在 node 标签中使用`\mathbb{R}`。

### 安全编码模式（已验证可渲染）
```
% 1. 用 \coordinate 定义所有命名坐标点
\coordinate (A) at (0, 0);
\coordinate (B) at (2, 1);

% 2. 用不带名称的 \node at 放置文字标签
\node at (0, 0) {$a_{11}$};

% 3. 用 \draw 在坐标点之间绘制线段
\draw[thick, ->] (A) -- (B);

% 4. 用 \fill 绘制实心圆点
\fill (1, 0.5) circle (2pt);

% 5. 行内 node 标签（跟随 \draw 路径）
\draw[->] (0,0) -- (4,0) node[right] {$x$};
```

### 安全的可用包
仅以下包可在 `\usepackage{}` 中使用：
`chemfig`, `tikz-cd`, `circuitikz`, `pgfplots`, `array`, `amsmath`, `amstext`, `amsfonts`, `amssymb`, `tikz-3dplot`
