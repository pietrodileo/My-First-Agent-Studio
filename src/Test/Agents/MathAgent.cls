Class Test.MathAgent Extends Test.Agent
{
Parameter DESCRIPTION="Tutorial agent demonstrating one Skill and an external statistics MCP server.";
Parameter EXAMPLEPROMPT="Load the calculation-review skill, then call add_numbers with first=17 and second=25.";
Parameter TOOLSETS="Test.ToolSet.StatisticsMCP";
Parameter SKILLS="Test.Skill.CalculationReview";

XData INSTRUCTIONS [ MimeType="text/markdown" ]
{
You are a small arithmetic tutorial agent. Load the calculation-review skill when asked to calculate. Use StatisticsMCP tools for arithmetic and server identity checks. Use ReviewCalculation when asked to delegate verification to the dedicated reviewer. Use Execute only to create a specialist for a task without a dedicated reviewer. Never invent a tool or sub-agent result.
}

Method RegisterSubAgentTools() As %Status
{
  Do ..RegisterGenericDelegateTool()

  Set reviewer=##class(Test.SubAgents.CalculationReviewer).%New($THIS)
  Do ..ToolManager.AddTool(reviewer)
  Quit $$$OK
}
}
