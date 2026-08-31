# Developer guide

This guide describes the project's architecture, code flow, and execution
model. Use it to understand how the classes collaborate and how to interpret
the terminal output produced by the demos.

---

## Architecture overview

```text
Terminal demos                   Browser (React)
       |                               |
       |                         Nginx /api proxy
       |                               |
       +---------- IRIS ---------------+
                     |
             Native %AI.Agent
               |     |     |
               |     |     +-- Tools: ObjectScript / Python MCP
               |     +-------- Sub-agents: isolated sessions
               +-------------- Ollama: model inference
                     |
             SDK session and statistics
                     |
             UI runtime saves conversations in IRIS
```

IRIS orchestrates model and tool calls. Ollama does not directly execute the
ObjectScript or MCP tools. Terminal sessions are held by the caller; the UI
runtime additionally persists its conversations.

### Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **Agent** | Main controller that owns the provider, tools, and skills | `Test.Agent.cls` |
| **Session** | Conversation state, message history, stats | Created at runtime |
| **Tools** | Native IRIS functions or external MCP functions | `Test.Tools.*` |
| **ToolSets** | Collections of related tools | `Test.ToolSet.*` |
| **Skills** | Reusable instructions and personas for the model | `Test.Skill.*` |
| **Sub-Agents** | Isolated agents for delegation | `Test.SubAgents.*` |
| **MCP Server** | Python process for external tools | `mcp-python-server.py` |

---

## Execution flow

The following sequence occurs when you run
`Do ##class(Test.PatientAnalysisDemo).Run()`:

```
USER COMMAND
    |
    v
+------------------------------+
| Test.PatientAnalysisDemo.Run() |
+------------------------------+
    |
    v
+------------------------------+
| 1. Setup                      |
|    - Call Test.Setup.Run()    |
|    - Ensure data is loaded     |
+------------------------------+
    |
    v
+------------------------------+
| 2. Create Agent              |
|    - New Test.Agent()         |
|    - agent.%Init()            |
|    - Register tools           |
+------------------------------+
    |
    v
+------------------------------+
| 3. Create Session             |
|    - agent.CreateSession()    |
|    - Conversation state       |
+------------------------------+
    |
    v
+------------------------------+
| 4. Create Monitor             |
|    - Test.DemoMonitor()        |
|    - Tracks iterations        |
+------------------------------+
    |
    v
+------------------------------+
| 5. LOOP: Run 4 Prompts        |
|                              |
|  +------------------------+  |
|  | PROMPT 1: Analysis     |  |
|  |  agent.Run(session,    |  |
|  |   "Load skill...",10) |  |
|  |                         |  |
|  |  -> LLM reads prompt   |  |
|  |  -> Decides: need data |  |
|  |  -> Calls Summarize-   |  |
|  |     Patients           |  |
|  |  -> Calls Search-      |  |
|  |     Patients(limit=3)  |  |
|  |  -> Calls summarize_   |  |
|  |     measurements        |  |
|  |  -> Generates briefing |  |
|  +------------------------+  |
|                              |
|  +------------------------+  |
|  | PROMPT 2: Evidence     |  |
|  |  agent.Run(session,    |  |
|  |   "Call ReviewEv...",5)|  |
|  |                         |  |
|  |  -> LLM sees prompt    |  |
|  |  -> Recognizes:        |  |
|  |     ReviewEvidence     |  |
|  |  -> Calls tool         |  |
|  |  -> Tool creates:      |  |
|  |     EvidenceReviewer   |  |
|  |     sub-agent         |  |
|  |  -> Sub-agent runs     |  |
|  |  -> Returns review     |  |
|  +------------------------+  |
|                              |
|  +------------------------+  |
|  | PROMPT 3: Safety       |  |
|  |  (Same flow)           |  |
|  |  -> Creates Safety-     |  |
|  |     Reviewer sub-agent |  |
|  +------------------------+  |
|                              |
|  +------------------------+  |
|  | PROMPT 4: Explanation  |  |
|  |  (Same flow)           |  |
|  |  -> Calls Execute      |  |
|  |  -> Creates Data       |  |
|  |     Analyst sub-agent  |  |
|  +------------------------+  |
+------------------------------+
    |
    v
+------------------------------+
| 6. Print Statistics           |
|    - session.GetStats()        |
|    - agent.SubAgents.Count()  |
|    - Active skills            |
|    - Available tools          |
+------------------------------+
```

---

## Key concepts

### 1. The model controls tool selection

You provide a prompt, and the model:

- reads the request;
- decides which tools to call;
- generates tool calls and their arguments;
- receives the results after AI Hub executes those calls;
- continues until it can produce a final response.

The prompt does not invoke a tool directly. Instead, the model chooses whether
to invoke one based on the request, the active skill instructions, and the
tools available through the agent's `ToolManager`.

### 2. Tool-call lifecycle

```
1. MODEL: "I need data to answer this"
   |
2. MODEL: Generates tool_call
   |  - name: "SummarizePatients"
   |  - arguments: {"diagnosis": "Diabetes"}
   |
3. AI HUB: Finds tool by name
   |
4. AI HUB: Executes tool
   |  - If Native IRIS: runs ObjectScript method
   |  - If MCP: sends to Python process
   |  - If Delegation: creates sub-agent
   |
5. TOOL: Returns result
   |
6. AI HUB: Inserts result into conversation
   |
7. MODEL: Continues with result
   |
8. Repeat until model is satisfied or maxIterations
```

### 3. Session and agent responsibilities

