Class Test.PatientAnalysisDemo Extends Test.Demo.Abstract
{
ClassMethod Run(model As %String="") As %Status
{
  Set sc=##class(Test.Setup).Run()
  If $$$ISERR(sc) Quit sc

  Set agent=##class(Test.Agent).%New()
  Set sc=agent.%Init()
  If $$$ISERR(sc) Quit sc
  If model'="" Set agent.Model=model

  Set session=agent.CreateSession()
  Set monitor=##class(Test.DemoMonitor).%New()
  Set maxIterations=5
  Set prompt="Load the synthetic-healthcare-analysis-brief skill. Analyze synthetic patients whose diagnosis is Diabetes. "
  _"Use SummarizePatients for cohort metrics, SearchPatients for exactly three example records, and summarize_measurements for their treatment costs. "
  _"Produce the required evidence-bound briefing."
  Do ..ShowPrompt(prompt)  
  Set draft=agent.Run(session,prompt,10,monitor)
  Do ..Render("Parent analysis",draft.Content)

  Set evidencePrompt="Call ReviewEvidence to delegate an evidence review of this draft:"_$CHAR(10)_draft.Content
  Do ..ShowPrompt(evidencePrompt)
  Set sc=..RunAgent(agent,session,evidencePrompt,maxIterations,monitor,,.response)

  Set safetyPrompt="Call ReviewSafety to delegate a safety review of this draft:"_$CHAR(10)_draft.Content
  Do ..ShowPrompt(safetyPrompt)
  Set sc=..RunAgent(agent,session,safetyPrompt,maxIterations,monitor,,.response)

  Set prompt="Call Execute to delegate this task to a sub agent which should summarize and explain the results of the analysis."
  Do ..ShowPrompt(prompt)  
  Set sc = ..RunAgent(agent, session, prompt, maxIterations, monitor,, .response)

  ; Show stats 
  Do ##class(%AI.System).RenderMarkdown("**=====================**")
  Write "Parent stats: ",session.GetStats().%ToJSON(),!
  Write "Spawned sub-agents: ",agent.SubAgents.Count(),!
  Write "Subagents info: ",!
  For i=1:1:agent.SubAgents.Count() {
    Write !,agent.SubAgents.GetAt(i).SystemPrompt,!
  }
  Write !,"Active skills: ",session.ActiveSkills.%ToJSON(),!,!
  Write !,"Available Tools: ",agent.ToolManager.%Discover().%ToJSON(),!,!

  Quit $$$OK
}

}
