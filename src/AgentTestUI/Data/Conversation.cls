Class AgentTestUI.Data.Conversation Extends %Persistent
{
Property ConversationId As %String(MAXLEN=64) [ Required ];
Property AgentClass As %String(MAXLEN=300) [ Required ];
Property ModelOverride As %String(MAXLEN=200);
Property SessionData As %Stream.GlobalCharacter;
Property Title As %String(MAXLEN=120);
Property MessagesData As %Stream.GlobalCharacter;
Property SkillsData As %String(MAXLEN=4000) [ InitialExpression = "[]" ];
Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($HOROLOG,3)} ];
Property UpdatedAt As %TimeStamp;

Index ConversationIdIndex On ConversationId [ Unique, PrimaryKey ];

Method SaveSession(session As %AI.Agent.Session) As %Status
{
  Set ..SessionData=##class(%Stream.GlobalCharacter).%New()
  Do ..SessionData.Write(session.Export())
  Quit $$$OK
}

Method RestoreSession(agent As %AI.Agent, Output session As %AI.Agent.Session) As %Status
{
  Set session=agent.CreateSession()
  Do ..SessionData.Rewind()
  Quit session.Import(..SessionData.Read())
}

Method SaveMessages(messages As %DynamicArray) As %Status
{
  Set ..MessagesData=##class(%Stream.GlobalCharacter).%New()
  Do ..MessagesData.Write(messages.%ToJSON())
  Quit $$$OK
}

Method GetMessages() As %DynamicArray
{
  If '$ISOBJECT(..MessagesData) Quit []
  Do ..MessagesData.Rewind()
  Set messages=[]
  Try {
    Set messages=[].%FromJSON(..MessagesData)
  } Catch ex {
    Set messages=[]
  }
  Quit messages
}

Method SaveSkills(skills As %DynamicArray) As %Status
{
  Set ..SkillsData=skills.%ToJSON()
  Quit $$$OK
}

Method GetSkills() As %DynamicArray
{
  Set skills=[]
  If ..SkillsData="" Quit skills
  Try {
    Set skills=[].%FromJSON(..SkillsData)
  } Catch ex {
    Set skills=[]
  }
  Quit skills
}

ClassMethod Open(id As %String) As AgentTestUI.Data.Conversation
{
  Set row=$$$NULLOREF
  Try {
    Set row=..ConversationIdIndexOpen(id)
  } Catch ex {
    Set row=$$$NULLOREF
  }
  Quit row
}
Storage Default
{
<Data name="ConversationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ConversationId</Value>
</Value>
<Value name="3">
<Value>AgentClass</Value>
</Value>
<Value name="4">
<Value>ModelOverride</Value>
</Value>
<Value name="5">
<Value>SessionData</Value>
</Value>
<Value name="6">
<Value>Title</Value>
</Value>
<Value name="7">
<Value>MessagesData</Value>
</Value>
<Value name="8">
<Value>CreatedAt</Value>
</Value>
<Value name="9">
<Value>UpdatedAt</Value>
</Value>
<Value name="10">
<Value>SkillsData</Value>
</Value>
</Data>
<DataLocation>^AgentTestUI.Data.ConversationD</DataLocation>
<DefaultData>ConversationDefaultData</DefaultData>
<IdLocation>^AgentTestUI.Data.ConversationD</IdLocation>
<IndexLocation>^AgentTestUI.Data.ConversationI</IndexLocation>
<StreamLocation>^AgentTestUI.Data.ConversationS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