| Aspect | %AI.Agent | %AI.Agent.Session |
|--------|-----------|-------------------|
| Lifetime | Persists across conversations | One conversation |
| Contains | Provider, Model, Tools, Skills | Messages, Active Skills, Stats |
| Created | Once, reused | Per conversation |
| State | Configuration | Conversation history |

```objectscript
// Create once, reuse
Set agent=##class(Test.Agent).%New()
Set agent.%Init()

// Create per conversation
Set session1=agent.CreateSession()
Set session2=agent.CreateSession()  // Separate conversation

// The same agent can own multiple isolated conversations
```

### 4. Skills and agent instructions

| Aspect | Skills | Agent Instructions |
|--------|--------|-------------------|
| Scope | Specific tasks | General behavior |
| Activation | On demand (`load_skill`) | Always active |
| Lifetime | Session | Agent |
| Location | Separate classes | Agent XData |

```
Agent Instructions (Test.Agent):
"You analyze synthetic healthcare dataset. Use IRIS tools first."

Skill (HealthcareAnalysis):
"Write sections in this order: 1. Scope 2. Findings 3. Examples..."
```

### 5. Activating skills

#### Method 1: model-driven activation

The model can load a skill when the prompt explicitly requests it:

```objectscript
// In your prompt, ask to load a skill
Set response=agent.Run(session,
    "Load the calculation-review skill. Then call get_mcp_info.",
    10)

// Model sees "calculation-review skill" in prompt
// Model calls AI Hub's load_skill capability
// Skill activates and appears in session.ActiveSkills
// Model follows skill instructions for subsequent turns
```

The activation sequence is:

1. The prompt names the skill.
2. The model recognizes that the skill is needed.
3. The model calls the `load_skill` capability.
4. AI Hub activates the skill.
5. AI Hub adds the skill instructions to the conversation context.
6. The model follows those instructions for the remainder of the session.

For example, `Test.PatientAnalysisDemo` uses this prompt-driven approach:
```
Prompt: "Load the synthetic-healthcare-analysis-brief skill. Analyze..."
→ Model activates skill
→ Model follows skill's 5-section structure
→ Output matches skill requirements
```

#### Method 2: registration and explicit UI activation

In this SDK preview, `agent.UseSkill("classname")` registers a skill and its
tools and exposes its metadata through `AvailableSkills`. It does **not** make
the skill active by itself. `Test.BasicDemo` registers Caveman, then asks the
model to use it; inspect `session.ActiveSkills` rather than inferring activation
from the response style.

The UI uses a different, deterministic path: `UpdateSkills` handles an explicit
Load/Unload command and calls `AgentTestUI.Runtime.ApplySkills` to replace the
session's available and active skill snapshots immediately, without inference.
The selected class IDs are validated against the agent's `SKILLS` parameter.
This avoids depending on the model to call `load_skill` or guess its name.
For example, the Poet class is `Test.Skill.Poet`, but its loadable name is
`talk-like-a-poet`, not `Talk Like A Poet`.

