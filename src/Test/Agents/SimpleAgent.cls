Class Test.Agents.SimpleAgent Extends %AI.Agent
{
Parameter OLLAMABASEURL="http://host.docker.internal:11434/v1/";

Parameter DESCRIPTION="A general-purpose conversational assistant that helps users answer questions, understand concepts, and solve simple problems.";
Parameter EXAMPLEPROMPT="I have three tasks to finish today. Can you help me decide which one to do first?";
Parameter TOOLSETS="";
Parameter SKILLS="Test.Skill.Poet,Test.Skill.Echo,Test.Skill.Caveman";
XData INSTRUCTIONS [ MimeType="text/markdown" ]

{
    You are a helpful conversational assistant.
    
    Your goal is to understand what the user needs and help them in a clear, practical, and friendly way.
    
    Guidelines:
    -Answer the user's questions directly.
    -Ask a clarifying question when the request is unclear.
    -Keep answers concise unless the user asks for more detail.
    -Do not invent information. If you are unsure, say so.
    -Maintain context from the conversation.
    -When useful, suggest a reasonable next step.
    
    Always respond naturally, as if you were having a conversation with the user.
}
Method %OnInit() As %Status
{
  Set sc=##super()
  If $$$ISERR(sc) Quit sc

  If '$ISOBJECT(..Provider) {
    Set base=$SYSTEM.Util.GetEnviron("OLLAMA_BASE_URL")
    If base="" Set base=..#OLLAMABASEURL
    Set ..Provider=##class(%AI.Provider).Create("openai",{"api_key":"ollama","base_url":(base)})
    Set ..Model=$SYSTEM.Util.GetEnviron("OLLAMA_MODEL")
    If ..Model="" Quit $$$ERROR($$$GeneralError,"OLLAMA_MODEL is required")
  }

  Set sc=..RegisterSubAgentTools()
  If $$$ISERR(sc) Quit sc
  Quit $$$OK
}

Method RegisterSubAgentTools() As %Status
{
  Do ..RegisterGenericDelegateTool()

  Set evidenceReviewer=##class(Test.SubAgents.EvidenceReviewer).%New($THIS)
  Do ..ToolManager.AddTool(evidenceReviewer)

  Set safetyReviewer=##class(Test.SubAgents.SafetyReviewer).%New($THIS)
  Do ..ToolManager.AddTool(safetyReviewer)

  Quit $$$OK
}

Method RegisterGenericDelegateTool()
{
  Set delegateTool=##class(Test.Tools.DelegateTasks).%New($THIS)
  Do ..ToolManager.AddTool(delegateTool)
}
}
