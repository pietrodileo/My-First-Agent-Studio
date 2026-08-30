Class Test.Setup Extends %RegisteredObject
{
ClassMethod Run() As %Status
{
  Quit ##class(Test.Data.Patient).ImportCSV()
}
}