Active skills normally persist in session state. The UI explicitly replaces
that state on each skill command and send, so switching skills removes the old instructions and
an empty selection unloads all skills. Earlier conversation messages remain.
See [Browser UI development](#browser-ui-development) for the implementation
contract and tests.

---

## Code structure

```
src/Test/
├── Agents/                    # Agent classes
│   ├── Agent.cls             # Base agent for project
│   ├── MathAgent.cls         # Used by Test.BasicDemo
│   ├── SimpleAgent.cls       # General chat with optional skills
│   ├── IRISAgent.cls         # Instance inspection and demo writes
│   └── CavemanAgent.cls      # Alternative agent
│
├── Data/
│   └── Patient.cls           # Patient data persistence
│
├── Demo/                     # Terminal test classes
│   ├── Abstract.cls          # Base class for demos
│   ├── BasicDemo.cls         # TEST 1
│   └── PatientAnalysisDemo.cls # TEST 2
│
├── Monitor/
│   └── DemoMonitor.cls      # Iteration tracking
│
├── Setup/
│   └── Setup.cls             # Data loading
│
├── Skill/                    # Skill classes
│   ├── HealthcareAnalysis.cls    # For patient analysis
│   ├── CalculationReview.cls    # For math
│   ├── Poet.cls              # Poetic style
│   ├── Echo.cls              # Echo, word count, sentiment
│   └── Caveman.cls           # Concise responses
│
├── SubAgents/                # Delegation tool classes
│   ├── CalculationReviewer.cls  # Math verification
│   ├── EvidenceReviewer.cls    # Healthcare evidence
│   └── SafetyReviewer.cls      # Healthcare safety
│
├── Tools/                    # Tool classes
│   ├── Patients.cls          # Native IRIS tools
│   ├── IRISManagement.cls    # Instance inspection and dedicated demo global
│   └── DelegateTasks.cls     # Generic delegation
│
└── ToolSet/                  # Tool collections
    ├── Local.cls             # Native tools (Patients)
    ├── IRISManagement.cls    # Native instance tools
    └── StatisticsMCP.cls     # External MCP (Python)
```

---

## Agent hierarchy

```
%AI.Agent (AI Hub base)
    ├── Test.Agent (healthcare agent and project base)
    │       ├── Test.MathAgent (BasicDemo)
    │       └── Test.CavemanAgent (alternative)
    ├── Test.Agents.SimpleAgent (general conversation)
    └── Test.Agents.IRISAgent (instance tools)
```

### `Test.Agent.%OnInit()`: agent initialization

```objectscript
Method %OnInit() As %Status
{
    // 1. Call parent
    Set sc=##super()
    
    // 2. Setup provider if not set
    Set base=$SYSTEM.Util.GetEnviron("OLLAMA_BASE_URL")
    Set ..Provider=##class(%AI.Provider).Create("openai",{
        "api_key":"ollama",
        "base_url":base
    })
    Set ..Model=$SYSTEM.Util.GetEnviron("OLLAMA_MODEL")
    
    // 3. Register delegation tools
    Set sc=..RegisterSubAgentTools()
    
    Quit $$$OK
}
```

### `RegisterSubAgentTools()`: delegation setup

```objectscript
Method RegisterSubAgentTools() As %Status
{
    // 1. Generic delegation tool
    Do ..RegisterGenericDelegateTool()
    
    // 2. Evidence reviewer tool
    Set evidenceReviewer=##class(Test.SubAgents.EvidenceReviewer).%New($THIS)
    Do ..ToolManager.AddTool(evidenceReviewer)
    
    // 3. Safety reviewer tool
    Set safetyReviewer=##class(Test.SubAgents.SafetyReviewer).%New($THIS)
    Do ..ToolManager.AddTool(safetyReviewer)
    
    Quit $$$OK
}
```

`..ToolManager.AddTool()` registers each tool after its `ParentAgent` reference
has been initialized with `$THIS`.

---

## Tool implementations

### 1. Native IRIS tool: `Test.Tools.Patients`

```objectscript
Class Test.Tools.Patients Extends %AI.Tool
{
Method SearchPatients(
    diagnosis As %String="",
    limit As %Integer=20
) As %DynamicObject [ WebMethod ]
{
    // Clamp limit
    If limit<1 Set limit=1
    If limit>50 Set limit=50
    
    // Execute SQL
    Set sql="SELECT TOP ? FROM Test_Data.Patient WHERE Diagnosis=?"
    Set stmt=##class(%SQL.Statement).%New()
    Set sc=stmt.%Prepare(sql)
    Set sc=stmt.%Execute(limit, diagnosis)
    
    // Return as JSON
    Quit stmt.%ToJSON()
}
}
```

Key characteristics:

- The class extends `%AI.Tool`.
- The `[ WebMethod ]` keyword makes the method discoverable and callable by the model.
- The method returns a `%DynamicObject` or other JSON-serializable data.
- The implementation bounds result counts and uses parameterized SQL.

### 2. Dedicated delegation tool: `Test.SubAgents.EvidenceReviewer`

```objectscript
Class Test.SubAgents.EvidenceReviewer Extends %AI.Tool
{
Property ParentAgent As %AI.Agent;

Method %OnNew(parentAgent As %AI.Agent) As %Status
{
    Set ..ParentAgent=parentAgent
    Quit $$$OK
}

Method ReviewEvidence(draft As %String) As %String [ WebMethod ]
{
    // Define sub-agent's role
    Set prompt="You are an evidence reviewer. Check only the supplied "_
               "synthetic healthcare draft. Identify unsupported numbers. "_
               "Return PASS or correction list. Never provide clinical advice."
    
    // Create isolated sub-agent
    Set subagent=##class(%AI.Agent.SubAgent).Create(
        ..ParentAgent,   // Parent reference
        prompt,           // System prompt
        ""               // Config
    )
    
    // Create session for sub-agent
    Set session=subagent.CreateSession()
    
    // Run the sub-agent
    Set response=subagent.Run(session, draft)
    
    // Return result to parent
    Quit response.Content
}
}
```

Key characteristics:

- The class extends `%AI.Tool` and exposes a `[ WebMethod ]`.
- `%OnNew()` receives the `ParentAgent` reference required to create the child.
- `##class(%AI.Agent.SubAgent).Create()` creates the sub-agent.
- The sub-agent receives its own isolated session and context.
- The tool returns the sub-agent's response to the parent conversation.

### 3. Generic delegation tool: `Test.Tools.DelegateTasks`

```objectscript
Class Test.Tools.DelegateTasks Extends %AI.Tool
{
Property ParentAgent As %AI.Agent;

Method Execute(
    task As %String,
    specialistRole As %String="",
    context As %String=""
) As %String [ WebMethod ]
{
    // Build dynamic system prompt
    Set systemPrompt="You are a helpful assistant"
    If specialistRole'="" {
        Set systemPrompt="You are a "_specialistRole_" assistant"
    }
    If context'="" {
        Set systemPrompt=systemPrompt_". Context: "_context
    }
    
    // Log delegation
    Write "[Delegation] Creating sub-agent with role '"_specialistRole_"'...",!
    
    // Create sub-agent
    Set subagent=##class(%AI.Agent.SubAgent).Create(
        ..ParentAgent,
        systemPrompt,
        ""
    )
    
    // Execute
    Set session=subagent.CreateSession()
    Set response=subagent.Run(session, task)
    
    // Log completion
    Write "[Delegation] Sub-agent completed",!
    Write "[Delegation] Response length: ",$LENGTH(response.Content)," characters",!
    
    Quit response.Content
}
}
```

Key characteristics:

- `specialistRole` and `context` are supplied at runtime.
- The tool constructs the child agent's system prompt dynamically.
- Child creation follows the same pattern used by the dedicated reviewers.
- Progress messages make the delegation lifecycle visible in the terminal.

---

## Skill implementations

The project contains five skills. Availability depends on the selected agent's
`SKILLS` declaration; registration and activation are separate operations:

| Skill | Class | Purpose |
| --- | --- | --- |
| `calculation-review` | `Test.Skill.CalculationReview` | Arithmetic evidence and inverse checks |
| `synthetic-healthcare-analysis-brief` | `Test.Skill.HealthcareAnalysis` | Evidence-bound synthetic-data briefings |
| `talk-like-a-poet` | `Test.Skill.Poet` | Poetic response style |
| `echo` | `Test.Skill.Echo` | Echo instructions, word-count and sentiment tools |
| `caveman` | `Test.Skill.Caveman` | ULTRA compression with technical and safety detail preserved |

### Caveman skill example

The full definition is in [Caveman.cls](src/Test/Skill/Caveman.cls). Its
instructions make ULTRA the default whenever active: dense fragments, no
filler, and a 3–12-word target for simple answers. Necessary detail, code,
negation, units, uncertainty, and safety warnings must remain intact. Explicitly
requested formats take precedence; there is no hard word-limit enforcement.

One style example from the instructions is:

```text
User: Sum, average, largest, smallest of 12, 7, 25, 4, 18, 9?
Answer: Sum: 75. Mean: 12.5. Max: 25. Min: 4.
```

Verify activation from session state, not whether a model obeys the compression
target. The skill does not grant extra permissions or remove tool requirements.

### Skill structure

```objectscript
Class Test.Skill.HealthcareAnalysis Extends %AI.Agent.Skill
{
XData SUMMARY [ MimeType="text/yaml" ]
{
name: synthetic-healthcare-analysis-brief
description: Build evidence-bound briefing from synthetic healthcare records.
parameters:
  - name: request
    description: Cohort filters and analysis requested
    type: string
    required: true
tags:
  - healthcare
  - synthetic-data
  - analysis
}

XData INSTRUCTIONS [ MimeType="text/markdown" ]
{
Use `SearchPatients` to retrieve bounded records and `SummarizePatients` for 
full-cohort aggregates. Use StatisticsMCP only on values already returned by 
an IRIS tool. Never invent, interpolate, or silently extend data.

Write sections in this order:
1. Scope: filters, source, row count, and truncation.
2. Findings: exact aggregate values with units.
3. Example records: patient codes only, never names.
4. Limitations: synthetic random data, no causal or population inference.
5. Next analysis: one safe reproducible follow-up query.

Clearly distinguish IRIS aggregate results from calculations produced by 
StatisticsMCP. Never diagnose, score individual risk, recommend treatment, or 
present this dataset as clinical evidence.
}
}
```

Key characteristics:

- The class extends `%AI.Agent.Skill`.
- The `SUMMARY` YAML block provides discovery metadata.
- The `INSTRUCTIONS` Markdown block contains the prompt instructions.
- The model can activate the skill through the `load_skill` capability.

---

## Demo implementation

### `Test.BasicDemo.Run()`

```objectscript
ClassMethod Run(model As %String="") As %Status
{
    // Setup
    Set agent=##class(Test.MathAgent).%New()
    Set agent.%Init()
    If model'="" Set agent.Model=model
    
    Set session=agent.CreateSession()
    Set monitor=##class(Test.DemoMonitor).%New()
    Set maxIterations=5
    
    // Show available tools
    Write "Agent: ",$CLASSNAME(agent),!,"Model: ",agent.Model,!
    Write "Available Tools: ",agent.ToolManager.%Discover().%ToJSON(),!,!
    
    // PROMPT 1: Load skill + get MCP info
    Set prompt="First load the calculation-review skill. Then call get_mcp_info..."
    Do ..ShowPrompt(prompt)
    Set sc=..RunAgent(agent, session, prompt, maxIterations, monitor, .response)
    Write "skills: ",agent.Skills,!
    
    // PROMPT 2: Call add_numbers
    Set prompt="Now call add_numbers with first=17 and second=25..."
    Do ..ShowPrompt(prompt)
    Set sc=..RunAgent(agent, session, prompt, maxIterations, monitor, .response)
    Write "skills: ",agent.Skills,!
    
    // PROMPT 3: Delegate to CalculationReviewer
    Set prompt="Call ReviewCalculation to delegate verification..."
    Do ..ShowPrompt(prompt)
    Set sc=..RunAgent(agent, session, prompt, maxIterations, monitor, .response)
    Write "skills: ",agent.Skills,!
    
    // PROMPT 4: Delegate to mental-math teacher
    Set prompt="Call Execute to delegate to mental-math teacher..."
    Do ..ShowPrompt(prompt)
    Set sc=..RunAgent(agent, session, prompt, maxIterations, monitor, .response)
    
    // PROMPT 5: Use caveman skill programmatically
    Set sc=agent.UseSkill("Test.Skill.Caveman")
    Set prompt="Using caveman skill, compact the concepts explained from the math teacher"
    Do ..ShowPrompt(prompt)
    Set sc=..RunAgent(agent, session, prompt, maxIterations, monitor, .response)
    
    // Statistics
    Write "Parent stats: ",session.GetStats().%ToJSON(),!
    Write "Spawned sub-agents: ",agent.SubAgents.Count(),!
    For i=1:1:agent.SubAgents.Count() {
        Write !,agent.SubAgents.GetAt(i).SystemPrompt,!
    }
    Write "Active skills: ",session.ActiveSkills.%ToJSON(),!
    Write "Available Tools: ",agent.ToolManager.%Discover().%ToJSON(),!
    
    Quit $$$OK
}
```

### `Test.PatientAnalysisDemo.Run()`

```objectscript
ClassMethod Run(model As %String="") As %Status
{
    // Setup
    Set sc=##class(Test.Setup).Run()  // Ensure data loaded
    Set agent=##class(Test.Agent).%New()
    Set agent.%Init()
    If model'="" Set agent.Model=model
    
    Set session=agent.CreateSession()
    Set monitor=##class(Test.DemoMonitor).%New()
    Set maxIterations=5
    
    // PROMPT 1: Primary analysis
    Set prompt="Load the synthetic-healthcare-analysis-brief skill. "_
            "Analyze synthetic patients whose diagnosis is Diabetes. "_
            "Use SummarizePatients for cohort metrics, SearchPatients for "_
            "exactly three example records, and summarize_measurements for "_
            "their treatment costs. Produce the required evidence-bound briefing."
    Do ..ShowPrompt(prompt)
    Set draft=agent.Run(session, prompt, 10, monitor)
    Do ..Render("Parent analysis", draft.Content)
    
    // PROMPT 2: Evidence review
    Set evidencePrompt="Call ReviewEvidence to delegate an evidence review..."
    Do ..ShowPrompt(evidencePrompt)
    Set sc=..RunAgent(agent, session, evidencePrompt, maxIterations, monitor, .response)
    
    // PROMPT 3: Safety review
    Set safetyPrompt="Call ReviewSafety to delegate a safety review..."
    Do ..ShowPrompt(safetyPrompt)
    Set sc=..RunAgent(agent, session, safetyPrompt, maxIterations, monitor, .response)
    
    // PROMPT 4: Explanation
    Set explainPrompt="Call Execute to delegate this task to a sub agent..."
    Do ..ShowPrompt(explainPrompt)
    Set sc=..RunAgent(agent, session, explainPrompt, maxIterations, monitor, .response)
    
    // Statistics
    Write "Parent stats: ",session.GetStats().%ToJSON(),!
    Write "Spawned sub-agents: ",agent.SubAgents.Count(),!
    For i=1:1:agent.SubAgents.Count() {
        Write !,agent.SubAgents.GetAt(i).SystemPrompt,!
    }
    Write "Active skills: ",session.ActiveSkills.%ToJSON(),!
    Write "Available Tools: ",agent.ToolManager.%Discover().%ToJSON(),!
    
    Quit $$$OK
}
```

---

## Browser UI development

### IRISAgent example

The new screenshots use [IRISAgent](src/Test/Agents/IRISAgent.cls), a direct
`%AI.Agent` subclass declaring `Test.ToolSet.IRISManagement` and the Caveman
and Echo skills. Its provider uses the same Ollama environment variables as
the other examples. The tool implementations are in
[IRISManagement.cls](src/Test/Tools/IRISManagement.cls):

| Method | Behavior |
| --- | --- |
| `LargestGlobals` | Returns up to 20 globals with estimated sizes in MB and the namespace. |
| `ReadGlobalContent` | Samples up to 20 root/top-level values, each truncated to 500 characters. |
| `CreateDemoGlobal` | Creates or updates one node in `^TestIRISAgent`; key/value limits are 100/500 characters. |
| `WebApplicationExists` | Checks registration of an application path through `Security.Applications`. |

The pictured prompt exercises `LargestGlobals`. Names and sizes vary with
instance state; compare the returned evidence, not a hard-coded screenshot.
Global reads can expose instance data. These tools and the unauthenticated
UI are for a trusted demo environment, not production administration.

### Components and routing

The optional `ui` Compose profile builds React with Vite and serves the static
bundle through Nginx on `http://localhost:5174`. Nginx proxies `/api/` to
`http://iris:52773/agent-ui/api/`. `App.Installer.cls` registers that REST
application in `FIRST_AGENT`.

| File or class | Responsibility |
|---|---|
| `frontend/src/main.jsx` | Collapsible panels, history, immediate skill commands, auto-growing composer, API errors |
| `frontend/src/markdown.js` | Math normalization and Markdown/GFM/KaTeX plugins |
| `frontend/src/markdown.test.js` | Math delimiter and protected-content regression tests |
| `frontend/src/style.css` | Sidebar, scrollable details, messages, responsive layout |
| `frontend/nginx.conf` | Same-origin API proxy; 300-second read/send timeouts |
| `AgentTestUI.REST.Router` | JSON endpoints and Ollama model discovery |
| `AgentTestUI.Runtime` | Agent discovery, session restoration, skill application, inference |
| `AgentTestUI.Data.Conversation` | IRIS persistence for session export, messages, selected skills, metadata |
| `AgentTestUI.Test` | Discovery and SDK skill-state regression checks |

Markdown uses `react-markdown`, `remark-gfm`, `remark-math`, and `rehype-katex`.
`normalizeMath` converts supported LaTeX delimiters outside protected code,
links, HTML, and existing math. A custom table wrapper allows horizontal
scrolling. The composer sends on Enter and inserts a newline on Shift+Enter.
Its height is recalculated after text and width changes, up to
`clamp(80px, 30dvh, 240px)`, then it scrolls vertically. Replies arrive as a
complete JSON response.
The provider display currently represents Ollama; it is not a multi-provider
selector. Model discovery queries `/api/tags` on the configured Ollama host,
falling back to `OLLAMA_MODEL` if discovery is unavailable.

### REST contract

Paths below are relative to the frontend's `/api` prefix.

| Method | Path | Purpose |
|---|---|---|
| GET | `/agents` | Runnable agents and their model, toolset, skill, and prompt metadata |
| GET | `/providers` | Ollama provider and discovered model names |
| GET | `/conversations` | Recent conversations, newest first |
| POST | `/conversations` | Create a conversation; returns `conversationId` with HTTP 201 |
| GET | `/conversations/:id` | Restore messages, agent, model, and saved `activeSkills` |
| POST | `/conversations/:id/messages` | Send a message; returns `content`, `role`, `recovered`, `stats`, and actual `activeSkills` |
| POST | `/conversations/:id/skills` | Apply the complete skill selection immediately; return updated conversation and Studio confirmation |
| DELETE | `/conversations/:id` | Delete a conversation; clients accept a successful 2xx response |

Create a chat, then substitute the returned ID in subsequent requests:

```bash
curl -sS http://localhost:5174/api/conversations \
  -H 'Content-Type: application/json' \
  -d '{"className":"Test.Agents.SimpleAgent","model":"granite4:3b","activeSkills":[]}'

curl -sS http://localhost:5174/api/conversations/CONVERSATION_ID/messages \
  -H 'Content-Type: application/json' \
  -d '{"message":"Describe moonlight briefly.","activeSkills":["Test.Skill.Poet"]}'

curl -sS http://localhost:5174/api/conversations/CONVERSATION_ID/messages \
  -H 'Content-Type: application/json' \
  -d '{"message":"What is 2 plus 2? Answer plainly.","activeSkills":[]}'
```

To activate a skill without a model request:

```bash
curl -sS http://localhost:5174/api/conversations/CONVERSATION_ID/skills \
  -H 'Content-Type: application/json' \
  -d '{"activeSkills":["Test.Skill.Caveman"]}'
```

Send `{"activeSkills":[]}` to that endpoint to unload all skills. The response
is the updated conversation, including visible messages and active IDs.

`activeSkills` is the complete desired selection, not a list of changes. Its
entries are class names allowed by the selected agent. An empty array means
all off; an omitted field currently defaults to an empty array in the router.
It must never be interpreted as “reuse the old selection.”

### Skill and conversation state

On each send, the runtime restores the saved SDK session, validates and
registers the selection with `ConfigureSkills`, then calls `ApplySkills` before
`agent.Run(session,message,10,monitor)`. `ApplySkills` exports session state,
replaces `available_skills` and `active_skills`, and imports it again. Each
active snapshot includes the skill ID, name, version, source, content hash,
instruction snapshot, and activation timestamp. This uses the current preview
SDK export format: rerun the regression checks after SDK upgrades.

After a completed turn (including empty-answer recovery), the runtime saves the session, visible
messages, and `ActiveSkillIds(session)`. The frontend adopts those returned IDs,
so it does not merely echo a possibly incorrect selection as active. New chats
start empty; reopening an existing chat restores its saved state. Load/Unload
commands persist immediately through `UpdateSkills`, with a visible `notice`
rendered as **Studio**. These confirmations are not model-generated and are
not inserted into the model transcript. The frontend adopts confirmed server
state, shows **Saving…** during the command, and disables mutations while busy.
Loading before a first prompt creates the conversation; agent and model are
then locked until **New chat**.

Unloading removes active instructions, not earlier conversation content. It is
not a tool-permission boundary: agent initialization can still register tools.
Multiple selected skills may conflict, and activation does not guarantee that
the model follows every instruction.

`SkillsData` is an additive field with an empty-array default for older chats.
History lives in IRIS; only sidebar collapse preference uses browser storage.
There is no explicitly configured persistent IRIS data volume in Compose.
Back up data before removing or replacing the IRIS container. The REST app is
unauthenticated and history is shared; add authentication and authorization
before any deployment beyond a trusted local demo.

### Error handling

- The router returns JSON errors under `message`. `responseJSON` parses the
  body before throwing, preserving the server's explanation instead of catching
  its own error and replacing it with a generic HTTP failure.
- Keep `IgnoreWrites` and the explicit `IgnoreRESTOutput` handling in the
  router: monitor output must not contaminate JSON responses.
- If `agent.Run()` returns empty content, `RecoverReply` makes one text-only
  completion over the exported transcript and active instructions. No tools
  are offered and the task is not replayed. A recovered answer is saved with
  `role: "assistant"` and `recovered: 1`. If recovery is also empty, the turn
  and tool results are saved with `role: "notice"` and `recovered: 0`. The
  Studio notice warns that tools may have run; inspect outcomes before retrying.
  This branch does not handle arbitrary exceptions from the initial run.
- Older saved null assistant replies can cause HTTP 400 with
  `invalid message content type: <nil>`. `ApplySkills` removes empty assistant
  messages without tool calls from model context, while preserving legitimate
  tool-call messages and visible chat history.

### Screenshot references

The current screenshots live in [pic/](pic/) and appear together in the
[README showcase](README.md#ui-showcase). Use them when checking the UI:

| Screenshot | Visible state |
| --- | --- |
| [Homepage](pic/1_homepage.png) | IRISAgent, collapsed Recent chats, expanded configuration and capabilities |
| [Chat example](pic/2_chat_example.png) | Estimated global-size table, locked configuration, collapsed agent details |
| [Poet example](pic/3_example_talk_like_a_poet.png) | Activation notice, Poet active, arithmetic explanation |
| [Skill loading](pic/4_skill_loading.png) | Caveman active, Unload action, Studio confirmation |
| [Model choice](pic/5_model_choice.png) | Installed-model dropdown; names depend on the Ollama host |

The model-choice capture includes an older connection-status label. Current
code displays **Local inference · Ollama**; neither a provider label nor a
model list is a continuous health check. Screenshots illustrate output, not
fixed expected global sizes or guaranteed model behavior.

### Build and verification

Run these commands from `projects/my-first-agent`. For a first installation:

```bash
docker compose --profile ui up -d --build --wait
```

For frontend-only changes, rebuild only that service to avoid replacing IRIS:

```bash
docker compose --profile ui build frontend
docker compose --profile ui up -d --no-deps frontend
```

`cd frontend && npm run build` checks the production bundle locally after
installing its dependencies. `npm run dev` starts Vite, but the current Vite
configuration has no `/api` proxy; use the Docker UI for end-to-end tests unless
you configure a development proxy explicitly.

Run the Markdown regression tests independently of IRIS:

```bash
node --test frontend/src/markdown.test.js
```

Also check multiline typing/paste, shrinking after send, vertical scrolling at
the height limit, and resizing the viewport. Verify Configuration, Recent chats,
and Selected agent expand/collapse without losing the conversation.

After importing changed ObjectScript classes into `FIRST_AGENT`, run:

```bash
docker compose exec iris iris session IRIS -U FIRST_AGENT
```

```objectscript
Set sc=##class(AgentTestUI.Test).Run()
Write $SYSTEM.Status.GetErrorText(sc),!
```

These checks exercise discovery, all-off defaults, activation, replacement,
unloading, export/import restoration, invalid skill rejection, and recovery
from legacy null replies, plus immediate command persistence and confirmation.
They make no LLM calls; the command test creates and deletes its own conversation.

For an end-to-end check, create a new UI chat with `Test.Agents.SimpleAgent`:
load Poet and check the Studio confirmation before sending a prompt. Unload
Poet, load Echo, then unload all skills. Confirm each command updates the
active count and composer summary immediately, and reopening the chat restores
its state. Repeat with
the API examples above. Inspect actual session state rather than relying only
on poetic or terse wording; model output varies.

---

## Troubleshooting

### Tools are not called

Check that:

1. the selected model supports structured tool calls;
2. the prompt explicitly requests tool usage;
3. the expected tools appear in `agent.ToolManager.%Discover()`;
4. the required skills appear in `session.ActiveSkills`.

Use this direct prompt as a diagnostic:
```objectscript
// Direct tool call test
Set response=agent.Run(session,"Call get_mcp_info and return the marker.",5)
```

If it succeeds, the model and provider support tool calling.

### MCP tools are missing

Check that:

1. the Python process is running;
2. `Test.ToolSet.StatisticsMCP` contains the correct MCP server path;
3. standard output contains only MCP protocol messages, with diagnostic logs sent to standard error.

Verify tool discovery with:
```objectscript
Write agent.ToolManager.%Discover().%ToJSON()
```

The result should include `add_numbers`, `get_mcp_info`, `count_categories`,
and `summarize_measurements`.

### Sub-agents do not appear to work

Check for these signs in the output:

1. a `[ToolName] called as tool` message;
2. delegation logs such as `[Delegation] Creating sub-agent...`;
3. the sub-agent's result in the parent response.

Together, these messages prove that delegation occurred, even when
`agent.SubAgents.Count()` is lower than expected.

### Provider connection fails

Check that:

1. Ollama is running by executing `ollama list`;
2. `.env` defines the correct `OLLAMA_MODEL`;
3. the container uses `host.docker.internal`, not `localhost`;
4. the selected model supports tools and system messages.

Inspect the configured provider directly:
```objectscript
Set agent=##class(Test.Agent).%New()
Set agent.%Init()
Write "Provider: ",agent.Provider.%ToJSON(),!
Write "Model: ",agent.Model,!
```

---

## Quick reference

### Key classes

| Purpose | Class | File |
|---------|-------|------|
| Base Agent | Test.Agent | src/Test/Agents/Agent.cls |
| Math Agent | Test.MathAgent | src/Test/Agents/MathAgent.cls |
| Basic Demo | Test.BasicDemo | src/Test/Demo/BasicDemo.cls |
| Patient Demo | Test.PatientAnalysisDemo | src/Test/Demo/PatientAnalysisDemo.cls |
| Healthcare Skill | Test.Skill.HealthcareAnalysis | src/Test/Skill/HealthcareAnalysis.cls |
| Caveman Skill | Test.Skill.Caveman | src/Test/Skill/Caveman.cls |
| Calculation Skill | Test.Skill.CalculationReview | src/Test/Skill/CalculationReview.cls |
| IRIS Tools | Test.Tools.Patients | src/Test/Tools/Patients.cls |
| Delegation Tool | Test.Tools.DelegateTasks | src/Test/Tools/DelegateTasks.cls |
| Evidence Reviewer | Test.SubAgents.EvidenceReviewer | src/Test/SubAgents/EvidenceReviewer.cls |
| Safety Reviewer | Test.SubAgents.SafetyReviewer | src/Test/SubAgents/SafetyReviewer.cls |
| Calculation Reviewer | Test.SubAgents.CalculationReviewer | src/Test/SubAgents/CalculationReviewer.cls |

### Key parameters

**Test.Agent.cls:**
```objectscript
Parameter OLLAMABASEURL="http://host.docker.internal:11434/v1/"
Parameter DESCRIPTION="Synthetic healthcare dataset analysis agent."
Parameter TOOLSETS="Test.ToolSet.Local,Test.ToolSet.StatisticsMCP"
Parameter SKILLS="Test.Skill.HealthcareAnalysis,Test.Skill.Poet,Test.Skill.Echo"
```

**Test.MathAgent.cls:**
```objectscript
Parameter TOOLSETS="Test.ToolSet.StatisticsMCP"
Parameter SKILLS="Test.Skill.CalculationReview"
```

### Key methods

**agent.Run(session, prompt, maxIterations, monitor)**

- Executes one conversation turn.
- Returns a response containing `Content` and `Usage`.
- Accumulates statistics in the session.

**session.GetStats()**

- Returns cumulative statistics.
- Includes `total_tool_calls`, `total_tool_duration_ms`, `total_interactions`, and token counts.

**agent.ToolManager.%Discover()**

- Returns an array containing every registered tool.
- Each entry includes a name, description, and parameter schema.

**session.ActiveSkills**

- Returns an array containing the activated skills.
- Each entry includes `id`, `name`, and `instructions_snapshot`.

---

## Understanding the output

### Basic demo output map

```
OUTPUT LINE                          WHAT IT MEANS
─────────────────────────────────────────────────────────────

Agent: Test.MathAgent                Agent class created
Model: granite4:3b                  Model from .env or override

Available Tools: [...]              All tools registered in ToolManager

[agent iteration 1/5]               Iteration 1 of max 5
Token usage: {...}                  Tokens used in this iteration
Total tool calls: 2                 Cumulative session tool calls

[CalculationReviewer] called as tool  CalculationReviewer tool was invoked
[Delegation] Creating sub-agent...   Execute tool creating sub-agent
[Delegation] Sub-agent completed     Sub-agent finished task

=================================              New prompt phase
Prompt>: Using caveman skill...      Skill registered; prompt requests use
[agent iteration 1/5]               Iteration for caveman phase

--- Response: ---                   Caveman skill output (terse)
Zero multiplied by any number...    Compressed response

Parent stats: {...}                 Cumulative session statistics
Spawned sub-agents: 3               Sub-agents created in last Run()
You are a calculation reviewer...    Sub-agent system prompts
```

The Caveman phase demonstrates `agent.UseSkill()` registering a skill before
a prompt asks the model to load it. Registration alone is not activation.

### Patient analysis demo output map

```
OUTPUT LINE                          WHAT IT MEANS
─────────────────────────────────────────────────────────────

[agent iteration 1/10]              Iteration 1 of max 10
Total tool calls: 4                 Cumulative session tool calls; inspect
                                   the trace for the actual tools used

--- Parent analysis ---             Briefing generated by parent agent
Synthetic Healthcare Briefing...      Structured output from skill

[EvidenceReviewer] called as tool   Evidence review delegation
Total tool calls: 8                  Cumulative session tool calls

--- Evidence sub-agent ---           Result from EvidenceReviewer
Synthetic Healthcare Briefing...      Reviewed briefing

[SafetyReviewer] called as tool      Safety review delegation

--- Safety sub-agent ---              Result from SafetyReviewer

[Delegation] Creating sub-agent      Data Analyst sub-agent created
with role 'data analyst'

--- Generic delegated sub-agent ---   Result from Data Analyst

Parent stats: {...}                 Final cumulative statistics
Spawned sub-agents: 1               Sub-agents from last Run() call only
```

If `Spawned sub-agents` shows one instead of three, note that each
`agent.Run()` call may clean up children created by earlier calls. The
`[EvidenceReviewer] called as tool`, `[SafetyReviewer] called as tool`, and
`[Delegation] Creating...` messages still demonstrate that all three
sub-agents were created and executed. The final count reflects the children
associated with the most recent `Run()` call.

---

## Summary

### End-to-end flow

1. **The user submits a prompt.** The model interprets the request.
2. **The model chooses an action.** It selects tools according to the request, active skills, and available tools.
3. **AI Hub executes the action.** This may involve a native IRIS tool, an external MCP tool, or sub-agent delegation.
4. **AI Hub returns the result.** The result becomes part of the conversation context.
5. **The model continues.** The loop ends when the model produces a final answer or reaches the iteration limit.

### Delegation pattern

```
Parent Agent
    │
    ├─► Tool: ReviewEvidence
    │       │
    │       ▼
    │   EvidenceReviewer Sub-Agent
    │       (isolated, specialized)
    │
    ├─► Tool: ReviewSafety
    │       │
    │       ▼
    │   SafetyReviewer Sub-Agent
    │       (isolated, specialized)
    │
    └─► Tool: Execute
            │
            ▼
        Generic Sub-Agent
        (dynamic role, context)
```

Each sub-agent:

- has its own system prompt;
- has its own session;
- runs independently;
- returns its result to the parent;
- is tracked temporarily in the parent's `SubAgents` collection.

### Tool hierarchy

```
ToolManager
    │
    ├─► ToolSet: Test.ToolSet.Local
    │       └─► Class: Test.Tools.Patients
    │               ├─► Method: SearchPatients [WebMethod]
    │               └─► Method: SummarizePatients [WebMethod]
    │
    ├─► ToolSet: Test.ToolSet.StatisticsMCP
    │       └─► MCP: /usr/irissys/bin/irispython mcp-python-server.py
    │               ├─► Tool: add_numbers
    │               ├─► Tool: get_mcp_info
    │               ├─► Tool: count_categories
    │               └─► Tool: summarize_measurements
    │
    ├─► Tool: ReviewCalculation (CalculationReviewer)
    ├─► Tool: ReviewEvidence (EvidenceReviewer)
    ├─► Tool: ReviewSafety (SafetyReviewer)
    └─► Tool: Execute (DelegateTasks)
```

These tools are available to the model whenever it decides how to handle a
request.
