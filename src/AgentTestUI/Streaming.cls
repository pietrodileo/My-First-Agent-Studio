/// Separate streaming path; reuse existing session and skill operations without changing Send.
Class AgentTestUI.Streaming Extends %RegisteredObject
{
Property Row As AgentTestUI.Data.Conversation;
Property Agent As %AI.Agent;
Property Session As %AI.Agent.Session;
Property Message As %String(MAXLEN="");
Property Iteration As %Integer;
Property Disconnected As %Boolean [ InitialExpression = 0 ];

/// One-time SSE comment clears this image's 128 KiB gateway aggregation buffer.
Parameter GatewayPreludeBytes = 131072;


/// Validate before committing SSE headers. Omitted skills preserve the saved selection.
Method Prepare(id As %String, body As %DynamicObject) As %Status
{
  Try {
    If '$IsObject(body) Return $$$ERROR($$$GeneralError,"JSON object required")
    If 'body.%IsA("%Library.DynamicObject") Return $$$ERROR($$$GeneralError,"JSON object required")
    If body.%GetTypeOf("message")'="string" Return $$$ERROR($$$GeneralError,"message must be a string")
    Set ..Message=body.message
    If $ZSTRIP(..Message,"<>W")="" Return $$$ERROR($$$GeneralError,"message is required")
    Set ..Row=##class(AgentTestUI.Data.Conversation).Open(id)
    If '$IsObject(..Row) Return $$$ERROR($$$GeneralError,"conversation not found")
    Set skills=body.%Get("activeSkills",..Row.GetSkills())
    If '$IsObject(skills) Return $$$ERROR($$$GeneralError,"activeSkills must be an array")
    If 'skills.%IsA("%Library.DynamicArray") Return $$$ERROR($$$GeneralError,"activeSkills must be an array")
    Set sc=##class(AgentTestUI.Runtime).Agent(..Row.AgentClass,..Row.ModelOverride,.agent)
    If $$$ISERR(sc) Return sc
    Set ..Agent=agent
    Set sc=..Row.RestoreSession(agent,.session)
    If $$$ISERR(sc) Return sc
    Set ..Session=session
    Set sc=##class(AgentTestUI.Runtime).ConfigureSkills(..Row.AgentClass,agent,skills)
    If $$$ISERR(sc) Return sc
    Set sc=##class(AgentTestUI.Runtime).ApplySkills(agent,session,skills)
  } Catch ex {
    Set sc=ex.AsStatus()
  }
  Quit sc
}

/// JSON keeps embedded newlines and Unicode inside one SSE data field.
ClassMethod Frame(event As %String, data As %DynamicObject) As %String
{
  Quit "event: "_event_$Char(10)_"data: "_data.%ToJSON()_$Char(10,10)
}

Method Emit(event As %String, data As %DynamicObject)
{
  If ..Disconnected Quit
  Try {
    Set %response.IgnoreRESTOutput=0
    If event="start" Write ": "_$Justify("",..#GatewayPreludeBytes)_$Char(10,10)
    Write ..Frame(event,data)
    Set sc=%response.Flush()
    Set %response.IgnoreRESTOutput=1
    If $$$ISERR(sc) Set ..Disconnected=1
  } Catch ex {
    Set %response.IgnoreRESTOutput=1
    Set ..Disconnected=1
  }
}

/// Native callback receives text as it is generated, including intermediate iterations.
Method OnChunk(chunk As %String)
{
  If chunk'="" Do ..Emit("delta",{"iteration":(..Iteration),"content":(chunk)})
}

Method Save(content As %String, role As %String) As %Status
{
  Do ..Row.SaveSession(..Session)
  Set messages=..Row.GetMessages()
  Do messages.%Push({"role":"user","content":(..Message)})
  Do messages.%Push({"role":(role),"content":(content)})
  If (..Row.Title="")!(..Row.Title="New chat") Set ..Row.Title=$Extract($Translate(..Message,$Char(10,13),"  "),1,60)
  Set ..Row.UpdatedAt=$ZDATETIME($HOROLOG,3)
  Do ..Row.SaveMessages(messages)
  Do ..Row.SaveSkills(##class(AgentTestUI.Runtime).ActiveSkillIds(..Session))
  Quit ..Row.%Save()
}

Method Run()
{
  Set %response.ContentType="text/event-stream"
  Set %response.CharSet="utf-8"
  Set %response.AllowOutputFlush=1
  Set %response.GzipOutput=0
  Do %response.SetHeader("CSP-gzip","0")
  Do %response.SetHeader("CSP-AllowOutputFlush","1")
  Do %response.SetHeader("Cache-Control","no-cache, no-transform")
  Do %response.SetHeader("X-Accel-Buffering","no")
  Do ..Emit("start",{"conversationId":(..Row.ConversationId)})
  Set saving=0
  Set initialTools=..Session.GetStats().%Get("total_tool_calls",0)
  Try {
    // Match Run's iteration limit and stopping condition using native StreamChat.
    For iteration=1:1:10 {
      Set ..Iteration=iteration
      Do ..Emit("progress",{"iteration":(iteration),"phase":"generating"})
      Set input=$Select(iteration=1:..Message,1:"")
      Set response=..Agent.StreamChat(..Session,input,$This,"OnChunk")
      Do ..Emit("progress",{"iteration":(iteration),"phase":"iteration_complete","hasToolCalls":(response.HasToolCalls())})
      If 'response.HasToolCalls() Quit
    }
    Set content=$ZSTRIP(response.Content,"<>W"),role="assistant",recovered=0
    If content="",..Session.GetStats().%Get("total_tool_calls",0)>initialTools {
      Do ..Emit("progress",{"phase":"recovering"})
      Set content=##class(AgentTestUI.Runtime).RecoverReply(..Agent,..Session),recovered=(content'="")
    }
    If content="" {
      Set role="notice",content="Native streaming did not produce a final answer. This AI Hub/Ollama preview can return empty output for tool requests without executing the tools. The turn was saved; inspect tool statistics and the outcome before retrying. Keep tool-based chats on the existing JSON API until streaming tool support is verified."
    }
    Set saving=1,sc=..Save(content,role)
    If $$$ISERR(sc) Throw ##class(%Exception.StatusException).CreateFromStatus(sc)
    // Only done confirms persistence. Its content supersedes provisional deltas.
    Do ..Emit("done",{"content":(content),"role":(role),"recovered":(recovered),"stats":(..Session.GetStats()),"activeSkills":(##class(AgentTestUI.Runtime).ActiveSkillIds(..Session))})
  } Catch ex {
    Set detail=$SYSTEM.Status.GetErrorText(ex.AsStatus())
    Set saved=0
    Try {
      If 'saving {
        Set sc=..Save("Generation interrupted. Tools may already have run. Check the outcome before retrying.","notice")
        Set saved=$$$ISOK(sc)
      }
    } Catch saveError {
      Set saved=0
    }
    Do ..Emit("error",{"message":(detail),"saved":(saved),"retrySafe":false})
  }
  // A disconnected client does not replay or cancel tool actions; finish and save.
}
}
