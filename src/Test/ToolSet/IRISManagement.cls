/// Small, bounded tools for inspecting the current IRIS namespace and writing
/// only to the dedicated demo global.
Class Test.ToolSet.IRISManagement Extends %AI.ToolSet [ DependsOn=Test.Tools.IRISManagement ]
{
XData Definition [ MimeType=application/xml ]
{
<ToolSet Name="IRISManagement">
  <Description>Inspect globals and web applications, and manage the dedicated IRIS agent demo global.</Description>
  <Include Class="Test.Tools.IRISManagement"/>
</ToolSet>
}
}
