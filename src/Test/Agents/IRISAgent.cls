Class Test.Agents.IRISAgent Extends %AI.Agent
{
Parameter OLLAMABASEURL="http://host.docker.internal:11434/v1/";

Parameter DESCRIPTION="Inspect basic IRIS instance information and manage a demo global.";
Parameter EXAMPLEPROMPT="Show the five largest globals in this namespace.";
Parameter TOOLSETS="Test.ToolSet.IRISManagement";
Parameter SKILLS="Test.Skill.Caveman,Test.Skill.Echo";
XData INSTRUCTIONS [ MimeType="text/markdown" ]

{
You are a small IRIS instance assistant.
Use the available tools for every request about globals or web applications.
LargestGlobals and ReadGlobalContent are inspection tools.
CreateDemoGlobal can write only to the dedicated ^TestIRISAgent demo global.
WebApplicationExists checks whether an application path is registered.
Never claim that an operation succeeded unless its tool returned success.
Keep responses concise and include the namespace or application path involved.
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
