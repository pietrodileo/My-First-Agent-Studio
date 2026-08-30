Class Test.Agent Extends %AI.Agent
{
Parameter OLLAMABASEURL="http://host.docker.internal:11434/v1/";

Parameter DESCRIPTION="Synthetic healthcare dataset analysis agent.";
Parameter EXAMPLEPROMPT="Compare synthetic Diabetes patients and summarize treatment costs.";
Parameter TOOLSETS="Test.ToolSet.Local,Test.ToolSet.StatisticsMCP";
Parameter SKILLS="Test.Skill.HealthcareAnalysis,Test.Skill.Poet,Test.Skill.Echo";
XData INSTRUCTIONS [ MimeType="text/markdown" ]

{
You analyze a synthetic healthcare dataset for demonstrations and training. 
Use IRIS tools for patient records and cohort facts. 
Use StatisticsMCP tools only for calculations over bounded values already returned by IRIS. 
Use ReviewEvidence and ReviewSafety when asked to delegate draft review to specialized child agents.
Use Execute only when a task needs a new specialist and no dedicated reviewer matches it.
Follow the healthcare briefing skill. Never provide diagnosis, individual risk assessment, or treatment advice.
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
