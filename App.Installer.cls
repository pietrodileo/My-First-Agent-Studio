Class App.Installer
{
XData setup
{
<Manifest>
  <Default Name="NAMESPACE" Value="FIRST_AGENT"/>
  <Namespace Name="${NAMESPACE}">
    <Import File="/home/irisowner/dev/src" Recurse="1"/>
    <Invoke Class="Test.Setup" Method="Run" CheckStatus="1"/>
  </Namespace>
  <Invoke Class="App.Installer" Method="RegisterWebApplication" CheckStatus="1">
    <Arg Value="${NAMESPACE}"/><Arg Value="/agent-ui/api"/><Arg Value="AgentTestUI.REST.Router"/>
  </Invoke>
</Manifest>
}
ClassMethod RegisterWebApplication(ns As %String, path As %String, dispatch As %String) As %Status
{
  New $Namespace
  Set $Namespace="%SYS"
  Set spec("AutheEnabled")=$$$AutheUnauthenticated
  Set spec("NameSpace")=ns
  Set spec("DispatchClass")=dispatch
  Set spec("IsNameSpaceDefault")=$$$NO
  Set spec("MatchRoles")=":%All"
  Set spec("UseCookies")=$$$NO
  If ##class(Security.Applications).Exists(path) Quit ##class(Security.Applications).Modify(path,.spec)
  Quit ##class(Security.Applications).Create(path,.spec)
}
ClassMethod setup(ByRef pVars,pLogLevel As %Integer=3,pInstaller As %Installer.Installer,pLogger As %Installer.AbstractLogger) As %Status [ CodeMode=objectgenerator, Internal ]
{
  Quit ##class(%Installer.Manifest).%Generate(%compiledclass,%code,"setup")
}
}
