Class Test.Demo.Abstract Extends %RegisteredObject [Abstract]
{
ClassMethod Render(title As %String, content As %String)
{
  Write !,"--- ",title," ---",!
  Do ##class(%AI.System).RenderMarkdown(content)
  Write !
}

ClassMethod ShowPrompt(prompt As %String) As %Status
{
  Do ##class(%AI.System).RenderMarkdown("**=====================**")
  Do ##class(%AI.System).RenderMarkdown("**Prompt**>: "_prompt)
}

ClassMethod RunAgent(agent As %AI.Agent, session As %AI.Agent.Session, prompt As %String, maxIterations As %Integer, monitor, maxRetry As %Integer = 5, Output response As %AI.LLM.Response) As %Status
{
    Set sc = $$$OK
    Set go = 1, i = 0
    While ((i<maxRetry)&&(go=1)) {
        Try {
            Do $INCREMENT(i)
            Set response=agent.Run(session,prompt,maxIterations,monitor)
            If $ISOBJECT(response) {
                Set go=0
            } Else {
                $$$ThrowOnError($$$ERROR($$$GeneralError,"Agent call was wrong"))
            }
        } Catch ex {
            Set sc=ex.AsStatus()
            write "Error occurred at retry "_i_". Details: "_$SYSTEM.Status.GetErrorText(sc)
        }
    }
    Do ..Render("Response: ",response.Content)
    Return sc
}

}
