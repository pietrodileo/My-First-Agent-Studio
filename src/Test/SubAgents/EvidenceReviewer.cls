Class Test.SubAgents.EvidenceReviewer Extends %AI.Tool
{
Parameter DESCRIPTION = "Delegate a synthetic healthcare draft to an evidence-review child agent.";

Property ParentAgent As %AI.Agent;

Method %OnNew(parentAgent As %AI.Agent = "") As %Status [ Private ]
{
  If $ISOBJECT(parentAgent) {
    Set ..ParentAgent=parentAgent
  }
  Quit $$$OK
}

/// Review the evidence boundaries of a synthetic healthcare draft.
///
/// Args:
///     draft: Synthetic healthcare analysis draft to review.
Method ReviewEvidence(draft As %String) As %String [ WebMethod ]
{
  Try {
    Write "["_..%ClassName()_"] called as tool",!
    If '$ISOBJECT(..ParentAgent) {
      $$$ThrowStatus($$$ERROR($$$AICoreIncompleteInitialization,$CLASSNAME(),"ParentAgent"))
    }
    Set prompt="You are an evidence reviewer. Check only the supplied synthetic healthcare draft. Identify unsupported numbers, missing source boundaries, or mismatches between cohort and example records. Return PASS or a short correction list. Never provide clinical advice."
    Set subagent=##class(%AI.Agent.SubAgent).Create(..ParentAgent,prompt,"")
    Set subagent.ToolManager=##class(%AI.ToolMgr).%New()
    Set session=subagent.CreateSession()
    Set response=subagent.Run(session,draft)
    Return response.Content
  } Catch exception {
    Return "Evidence review failed: "_exception.DisplayString()
  }
}
}
