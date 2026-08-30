/// Bounded IRIS inspection tools plus one safe demo write operation.
Class Test.Tools.IRISManagement Extends %AI.Tool
{

/// Return the largest non-system globals visible in the current namespace.
///
/// Args:
///     limit: Number of globals to return, from 1 to 20.
Method LargestGlobals(limit As %Integer=10) As %DynamicObject [ WebMethod ]
{
  If limit<1 Set limit=1
  If limit>20 Set limit=20

  Set rows=[]
  Set out={"namespace":($NAMESPACE),"unit":"MB","estimated":true,"rows":(rows)}
  Set list=##class(%ResultSet).%New("%SYS.GlobalQuery:NameSpaceList")
  Set sc=list.Execute($NAMESPACE,"*",0,.unavailable,0,1,0)
  If $$$ISERR(sc) Quit {"error":($SYSTEM.Status.GetErrorText(sc))}

  While list.Next() {
    Set name=list.GetData(1)
    Continue:name["("
    Set size=##class(%ResultSet).%New("%SYS.GlobalQuery:NameSpaceSize")
    Set sc=size.Execute("^"_name,1,1)
    If $$$ISERR(sc) Continue
    Set mb=0
    While size.Next() {
      Set mb=mb+$SELECT(size.GetData(4)'="":+size.GetData(4),1:+size.GetData(3))
    }
    Set sizes(name)=mb
  }

  For rank=1:1:limit {
    Set name=""
    Set largest=""
    Set largestMB=-1
    For  {
      Set name=$ORDER(sizes(name))
      Quit:name=""
      If sizes(name)>largestMB {
        Set largest=name
        Set largestMB=sizes(name)
      }
    }
    Quit:largest=""
    Do rows.%Push({"global":("^"_largest),"sizeMB":(largestMB)})
    Kill sizes(largest)
  }

  Quit out
}

/// Read a bounded sample of top-level nodes from a global in the current namespace.
///
/// Args:
///     globalName: Global name with or without the leading caret.
///     limit: Maximum number of nodes to return, from 1 to 20.
Method ReadGlobalContent(globalName As %String,limit As %Integer=10) As %DynamicObject [ WebMethod ]
{
  If limit<1 Set limit=1
  If limit>20 Set limit=20
  Set name=$SELECT($EXTRACT(globalName)="^":$EXTRACT(globalName,2,*),1:globalName)

  Set rows=[]
  Set out={"namespace":($NAMESPACE),"global":("^"_name),"rows":(rows),"truncated":false}
  Set root="^"_name
  If $DATA(@root)#2 {
    Do rows.%Push({"reference":(root),"value":($EXTRACT($GET(@root),1,500))})
  }

  Set subscript=""
  For  {
    Set subscript=$ORDER(@root@(subscript))
    Quit:subscript=""
    If rows.%Size()>=limit {
      Do out.%Set("truncated","true")
      Quit
    }
    Set reference=root_"("_subscript_")"
    Set value=$GET(@root@(subscript))
    Do rows.%Push({"reference":(reference),"value":($EXTRACT(value,1,500))})
  }
  Quit out
}

/// Create or update one node in the dedicated ^TestIRISAgent demo global.
///
/// Args:
///     key: Demo node key, limited to 100 characters.
///     value: Demo node value, limited to 500 characters.
Method CreateDemoGlobal(key As %String,value As %String) As %DynamicObject [ WebMethod ]
{
  If key="" Quit {"error":"key is required"}
  If $LENGTH(key)>100 Quit {"error":"key must not exceed 100 characters"}
  If $LENGTH(value)>500 Quit {"error":"value must not exceed 500 characters"}

  Set existed=$DATA(^TestIRISAgent(key))#2
  Set ^TestIRISAgent(key)=value
  Quit {
    "success":true,
    "namespace":($NAMESPACE),
    "global":"^TestIRISAgent",
    "key":(key),
    "created":('existed),
    "value":(value)
  }
}

/// Check whether a web application path is registered in IRIS.
///
/// Args:
///     path: Absolute web application path, for example /agent-test-ui.
Method WebApplicationExists(path As %String) As %DynamicObject [ WebMethod ]
{
  set actualNamespace = $ZNSPACE
  zn "%SYS"
  If $EXTRACT(path)'="/" Quit {"error":"path must start with /"}
  If $LENGTH(path)>200 Quit {"error":"path must not exceed 200 characters"}
  Set out={}
  Try {
    Set exists=##class(Security.Applications).Exists(path)
    Set out={"path":(path),"exists":(exists)}
  } Catch exception {
    Set out={"error":(exception.DisplayString()),"path":(path)}
  }
  zn actualNamespace
  Quit out
}

}
