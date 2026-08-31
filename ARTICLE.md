# My First Agent Studio: building and testing native IRIS agents with AI Hub and Ollama

What does it take to go from an ObjectScript class to an agent that can call tools, use skills, and delegate part of a task?

I built **My First Agent Studio** to make that process easier to explore. It includes small native `%AI.Agent` examples, terminal demos, a synthetic dataset, and a browser workspace for testing the same agents interactively. Everything except the local model service is packaged in a Docker Compose project.

The project is my contribution to the [InterSystems Community Bounty Program — Round 2](https://community.intersystems.com/post/community-bounty-program-idea-application-%E2%80%94-round-2-live). It brings together two ideas:

- [My First Agent (End-To-End Starter)](https://ideas.intersystems.com/ideas/DPI-I-986): learn the SDK through a small task involving tools, skills, an external MCP server, and sub-agents.
- [Generic Agent Test UI for %AI.Agent](https://ideas.intersystems.com/ideas/DPI-I-984): select an existing agent class and chat with it, using the behavior defined in that class.

The source is available in the [My First Agent Studio repository](https://github.com/pietrodileo/My-First-Agent-Studio). The [README](README.md) contains the full setup instructions and example transcripts; this article focuses on how the pieces work together.

## Contents

- [1. What the project runs](#1-what-the-project-runs)
- [2. Start the environment](#2-start-the-environment)
- [3. A first conversation in ObjectScript](#3-a-first-conversation-in-objectscript)
- [4. Tools, skills, and a small arithmetic task](#4-tools-skills-and-a-small-arithmetic-task)
- [5. Delegating work to another agent](#5-delegating-work-to-another-agent)
- [6. From arithmetic to a synthetic dataset](#6-from-arithmetic-to-a-synthetic-dataset)
- [7. Testing the same agents in the browser](#7-testing-the-same-agents-in-the-browser)
- [8. Add your own agent](#8-add-your-own-agent)
- [9. What to verify and where to go next](#9-what-to-verify-and-where-to-go-next)

## 1. What the project runs

The agents run inside InterSystems IRIS using the AI Hub preview. Ollama supplies the model, while ObjectScript defines the instructions, toolsets, skills, and delegation logic.

I chose Ollama so developers can try these features without a paid model API or a cloud-provider API key. You still need an AI Hub-enabled IRIS image and enough local resources to run your chosen model. In particular, use a tool-capable model for the tool and delegation examples: a model that produces good conversational answers may still struggle to call tools correctly.

The application has the following structure:

```text
Browser: React UI
    |
    v
Nginx: static files and /api/* proxy
    |
    v
IRIS: REST API, native agents, sessions, chat history
    |-- Ollama: model inference
    |-- ObjectScript tools: synthetic patient queries
    `-- Python MCP process: arithmetic and statistics over stdio
```

There is no Node middleware executing the agents. The frontend sends requests to IRIS, and IRIS owns execution and persistence. The Python MCP server is an external process launched inside the IRIS container, not another Compose service or a hosted API.

If MCP is new to you, my earlier article, [Model Context Protocol (MCP) with InterSystems IRIS: From Zero to Hero](https://community.intersystems.com/post/model-context-protocol-mcp-intersystems-iris-zero-hero), covers the protocol and server structure. Here, the focus is on an IRIS agent *consuming* MCP tools.

## 2. Start the environment

This project requires the AI Hub preview, not a standard IRIS image. Download the appropriate image from the [Early Access Program portal](https://evaluation.intersystems.com/Eval/early-access/AIHub), following the [official AI Hub repository](https://github.com/intersystems-community/ai-hub-eap). The preview is not intended for production, and its APIs may change.

Load the downloaded archive:

```bash
docker image load -i /path/to/downloaded-iris-ai-hub-image.tar.gz
```

The current [Dockerfile](Dockerfile) uses:

```dockerfile
FROM docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.136.0
```

Check that the loaded image matches this name and your machine's architecture. If your download has a different tag, update the Dockerfile and check SDK compatibility. The internal registry address is not an instruction to pull an image anonymously.

With Ollama running and a suitable model already pulled, run these commands from the project directory:

```bash
ollama list
cp .env.example .env
```

Set the connection and an exact installed model name in `.env`:

```dotenv
OLLAMA_BASE_URL=http://host.docker.internal:11434/v1/
OLLAMA_MODEL=your-installed-model-name
```

The URL must be reachable from the IRIS container. Adjust the hostname if Ollama runs elsewhere or your Docker environment does not resolve `host.docker.internal`.

Start the backend and browser UI:

```bash
docker compose --profile ui up -d --build --wait --wait-timeout 180
```

The UI is available at [localhost:5174](http://localhost:5174), and the [IRIS Management Portal](http://localhost:9392/csp/sys/UtilHome.csp?$NAMESPACE=FIRST_AGENT) uses port `9392`. The application namespace is `FIRST_AGENT`.

For terminal-only work, start just the backend:

```bash
docker compose up -d --build --wait --wait-timeout 180 iris
```

The build imports the application classes and installs the dataset. For background on the container setup, see [Running InterSystems IRIS with Docker: From the Basics to Custom Dockerfile](https://community.intersystems.com/post/running-intersystems-iris-docker-step-step-guide-part-1-basics-custom-dockerfile).

## 3. A first conversation in ObjectScript

Before opening the browser, it is useful to run one conversation directly. This makes the distinction between the agent and its session explicit.

Open the terminal:

```bash
docker compose exec iris iris session IRIS -U FIRST_AGENT
```

Then create the bundled simple chat agent:

```objectscript
Set agent=##class(Test.Agents.SimpleAgent).%New()
Set sc=agent.%Init()
Do $SYSTEM.Status.DisplayError(sc)
```

If initialization reports an error, fix it before continuing. Otherwise:

```objectscript
Set session=agent.CreateSession()
Set monitor=##class(Test.DemoMonitor).%New()
Set prompt="I have three tasks to finish today. Can you help me decide which one to do first?"
Set response=agent.Run(session,prompt,10,monitor)
Do ##class(%AI.System).RenderMarkdown(response.Content)
```

`%Init()` initializes the agent's configuration. `CreateSession()` creates the conversation context. `Run()` submits a prompt, with an iteration limit and the demo monitor. The returned response exposes its text through `Content`.

Keep the same session for a follow-up:

```objectscript
Set prompt="One task has a deadline today; the other two can wait until Friday."
Set response=agent.Run(session,prompt,10,monitor)
Do ##class(%AI.System).RenderMarkdown(response.Content)
```

The provider configuration lives in [SimpleAgent.cls](src/Test/Agents/SimpleAgent.cls). This excerpt shows how the local endpoint is passed to the SDK:

```objectscript
Set base=$SYSTEM.Util.GetEnviron("OLLAMA_BASE_URL")
If base="" Set base=..#OLLAMABASEURL
Set ..Provider=##class(%AI.Provider).Create("openai",{"api_key":"ollama","base_url":(base)})
Set ..Model=$SYSTEM.Util.GetEnviron("OLLAMA_MODEL")
```

Here, `"openai"` selects the compatible provider interface; the configured URL points to Ollama. It does not mean the application sends this request to a paid OpenAI endpoint.

The simple agent also declares optional Poet, Echo, and Caveman skills. It has no declared toolsets, but its initialization registers delegation and reviewer tools. It is a conversational starting point, not a strictly tool-free class.

## 4. Tools, skills, and a small arithmetic task

The first guided demo deliberately uses a task whose result is easy to check:

```objectscript
Do ##class(Test.BasicDemo).Run()
```

It creates `Test.MathAgent`, asks for the calculation-review skill, checks the MCP server identity, and calls `add_numbers` with `17` and `25`. It then demonstrates two forms of delegation and a change in response style.

Why start with addition? Because the interesting question is whether the agent actually used the configured tool, not whether a language model knows that the answer is `42`.

### Declaring capabilities

The relevant declarations in [MathAgent.cls](src/Test/Agents/MathAgent.cls) are small:

```objectscript
Class Test.MathAgent Extends Test.Agent
{
Parameter DESCRIPTION="Tutorial agent demonstrating one Skill and an external statistics MCP server.";
Parameter EXAMPLEPROMPT="Load the calculation-review skill, then call add_numbers with first=17 and second=25.";
Parameter TOOLSETS="Test.ToolSet.StatisticsMCP";
Parameter SKILLS="Test.Skill.CalculationReview";
```

This is an excerpt, not the complete class. The class also defines instructions and registers its calculation reviewer. It inherits provider initialization from `Test.Agent`, but declares its own task-specific toolset and skill.

A tool supplies executable behavior. A skill supplies instructions for approaching a task. In this example, the calculation-review skill tells the agent to use a calculation tool, report the operands and result, and check the result using the inverse operation. Its definition is in [CalculationReview.cls](src/Test/Skill/CalculationReview.cls).

### Connecting the MCP process

[StatisticsMCP.cls](src/Test/ToolSet/StatisticsMCP.cls) connects the agent to the Python server through a declarative toolset:

```xml
<ToolSet Name="StatisticsMCP">
  <Description>Deterministic arithmetic and synthetic-data statistics from an external Python MCP process.</Description>
  <MCP Name="HealthcareStatistics">
    <Stdio Executable="/usr/irissys/bin/irispython"
           Args="/home/irisowner/dev/mcp-python-server.py"/>
  </MCP>
</ToolSet>
```

The SDK launches the configured executable and communicates over standard input/output. In [mcp-python-server.py](mcp-python-server.py), the arithmetic tool returns both its inputs and the computed result. With its docstring omitted, the implementation is:

```python
@mcp.tool()
async def add_numbers(first: float, second: float) -> dict:
    return {
        "first": float(first),
        "second": float(second),
        "result": float(first) + float(second),
    }
```

That gives the agent concrete evidence to explain. The same server exposes `get_mcp_info`, which returns an identity marker, and bounded statistical tools used in the second demo. The marker is a diagnostic aid; it is not an authentication mechanism.

### Making skill activation visible

You can also register a skill from the terminal:

```objectscript
Set sc=agent.UseSkill("Test.Skill.Caveman")
Set prompt="Load the Caveman skill and explain your previous answer briefly."
Set response=agent.Run(session,prompt,10,monitor)
Write session.ActiveSkills.%ToJSON(),!
```

In this preview, making a skill available with `UseSkill()` is not the same as proving that it is active. The prompt asks the model to load it; `session.ActiveSkills` lets you inspect the result. A short answer alone is not evidence of activation.

## 5. Delegating work to another agent

The arithmetic demo shows both a dedicated reviewer and a generic delegation tool.

The dedicated [CalculationReviewer](src/Test/SubAgents/CalculationReviewer.cls) is exposed as a `%AI.Tool`. When the parent calls `ReviewCalculation`, the method creates a child agent with a focused review prompt. The core sequence is:

```objectscript
Set subagent=##class(%AI.Agent.SubAgent).Create(..ParentAgent,prompt,"")
Set subagent.ToolManager=##class(%AI.ToolMgr).%New()
Set session=subagent.CreateSession()
Set response=subagent.Run(session,task)
Set output = response.Content
```

The reviewer gets its own session, and its tool manager is explicitly replaced with an empty one. It reviews the supplied calculation rather than repeating the parent's tool workflow. This is an additional model check, not a mathematical guarantee.

The generic [`Execute` tool](src/Test/Tools/DelegateTasks.cls) accepts a task, a specialist role, and optional context. It builds the child's instructions from those inputs, creates a separate session, and returns the child's answer to the parent as a tool result.

For example, the basic demo asks a mental-math teacher to explain multiplication by zero. The parent can then use the Caveman skill to shorten that explanation. This separates three operations that otherwise look similar in a chat transcript: calling executable code, delegating a task, and changing the instructions used to compose an answer.

Inspect the execution as well as the response:

```objectscript
Write session.GetStats().%ToJSON(),!
Write agent.SubAgents.Count(),!
Write agent.ToolManager.%Discover().%ToJSON(),!
```

## 6. From arithmetic to a synthetic dataset

The second demo adds native IRIS data access:

```objectscript
Do ##class(Test.PatientAnalysisDemo).Run()
```

During installation, the project imports all 500 records from [synthetic_healthcare_data.csv](data/synthetic_healthcare_data.csv), derived from the [Synthetic Healthcare Patient Records Dataset by dnation on Kaggle](https://www.kaggle.com/datasets/dnation/synthetic-healthcare-patient-records-dataset).

The records contain patient codes, age, gender, BMI, blood pressure, cholesterol, smoker and diabetic flags, diagnosis, treatment cost, admission and discharge dates, and outcome. There are no real patient records or names. [Test.Data.Patient](src/Test/Data/Patient.cls) stores the data in `Test_Data.Patient`; its importer splits blood pressure into systolic and diastolic values and converts dates and yes/no fields to native IRIS types.

### Keep data access in the tools

The healthcare agent declares two toolsets:

```objectscript
Parameter TOOLSETS="Test.ToolSet.Local,Test.ToolSet.StatisticsMCP";
```

The [local toolset](src/Test/ToolSet/Local.cls) includes `Test.Tools.Patients`. Its `SearchPatients` method returns bounded patient rows, while `SummarizePatients` performs cohort aggregation in SQL.

In [Patients.cls](src/Test/Tools/Patients.cls), the search implementation clamps the requested row limit between 1 and 50. It prepares a fixed SQL statement and passes filter values separately to `%Execute()`. The model selects tool arguments; it does not supply arbitrary SQL to these methods.

The division of work is intentional:

- IRIS retrieves patient records and calculates cohort aggregates.
- The MCP server calculates descriptive statistics over a bounded list of values already returned by IRIS.
- The model explains the evidence and can request evidence and safety reviews.

### Do not confuse the sample with the cohort

The demo uses the Diabetes diagnosis filter. The bundled data yields a cohort of 115 records. Its first three examples are `P001`, `P002`, and `P013`.

These produce two different treatment-cost summaries:

| Scope | Records | Mean treatment cost |
| --- | ---: | ---: |
| Diabetes cohort, aggregated in IRIS | 115 | 2,398.24 |
| Three returned examples, summarized by MCP | 3 | 2,306.14 |

Both values have a role, but the three-record mean must not be described as the cohort mean. This is a useful test of whether the final explanation preserves the scope of its evidence.

The demo subsequently calls evidence and safety reviewers and delegates an explanation to a data analyst. These steps demonstrate review patterns; they do not make model output clinically reliable. The dataset is synthetic, and the agent's instructions prohibit diagnosis, individual risk assessment, and treatment advice.

For your own prompts, use the [manual terminal session in the README](README.md#manual-terminal-session). It keeps the same agent and session between turns so you can explore follow-up questions without rerunning the whole demo.

## 7. Testing the same agents in the browser

Once the terminal flow is clear, the browser provides a more convenient place to repeat experiments.

![IRISAgent homepage with its suggested prompt and available skills](pic/1_homepage.png)

*The starting screen with IRISAgent selected. Recent chats, Configuration, and Selected agent can be collapsed independently.*

Select an agent, choose a model, and send a message. The composer expands as you type or paste multiple lines, then scrolls vertically at its height limit. Enter sends; Shift+Enter inserts a newline. Replies support Markdown tables, code blocks, and KaTeX math rendering. The workspace shows execution statistics and lets you reopen saved conversations from **Recent chats**.

![IRISAgent response listing globals and estimated sizes](pic/2_chat_example.png)

*“Show the five largest globals in this namespace.” The table contains estimates from this instance; another installation will produce different values.*

This example uses [IRISAgent](src/Test/Agents/IRISAgent.cls) and its [IRISManagement toolset](src/Test/ToolSet/IRISManagement.cls). The native `LargestGlobals` method bounds the requested result count to 1–20, queries global sizes, and returns the namespace, units, and an explicit estimated-size flag. The model turns that result into an explanation. The screenshot also shows one recorded tool call: the table alone would not prove execution.

The toolset additionally exposes a bounded content sample, a web-application existence check, and a write method restricted to the dedicated `^TestIRISAgent` demo global. It is not a production administration console; global reads can expose instance data, so keep this demo in a trusted environment.

### How agents appear without frontend registration

[AgentTestUI.Runtime](src/AgentTestUI/Runtime.cls) queries `%Dictionary.CompiledClass`. It checks whether each application class extends `%AI.Agent` and excludes abstract classes and names beginning with `%`.

For each discovered agent, it reads class parameters such as `DESCRIPTION`, `EXAMPLEPROMPT`, `TOOLSETS`, and `SKILLS`. When starting a conversation, it instantiates the selected class and calls `%Init()`.

This keeps the agent definition in ObjectScript. Adding a class does not require adding a matching entry to a React registry. Discovery only establishes that the class is a concrete agent subclass, however: missing provider configuration can still make initialization fail.

### Choose from your installed Ollama models

![Model selector populated with models from the configured Ollama instance](pic/5_model_choice.png)

*The model list comes from the configured Ollama instance, not a hard-coded catalog.*

The [REST router](src/AgentTestUI/REST/Router.cls) retrieves installed models through Ollama's `/api/tags` endpoint. After pulling another model, reload the browser to refresh the list. If discovery produces no models, the UI falls back to `OLLAMA_MODEL`; that fallback does not download anything or prove that the server is reachable.

The selected model is saved when a conversation is created. To compare two models, start a new chat for each and use the same agent, skill selection, and prompt. Agent and model controls are disabled once a conversation exists. The pictured model names reflect that local installation, not a required model list or a compatibility guarantee.

### Load a skill and see its state

![Caveman loaded with an immediate Studio confirmation](pic/4_skill_loading.png)

*The Load action has completed: Caveman is marked Active, the button now says Unload, and Studio confirms the saved change.*

New chats start with no active skills. Clicking **Load** sends an explicit command to IRIS, which activates the instructions immediately and saves the session. It also adds a **Studio** confirmation to the visible conversation. That message comes from the application, not the model; no inference request is needed to activate a skill.

In [AgentTestUI.Runtime](src/AgentTestUI/Runtime.cls), `UpdateSkills()` validates the selected class IDs, registers the skills, restores the session, and calls `ApplySkills()`. The latter replaces the available and active instruction snapshots through session export/import. Finally, the runtime saves the session, active IDs, and confirmation message. This preview-specific implementation deserves regression checks when upgrading the SDK.

The frontend uses `POST /api/conversations/:id/skills` and adopts the state returned by the server. It does not mark a skill active before the request succeeds. Loading before the first prompt creates the conversation, so select your agent and model first. Skill changes are disabled while another request is running.

![SimpleAgent answering a calculation prompt with Poet active](pic/3_example_talk_like_a_poet.png)

*Poet changes how SimpleAgent explains the calculation. The activation notice and active-state controls are separate from the model's prose.*

For a reproducible prompt, use:

```text
You have the numbers: 12, 7, 25, 4, 18, 9.
Find the sum, average, largest number, and smallest number.
Then explain your calculations briefly and give the final results in a table.
```

The expected values are 75, 12.5, 25, and 4. Compare separate conversations with Poet and Caveman: the calculation should stay the same while the wording changes. This tests style and arithmetic output; it does not establish that a calculation tool was used. The pictured Poet reply records zero tool calls.

[Caveman](src/Test/Skill/Caveman.cls) specifies **ULTRA** directly in its instructions: keyword-first fragments, no filler, and a 3–12-word target for simple answers. There is no extra mode to request after loading it. Required detail, valid code, and explicit safety warnings take priority over brevity. These are model instructions, not a guaranteed word limit.

**Unload** removes the active instructions immediately, but does not erase earlier messages. The sidebar count and summary above the composer show the current selection. For a clean style comparison, use separate chats; prior wording remains part of an existing conversation.

Chat history and SDK session state are stored in IRIS, not browser storage. Reopening a conversation restores the saved context and skills. Persistence has a deployment caveat: this Compose configuration has no explicitly configured persistent IRIS data volume, so back up data before replacing the container.

## 8. Add your own agent

For a conversational assistant, start with [Test.Agents.SimpleAgent](src/Test/Agents/SimpleAgent.cls). Change its description, example prompt, and `INSTRUCTIONS`, and keep only the skills and registered tools your use case needs.

For a task-oriented agent, inspect [Test.MathAgent](src/Test/Agents/MathAgent.cls). For an agent using application data, inspect [Test.Agent](src/Test/Agents/Agent.cls) and its patient tools.

The development loop is short:

1. Add a concrete `%AI.Agent` subclass under `src`, directly or through an existing agent class.
2. Configure the provider and model, and define the instructions and capabilities in ObjectScript.
3. Compile the class into `FIRST_AGENT`, or rebuild the backend after backing up anything you want to retain.
4. Refresh the browser and select the new class.
5. Test the same agent from the terminal when you need to inspect sessions, tools, or statistics directly.

The UI is deliberately generic. Task-specific validation belongs in the agent's tools and application code, where both terminal and browser execution can use it.

## 9. What to verify and where to go next

A convincing answer is not sufficient proof that an agent followed the intended path. Check the tool calls, returned values, active skills, and delegated work.

The repository includes regression checks that run without an LLM request:

```bash
docker compose exec iris iris session IRIS -U FIRST_AGENT '##class(AgentTestUI.Test).Run()'
```

Expected output includes:

```text
PASS: native %AI.Agent discovery
PASS: skill defaults, activation, replacement, unload, restore, validation
PASS: legacy null reply recovery preserves valid history
PASS: immediate skill commands, confirmation, restore, unload, invalid selection
```

These tests cover discovery and session handling, not the quality of a particular model. For an end-to-end check, run both demos, verify the arithmetic tool result, inspect the healthcare evidence, and reopen a browser conversation after a page reload. Exact wording and token counts will vary.

If a run ends without answer text, the browser runtime attempts one text-only completion over the existing transcript and tool results. It does not replay the tools. If no answer is available after that attempt, it saves the turn with a Studio notice. Inspect action outcomes before retrying: a missing answer does not mean nothing executed. Other provider or tool exceptions still surface as errors.

There are also clear limits to the current setup. It uses a preview SDK, exposes an unauthenticated demo API, and shares chat history rather than isolating it by user. Keep it on a trusted local environment. Model-based reviewers and safety instructions are examples to study, not substitutes for application security or domain validation.

My goal with this project is to make the first few agent experiments concrete: create a session, call an actual tool, activate a skill, delegate a bounded task, and inspect what happened. Once that works in ObjectScript, the browser gives you a place to repeat those experiments with different models and your own agent classes.

The [README](README.md) keeps the runnable examples and manual tests together. For class relationships, API details, and implementation notes, continue with the [developer guide](dev.md).

<!-- Publishing note: upload the five pic/ images to Developer Community and update their URLs. Resolve repository-relative source links against https://github.com/pietrodileo/My-First-Agent-Studio when publishing outside the repository. -->
