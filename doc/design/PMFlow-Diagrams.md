# PM 智能体工作流程图

## 流程总览图

```mermaid
graph TB
    Start([用户需求]) --> Analysis[需求分析阶段]
    Analysis --> Clarify[需求澄清阶段]
    Clarify --> PRD[PRD生成阶段]
    PRD --> Review[用户审批阶段]
    Review --> Approve{审批结果}
    Approve -->|通过| Task[任务创建阶段]
    Approve -->|不通过| Feedback[反馈修改]
    Feedback --> Analysis
    Task --> End([开发执行])
    
    style Start fill:#4A90E2,color:#fff
    style Analysis fill:#F5A623
    style Clarify fill:#F8E71C
    style PRD fill:#7ED321
    style Review fill:#BD10E0
    style Task fill:#50E3C2
    style End fill:#4A90E2,color:#fff
    style Approve fill:#D0021B,color:#fff
```

## 详细流程图：完整工作流程

```mermaid
graph TD
    A[用户提出需求] --> B[PM 分析需求]
    B --> C{需求是否清晰?}
    C -->|否| D[PM 向用户提问]
    D --> E[用户澄清需求]
    E --> B
    C -->|是| F[PM 生成 PRD]
    F --> G[保存至文档平台]
    G --> H[提交用户确认]
    H --> I{用户审批}
    I -->|通过| J[创建任务]
    J --> K[任务拆解为 Epic/Feature]
    K --> L[锁定本迭代范围]
    L --> M[通知开发团队]
    M --> N[流程结束]
    I -->|不通过| O[用户提出修改意见]
    O --> P[记录反馈到 PRD]
    P --> B
    
    style A fill:#e1f5ff
    style F fill:#fff4e1
    style I fill:#ffe1e1
    style J fill:#e1ffe1
    style O fill:#ffd4d4
    style P fill:#ffebcc
    style N fill:#f0f0f0
```

**说明**：
- 🔵 浅蓝色：流程起点（用户提出需求）
- 🟡 浅黄色：关键生成节点（PRD 生成）
- 🔴 浅红色：决策节点（用户审批）
- 🟢 浅绿色：审批通过路径（创建任务）
- 🟠 橙色：审批不通过路径（修改意见、记录反馈）
- ⚪ 灰色：流程结束

## 时序图：PM 与用户交互

```mermaid
sequenceDiagram
    participant U as 用户
    participant PM as PM智能体
    participant Doc as 文档平台
    participant Team as 开发团队
    
    U->>PM: 提出需求
    PM->>PM: 分析需求
    
    alt 需求不清晰
        PM->>U: 提出澄清问题
        U->>PM: 回答问题
        PM->>PM: 重新分析
    end
    
    PM->>PM: 生成 PRD
    PM->>Doc: 保存 PRD
    PM->>U: 提交审批
    
    alt 审批通过
        U->>PM: 确认通过
        PM->>PM: 创建任务
        PM->>PM: 拆解 Epic/Feature
        PM->>Team: 通知开始开发
    else 审批不通过
        U->>PM: 提出修改意见
        PM->>PM: 记录反馈
        PM->>PM: 重新分析需求
    end
```

## 状态图：PRD 文档状态流转

```mermaid
stateDiagram-v2
    [*] --> 草稿: 创建PRD
    草稿 --> 待审批: 提交审批
    待审批 --> 已通过: 用户批准
    待审批 --> 修改中: 用户拒绝
    修改中 --> 草稿: 更新内容
    已通过 --> 已归档: 任务完成
    已归档 --> [*]
    
    note right of 草稿
        PM正在编写
        可多次修改
    end note
    
    note right of 待审批
        等待用户确认
        可能需要澄清
    end note
    
    note right of 已通过
        锁定版本
        开始执行
    end note
```

## 泳道图：跨角色协作流程

```mermaid
graph TB
    subgraph 用户
        U1[提出需求]
        U2[澄清需求]
        U3[审批PRD]
        U4A[确认通过]
        U4B[提出修改]
    end
    
    subgraph PM智能体
        P1[接收需求]
        P2[分析需求]
        P3[提问澄清]
        P4[生成PRD]
        P5[创建任务]
        P6[记录反馈]
    end
    
    subgraph 文档平台
        D1[保存PRD]
        D2[版本控制]
    end
    
    subgraph 开发团队
        T1[接收任务]
        T2[开始开发]
    end
    
    U1 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> U2
    U2 --> P2
    P2 --> P4
    P4 --> D1
    D1 --> U3
    U3 --> U4A
    U3 --> U4B
    U4A --> P5
    U4B --> P6
    P6 --> P2
    P5 --> T1
    T1 --> T2
    D1 --> D2
    
    style U1 fill:#E3F2FD
    style U2 fill:#E3F2FD
    style U3 fill:#E3F2FD
    style U4A fill:#C8E6C9
    style U4B fill:#FFCDD2
```

## 决策树：需求清晰度判断

```mermaid
graph TD
    Start{开始判断需求清晰度} --> Q1{功能描述是否明确?}
    Q1 -->|否| Unclear[需求不清晰]
    Q1 -->|是| Q2{验收标准是否可量化?}
    Q2 -->|否| Unclear
    Q2 -->|是| Q3{边界条件是否清晰?}
    Q3 -->|否| Unclear
    Q3 -->|是| Q4{用户场景是否完整?}
    Q4 -->|否| Unclear
    Q4 -->|是| Clear[需求清晰]
    
    Unclear --> Action1[向用户提问]
    Clear --> Action2[生成PRD]
    
    style Start fill:#FFE082
    style Clear fill:#81C784
    style Unclear fill:#E57373
    style Action1 fill:#64B5F6
    style Action2 fill:#4DB6AC
```

## 流程性能指标图

```mermaid
graph LR
    subgraph 关键指标
        M1[需求澄清次数<br/>目标: ≤3次]
        M2[PRD生成时间<br/>目标: ≤2小时]
        M3[审批通过率<br/>目标: ≥80%]
        M4[任务拆解准确性<br/>目标: ≥90%]
    end
    
    subgraph 优化方向
        O1[提高需求理解能力]
        O2[优化PRD模板]
        O3[增强沟通效率]
        O4[改进拆解算法]
    end
    
    M1 -.-> O1
    M2 -.-> O2
    M3 -.-> O3
    M4 -.-> O4
    
    style M1 fill:#FFF9C4
    style M2 fill:#F0F4C3
    style M3 fill:#DCEDC8
    style M4 fill:#C5E1A5
```

## 使用说明

### 如何查看这些图表

1. **在 GitHub 上查看**：直接打开此 Markdown 文件，GitHub 会自动渲染 Mermaid 图
2. **在 VS Code 中查看**：安装 "Markdown Preview Mermaid Support" 插件
3. **在 Notion 中查看**：复制代码块到支持 Mermaid 的页面
4. **在线工具**：访问 [Mermaid Live Editor](https://mermaid.live/) 粘贴代码

### 图表说明

- **流程总览图**：整体流程的鸟瞰图
- **详细流程图**：两个分支流程的完整展示
- **时序图**：展示各角色之间的交互时间线
- **状态图**：PRD 文档的生命周期
- **泳道图**：跨团队协作的职责划分
- **决策树**：需求清晰度的判断逻辑
- **性能指标图**：关键指标与优化方向

---

**创建日期**：2026年3月7日  
**版本**：v1.0


