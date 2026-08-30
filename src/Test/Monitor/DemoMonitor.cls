Class Test.DemoMonitor Extends %RegisteredObject
{
Method OnIterationStart(iteration As %Integer, maxIterations As %Integer, session As %AI.Agent.Session)
{
  Write !,"[agent iteration ",iteration,"/",maxIterations,"]",!
}

Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
{
  Set stats=session.GetStats()
  Set totalToolCalls=stats.%Get("total_tool_calls",0)
  Set totalToolDuration=stats.%Get("total_tool_duration_ms",0)
  Write "Token usage: ",response.Usage.%ToJSON(),!
  Write "Total tool calls: ",totalToolCalls," | Total tool duration (ms): ",totalToolDuration,!
}

ClassMethod CallBackStreamComplete(session As %AI.Agent.Session)
{
  Set stats=session.GetStats()
  Set totalToolCalls=stats.%Get("total_tool_calls",0)
  Set totalToolDuration=stats.%Get("total_tool_duration_ms",0)
  Write "Total tool calls: ",totalToolCalls," | Total tool duration (ms): ",totalToolDuration,!
}


}
