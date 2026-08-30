Class AgentTestUI.Test Extends %RegisteredObject
{
ClassMethod Run() As %Status
{
  Set items=##class(AgentTestUI.Runtime).Agents()
  If items.%Size()<2 Quit $$$ERROR($$$GeneralError,"Expected at least two runnable agents")
  For class="Test.MathAgent","Test.Agent" {
    If '##class(AgentTestUI.Runtime).Runnable(class) { 
      Return $$$ERROR($$$GeneralError,"Missing agent: "_class)
    }
  }
  Write "PASS: native %AI.Agent discovery",!
  Set sc=..Skills()
  If $$$ISERR(sc) Quit sc
  Quit $$$OK
}

/// Exercise real SDK state transitions without an LLM request or saved conversation.
ClassMethod Skills() As %Status
{
  Set sc=##class(AgentTestUI.Runtime).Agent("Test.Agents.SimpleAgent","",.agent)
  If $$$ISERR(sc) Quit sc
  Set session=agent.CreateSession()
  Set before=session.MessageCount()
  For selection=[],["Test.Skill.Poet"],["Test.Skill.Echo"],[] {
    Set sc=##class(AgentTestUI.Runtime).ConfigureSkills("Test.Agents.SimpleAgent",agent,selection)
    If $$$ISERR(sc) Return sc
    Set sc=##class(AgentTestUI.Runtime).ApplySkills(agent,session,selection)
    If $$$ISERR(sc) Return sc
    Set actual=##class(AgentTestUI.Runtime).ActiveSkillIds(session)
    If actual.%ToJSON()'=selection.%ToJSON() Return $$$ERROR($$$GeneralError,"Active skills differ from selection")
    If session.MessageCount()'=before Return $$$ERROR($$$GeneralError,"Skill transition changed history")
    Set exported=session.Export()
    Set restored=agent.CreateSession()
    Set sc=restored.Import(exported)
    If $$$ISERR(sc) Return sc
    If ##class(AgentTestUI.Runtime).ActiveSkillIds(restored).%ToJSON()'=selection.%ToJSON() Return $$$ERROR($$$GeneralError,"Skills did not survive restore")
  }
  Set sc=##class(AgentTestUI.Runtime).ConfigureSkills("Test.Agents.SimpleAgent",agent,["Test.Skill.NotAvailable"])
  If $$$ISOK(sc) Quit $$$ERROR($$$GeneralError,"Invalid skill was accepted")
  Set state={}.%FromJSON(session.Export())
  Set state.messages=[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi"},{"role":"assistant","content":null}]
  Set sc=session.Import(state.%ToJSON())
  If $$$ISERR(sc) Quit sc
  Set sc=##class(AgentTestUI.Runtime).ApplySkills(agent,session,[])
  If $$$ISERR(sc) Quit sc
  Set state={}.%FromJSON(session.Export())
  If state.messages.%Size()'=2 Quit $$$ERROR($$$GeneralError,"Invalid reply was not removed from model context")
  If state.messages.%Get(1).content'="Hi" Quit $$$ERROR($$$GeneralError,"Valid history was changed")
  Write "PASS: skill defaults, activation, replacement, unload, restore, validation",!
  Write "PASS: legacy null reply recovery preserves valid history",!
  Quit $$$OK
}
}
