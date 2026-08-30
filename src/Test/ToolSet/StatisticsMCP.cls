/// External Python MCP toolset for deterministic arithmetic and synthetic-data statistics.
/// This toolset is used in the BasicDemo test to demonstrate the use of an external MCP process for calculations and statistics.
Class Test.ToolSet.StatisticsMCP Extends %AI.ToolSet
{
XData Definition [ MimeType=application/xml ]
{
<ToolSet Name="StatisticsMCP">
  <Description>Deterministic arithmetic and synthetic-data statistics from an external Python MCP process.</Description>
  <MCP Name="HealthcareStatistics">
    <Stdio Executable="/usr/irissys/bin/irispython"
           Args="/home/irisowner/dev/mcp-python-server.py"/>
  </MCP>
</ToolSet>
}
}
