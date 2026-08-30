Class Test.SubAgents.CalculationReviewer Extends %AI.Tool
{
Parameter DESCRIPTION = "Delegate a calculation result to a specialized child agent for independent verification.";

Property ParentAgent As %AI.Agent;

Method %OnNew(parentAgent As %AI.Agent = "") As %Status [ Private ]
{
  If $ISOBJECT(parentAgent) {
    Set ..ParentAgent=parentAgent
  }
  Quit $$$OK
}

/// Verify a calculation with an isolated child agent.
///
/// Args:
///     task: Calculation, tool result, and relevant evidence to review.
Method ReviewCalculation(task As %String) As %String [ WebMethod ]
{
  Set output = ""
  Try {
    If '$ISOBJECT(..ParentAgent) {
      $$$ThrowStatus($$$ERROR($$$AICoreIncompleteInitialization,$CLASSNAME(),"ParentAgent"))
    }
    Write "["_..%ClassName()_"] called as tool",!
    Set prompt="You are a calculation reviewer. Check only the supplied calculation result. Verify it independently, return PASS or FAIL, and keep the explanation short. Do not claim that you used tools."
    Set subagent=##class(%AI.Agent.SubAgent).Create(..ParentAgent,prompt,"")
    Set subagent.ToolManager=##class(%AI.ToolMgr).%New()
    Set session=subagent.CreateSession()
    Set response=subagent.Run(session,task)
    Set output = response.Content
  } Catch exception {
    Set sc = exception.AsStatus()
    Set output = "Calculation review failed: "_$SYSTEM.Status.GetErrorText(sc)
  }
  Return output
}
}
