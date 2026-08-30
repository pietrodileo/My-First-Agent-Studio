Class Test.SubAgents.SafetyReviewer Extends %AI.Tool
{
Parameter DESCRIPTION = "Delegate a synthetic healthcare draft to a safety-review child agent.";

Property ParentAgent As %AI.Agent;

Method %OnNew(parentAgent As %AI.Agent = "") As %Status [ Private ]
{
  If $ISOBJECT(parentAgent) {
    Set ..ParentAgent=parentAgent
  }
  Quit $$$OK
}

/// Review the safety boundaries of a synthetic healthcare draft.
///
/// Args:
///     draft: Synthetic healthcare analysis draft to review.
Method ReviewSafety(draft As %String) As %String [ WebMethod ]
{
  Write "["_..%ClassName()_"] called as tool",!
  Try {
    If '$ISOBJECT(..ParentAgent) {
      $$$ThrowStatus($$$ERROR($$$AICoreIncompleteInitialization,$CLASSNAME(),"ParentAgent"))
    }
    Set prompt="You are a healthcare safety reviewer. Check only whether the supplied draft clearly says data is synthetic and avoids diagnosis, individual risk scoring, and treatment advice. Return PASS or a short correction list."
    Set subagent=##class(%AI.Agent.SubAgent).Create(..ParentAgent,prompt,"")
    Set subagent.ToolManager=##class(%AI.ToolMgr).%New()
    Set session=subagent.CreateSession()
    Set response=subagent.Run(session,draft)
    Return response.Content
  } Catch exception {
    Return "Safety review failed: "_exception.DisplayString()
  }
}
}
