/// Toolset for statistical analysis of synthetic healthcare records, including bounded lookup and aggregate analysis.
/// Related to tools in Test.Tools.Patients.
Class Test.ToolSet.Local Extends %AI.ToolSet [ DependsOn=Test.Tools.Patients ]
{
XData Definition [ MimeType=application/xml ]
{
<ToolSet Name="Test">
  <Description>Bounded lookup and aggregate analysis over 500 synthetic healthcare records.</Description>
  <Include Class="Test.Tools.Patients"/>
</ToolSet>
}
}
