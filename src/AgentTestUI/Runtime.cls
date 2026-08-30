Class AgentTestUI.Runtime Extends %RegisteredObject
{
ClassMethod Agents() As %DynamicArray
{
  Set out=[]
  Set stmt=##class(%SQL.Statement).%New()
  Set sc=stmt.%Prepare("SELECT Name FROM %Dictionary.CompiledClass WHERE Name <> '%AI.Agent' ORDER BY Name")
  If $$$ISERR(sc) Quit out
  Set rs=stmt.%Execute()
  While rs.%Next() {
    Set name=rs.Name
    If $EXTRACT(name,1)'="%",..Runnable(name) {
      Set item={
        "className":(name),
        "description":($CLASSMETHOD(name,"%GetParameter","DESCRIPTION")),
        "model":($CLASSMETHOD(name,"%GetParameter","MODEL")),
        "provider":($CLASSMETHOD(name,"%GetParameter","PROVIDER")),
        "toolSets":(..Csv($CLASSMETHOD(name,"%GetParameter","TOOLSETS"))),
        "skills":(..Csv($CLASSMETHOD(name,"%GetParameter","SKILLS"))),
        "examplePrompt":($CLASSMETHOD(name,"%GetParameter","EXAMPLEPROMPT"))
      }
      Do out.%Push(item)
    }
  }
  Quit out
}

ClassMethod Runnable(name As %String) As %Boolean
{
  Set runnable=0
  Try {
    If $CLASSMETHOD(name,"%Extends","%AI.Agent") {
      Set definition=##class(%Dictionary.CompiledClass).%OpenId(name)
      If $ISOBJECT(definition),'definition.Abstract Set runnable=1
    }
  } Catch ex {
    Set runnable=0
  }
  Quit runnable
}

ClassMethod Csv(value As %String) As %DynamicArray
{
  Set out=[]
  For index=1:1:$LENGTH(value,",") {
    Set item=$ZSTRIP($PIECE(value,",",index),"<W")
    If item'="" Do out.%Push(item)
  }
  Quit out
}

ClassMethod Agent(name As %String, model As %String, Output agent As %AI.Agent) As %Status
{
  Set sc=$$$OK
  Set agent=$$$NULLOREF
  If '..Runnable(name) Quit $$$ERROR($$$GeneralError,"Agent is not runnable: "_name)
  Try {
    Set agent=$CLASSMETHOD(name,"%New")
    Set sc=agent.%Init()
    If $$$ISOK(sc),model'="" Set agent.Model=model
  } Catch ex {
    Set sc=ex.AsStatus()
  }
  Quit sc
}

ClassMethod ConfigureSkills(name As %String, agent As %AI.Agent, skills As %DynamicArray) As %Status
{
  If '$ISOBJECT(skills) Quit $$$ERROR($$$GeneralError,"activeSkills must be an array")
  If 'skills.%IsA("%DynamicArray") Quit $$$ERROR($$$GeneralError,"activeSkills must be an array")
  Set allowed=..Csv($CLASSMETHOD(name,"%GetParameter","SKILLS"))
  For index=0:1:(skills.%Size()-1) {
    Set skill=skills.%Get(index),found=0
    For allowedIndex=0:1:(allowed.%Size()-1) {
      If allowed.%Get(allowedIndex)=skill Set found=1 Quit
    }
    If 'found Return $$$ERROR($$$GeneralError,"Skill is not available for this agent: "_skill)
    Set sc=agent.UseSkill(skill)
    If $$$ISERR(sc) Return sc
  }
  Quit $$$OK
}

/// Replace active instructions before inference, without changing chat history.
ClassMethod ApplySkills(agent As %AI.Agent, session As %AI.Agent.Session, skills As %DynamicArray) As %Status
{
  Try {
    Set state={}.%FromJSON(session.Export()),available=[],active=[]
    // Older runs saved null assistant replies. They are not valid provider input.
    // Preserve tool-call messages, whose content is legitimately null.
    Set messages=state.messages,clean=[]
    For messageIndex=0:1:(messages.%Size()-1) {
      Set item=messages.%Get(messageIndex)
      If item.role="assistant",item.%Get("content")="",item.%Get("tool_calls",[]).%Size()=0 Continue
      Do clean.%Push(item)
    }
    Set state.messages=clean
    For index=0:1:(skills.%Size()-1) {
      Set id=skills.%Get(index)
      For entryIndex=0:1:(agent.AvailableSkills.%Size()-1) {
        Set entry=agent.AvailableSkills.%Get(entryIndex)
        If entry.id'=id Continue
        Do available.%Push(entry)
        Set snapshot={"id":(entry.id),"name":(entry.name),"source":(entry.source)}
        Do snapshot.%Set("version",entry.%Get("version"),entry.%GetTypeOf("version"))
        Do snapshot.%Set("content_hash",entry.%Get("content_hash"),"string")
        Do snapshot.%Set("instructions_snapshot",entry.instructions)
        Do snapshot.%Set("activated_at",$ZDATETIME($HOROLOG,3,1)_"Z")
        Do active.%Push(snapshot)
        Quit
      }
    }
    Do state.%Set("available_skills",available)
    Do state.%Set("active_skills",active)
    Set sc=session.Import(state.%ToJSON())
  } Catch ex {
    Set sc=ex.AsStatus()
  }
  Quit sc
}

