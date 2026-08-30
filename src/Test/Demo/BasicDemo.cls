Class Test.BasicDemo Extends Test.Demo.Abstract
{

ClassMethod Run(model As %String="") As %Status
{
  Set agent=##class(Test.MathAgent).%New()
  Set sc=agent.%Init()
  If $$$ISERR(sc) Quit sc
  If model'="" Set agent.Model=model

  Set session=agent.CreateSession()
  Set maxIterations=5
  Set monitor=##class(Test.DemoMonitor).%New()
  Write "Agent: ",$CLASSNAME(agent),!,"Model: ",agent.Model,!

  ; %Init() registers generic and specific delegation tools with this parent.
  Write "Available Tools: ",agent.ToolManager.%Discover().%ToJSON(),!,!

  Set prompt="First load the calculation-review skill. Then call get_mcp_info and return its result."
  Do ..ShowPrompt(prompt)
  Set sc = ..RunAgent(agent, session, prompt, maxIterations, monitor,, .response)
  write "skills: "_agent.Skills,!

  Set prompt="Now call add_numbers with first=17 and second=25. Follow the active calculation-review skill"
  Do ..ShowPrompt(prompt)
  Set sc = ..RunAgent(agent, session, prompt, maxIterations, monitor,, .response)
  write "skills: "_agent.Skills,!

  Set prompt="Call ReviewCalculation to delegate verification of this result to the calculation-review child agent: "_response.Content
  Do ..ShowPrompt(prompt)
  Set sc = ..RunAgent(agent, session, prompt, maxIterations, monitor,, .response)
  write "skills: "_agent.Skills,!

  Set prompt="Call Execute to delegate this task to a mental-math teacher: explain in ten sentences why multiplication by zero always returns zero. Use specialistRole='mental-math teacher'."
  Do ..ShowPrompt(prompt)
  Set sc = ..RunAgent(agent, session, prompt, maxIterations, monitor,, .response)
  
  // Load caveman skill programmatically - demonstrates Method 2 (direct API)
  // This activates the caveman skill which forces minimal/terse responses
  Set sc = agent.UseSkill("Test.Skill.Caveman")
  Set prompt="Using caveman skill, compact the concepts explained from the math teacher"
  Do ..ShowPrompt(prompt)
  Set sc = ..RunAgent(agent, session, prompt, maxIterations, monitor,, .response)
  // Expected: "Zero multiplied by any number equals zero. Zero groups mean nothing, so the product is zero."

  ; Show stats 
  Do ##class(%AI.System).RenderMarkdown("**=====================**")
  Write "Parent stats: ",session.GetStats().%ToJSON(),!
  Write "Spawned sub-agents: ",agent.SubAgents.Count(),!
  For i=1:1:agent.SubAgents.Count() {
    Write !,agent.SubAgents.GetAt(i).SystemPrompt,!
  }
  Write !,"Active skills: ",session.ActiveSkills.%ToJSON(),!,!
  Write !,"Available Tools: ",agent.ToolManager.%Discover().%ToJSON(),!,!
  Quit $$$OK
}

}
