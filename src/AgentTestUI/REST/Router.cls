Class AgentTestUI.REST.Router Extends %CSP.REST
{

/// Ignore writes from internal methods
Parameter IgnoreWrites As BOOLEAN [ Internal ] = 1;

XData UrlMap
{
<Routes>
<Route Url="/agents" Method="GET" Call="Agents"/>
<Route Url="/providers" Method="GET" Call="Providers"/>
<Route Url="/conversations" Method="GET" Call="Conversations"/>
<Route Url="/conversations" Method="POST" Call="Start"/>
<Route Url="/conversations/:id" Method="GET" Call="Conversation"/>
<Route Url="/conversations/:id/messages" Method="POST" Call="Send"/>
<Route Url="/conversations/:id" Method="DELETE" Call="Delete"/>
</Routes>
}

ClassMethod Agents() As %Status
{
  Set %response.ContentType="application/json"
  Set %response.IgnoreRESTOutput=0
  Write ##class(AgentTestUI.Runtime).Agents().%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}

ClassMethod Providers() As %Status
{
  Set %response.ContentType="application/json"
  Set models=[]
  Set configuredModel=$SYSTEM.Util.GetEnviron("OLLAMA_MODEL")
  Set base=$SYSTEM.Util.GetEnviron("OLLAMA_BASE_URL")
  If base="" Set base="http://host.docker.internal:11434/v1/"
  Try {
    Set https=($EXTRACT(base,1,8)="https://")
    Set rest=$SELECT(https:$EXTRACT(base,9,*),1:$EXTRACT(base,8,*))
    Set authority=$PIECE(rest,"/",1)
    Set request=##class(%Net.HttpRequest).%New()
    Set request.Server=$PIECE(authority,":",1)
    Set request.Port=$SELECT($PIECE(authority,":",2)'="":+$PIECE(authority,":",2),https:443,1:80)
    Set request.Https=https,request.Timeout=5
    Set sc=request.Get("/api/tags")
    If $$$ISOK(sc),request.HttpResponse.StatusCode=200 {
      Set payload={}.%FromJSON(request.HttpResponse.Data)
      Set available=payload.%Get("models",[])
      For index=0:1:(available.%Size()-1) {
        Set modelName=available.%Get(index).%Get("name","")
        If modelName'="" Do models.%Push(modelName)
      }
    }
  } Catch ex {
    // Keep the endpoint usable when Ollama is temporarily unavailable.
  }
  If (models.%Size()=0),(configuredModel'="") Do models.%Push(configuredModel)
  Set %response.IgnoreRESTOutput=0
  Write [{"name":"Ollama","type":"ollama","model":(configuredModel),"models":(models)}].%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}

ClassMethod Start() As %Status
{
  Set body=..Body(.sc)
  If $$$ISERR(sc) Quit ..WriteError(sc,400)
  Set sc=##class(AgentTestUI.Runtime).Start(body.%Get("className",""),body.%Get("model",""),body.%Get("activeSkills",[]),.id)
  If $$$ISERR(sc) Quit ..WriteError(sc,400)
  Set %response.Status="201 Created"
  Set %response.ContentType="application/json"
  Set %response.IgnoreRESTOutput=0 
  Write {"conversationId":(id)}.%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}

ClassMethod Conversations() As %Status
{
  Set %response.ContentType="application/json"
  Set %response.IgnoreRESTOutput=0 
  Write ##class(AgentTestUI.Runtime).Conversations().%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}

ClassMethod Conversation(id As %String) As %Status
{
  Set sc=##class(AgentTestUI.Runtime).Conversation(id,.result)
  If $$$ISERR(sc) Quit ..WriteError(sc,404)
  Set %response.ContentType="application/json"
  Set %response.IgnoreRESTOutput=0
  Write result.%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}

ClassMethod Send(id As %String) As %Status
{
  Set body=..Body(.sc)
  If $$$ISERR(sc) Quit ..WriteError(sc,400)
  Set sc=##class(AgentTestUI.Runtime).Send(id,body.%Get("message",""),body.%Get("activeSkills",[]),.result)
  If $$$ISERR(sc) Quit ..WriteError(sc,400)
  Set %response.ContentType="application/json"
  Set %response.IgnoreRESTOutput=0
  Write result.%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}

ClassMethod Delete(id As %String) As %Status
{
  Set sc=##class(AgentTestUI.Runtime).Delete(id)
  If $$$ISERR(sc) Quit ..WriteError(sc,400)
  Set %response.Status="204 No Content"
  Quit $$$OK
}

ClassMethod Body(Output sc As %Status) As %DynamicObject
{
  Set sc=$$$OK
  Set body={}
  Try {
    Set body={}.%FromJSON(%request.Content)
  } Catch ex {
    Set sc=ex.AsStatus()
  }
  Quit body
}

ClassMethod WriteError(sc As %Status, code As %Integer) As %Status
{
  Set %response.Status=code_" Error"
  Set %response.ContentType="application/json"
  Set %response.IgnoreRESTOutput=0
  Write {"message":($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
  Set %response.IgnoreRESTOutput=1
  Quit $$$OK
}
}