ClassMethod ActiveSkillIds(session As %AI.Agent.Session) As %DynamicArray
{
  Set ids=[],active=session.ActiveSkills
  For index=0:1:(active.%Size()-1) {
    Do ids.%Push(active.%Get(index).id)
  }
  Quit ids
}

ClassMethod Start(name As %String, model As %String, skills As %DynamicArray, Output id As %String) As %Status
{
  Set sc=..Agent(name,model,.agent)
  If $$$ISERR(sc) Quit sc
  Set sc=..ConfigureSkills(name,agent,skills)
  If $$$ISERR(sc) Quit sc
  Set session=agent.CreateSession()
  Set sc=..ApplySkills(agent,session,skills)
  If $$$ISERR(sc) Quit sc
  Set id=$SYSTEM.Util.CreateGUID()
  Set row=##class(AgentTestUI.Data.Conversation).%New()
  Set row.ConversationId=id
  Set row.AgentClass=name
  Set row.ModelOverride=model
  Set row.Title="New chat"
  Set row.UpdatedAt=$ZDATETIME($HOROLOG,3)
  Do row.SaveSession(session)
  Do row.SaveMessages([])
  Do row.SaveSkills(skills)
  Quit row.%Save()
}

ClassMethod Send(id As %String, message As %String, skills As %DynamicArray, Output result As %DynamicObject) As %Status
{
  Set result={}
  If message="" Quit $$$ERROR($$$GeneralError,"message is required")
  Set row=##class(AgentTestUI.Data.Conversation).Open(id)
  If '$ISOBJECT(row) Quit $$$ERROR($$$GeneralError,"conversation not found")

  Set sc=..Agent(row.AgentClass,row.ModelOverride,.agent)
  If $$$ISERR(sc) Quit sc
  Set sc=row.RestoreSession(agent,.session)
  If $$$ISERR(sc) Quit sc
  Set sc=..ConfigureSkills(row.AgentClass,agent,skills)
  If $$$ISERR(sc) Quit sc
  Set sc=..ApplySkills(agent,session,skills)
  If $$$ISERR(sc) Quit sc

  Try {
    Set monitor=##class(Test.DemoMonitor).%New()
    Set response=agent.Run(session,message,10,monitor)
    If $ZSTRIP(response.Content,"<>W")="" {
      Return $$$ERROR($$$GeneralError,"The model returned an empty reply. Please retry; this turn was not saved.")
    }
    Do row.SaveSession(session)
    Set messages=row.GetMessages()
    Do messages.%Push({"role":"user","content":(message)})
    Do messages.%Push({"role":"assistant","content":(response.Content)})
    If (row.Title="")!(row.Title="New chat") Set row.Title=$EXTRACT($TRANSLATE(message,$CHAR(10)_$CHAR(13),"  "),1,60)
    Set row.UpdatedAt=$ZDATETIME($HOROLOG,3)
    Do row.SaveMessages(messages)
    Set skills=..ActiveSkillIds(session)
    Do row.SaveSkills(skills)
    Set sc=row.%Save()
    If $$$ISOK(sc) {
      Set result={
        "content":(response.Content),
        "stats":(session.GetStats()),
        "activeSkills":(skills)
      }
    }
  } Catch ex {
    Set sc=ex.AsStatus()
  }
  Quit sc
}

ClassMethod ArrayToString(arr As %Library.DynamicArray) As %String
{
  Set output = ""
  For i=0:1:arr.%Size()-1{
    Set $LIST(output,*+1) = arr.%Get(i)
  }
  Set output = $LISTTOSTRING(output,",")
  Return output
}

ClassMethod Conversations() As %DynamicArray
{
  Set out=[]
  Set stmt=##class(%SQL.Statement).%New()
  Set sc=stmt.%Prepare("SELECT ConversationId, AgentClass, ModelOverride, Title, CreatedAt, UpdatedAt FROM AgentTestUI_Data.Conversation ORDER BY UpdatedAt DESC, CreatedAt DESC")
  If $$$ISERR(sc) Quit out
  Set rs=stmt.%Execute()
  While rs.%Next() {
    Set title=rs.Title
    If title="" Set title="Previous conversation"
    Do out.%Push({"conversationId":(rs.ConversationId),"agentClass":(rs.AgentClass),"model":(rs.ModelOverride),"title":(title),"createdAt":(rs.CreatedAt),"updatedAt":(rs.UpdatedAt)})
  }
  Quit out
}

ClassMethod Conversation(id As %String, Output result As %DynamicObject) As %Status
{
  Set row=##class(AgentTestUI.Data.Conversation).Open(id)
  If '$ISOBJECT(row) Quit $$$ERROR($$$GeneralError,"conversation not found")
  Set title=row.Title
  If title="" Set title="Previous conversation"
  Set result={"conversationId":(row.ConversationId),"agentClass":(row.AgentClass),"model":(row.ModelOverride),"title":(title),"messages":(row.GetMessages()),"activeSkills":(row.GetSkills()),"createdAt":(row.CreatedAt),"updatedAt":(row.UpdatedAt)}
  Quit $$$OK
}

ClassMethod Delete(id As %String) As %Status
{
  Set row=##class(AgentTestUI.Data.Conversation).Open(id)
  If '$ISOBJECT(row) Quit $$$OK
  Quit ##class(AgentTestUI.Data.Conversation).%DeleteId(row.%Id())
}
}
