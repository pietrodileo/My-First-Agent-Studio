Class Test.Tools.Patients Extends %AI.Tool
{

Method SearchPatients(diagnosis As %String="",diabetic As %String="",smoker As %String="",minimumAge As %Integer=0,maximumAge As %Integer=120,limit As %Integer=20) As %DynamicObject [ WebMethod ]
{
  If limit<1 Set limit=1
  If limit>50 Set limit=50
  If minimumAge<0 Set minimumAge=0
  If maximumAge>120 Set maximumAge=120
  If maximumAge<minimumAge Set maximumAge=minimumAge
  Set diagnosisPattern=$SELECT(diagnosis="":"%",1:diagnosis_"%")
  Set diabeticFilter=$SELECT(diabetic="":"%",diabetic="Yes":1,diabetic="No":0,1:"invalid")
  Set smokerFilter=$SELECT(smoker="":"%",smoker="Yes":1,smoker="No":0,1:"invalid")
  If diabeticFilter="invalid"!(smokerFilter="invalid") Quit {"error":"diabetic and smoker must be Yes, No, or empty"}
  Set rows=[]
  Set out={"source":"synthetic_healthcare_data.csv","rows":(rows),"row_count":0,"truncated":false}
  Set stmt=##class(%SQL.Statement).%New()
  Set sc=stmt.%Prepare("SELECT TOP ? PatientCode,Age,Gender,BMI,SystolicPressure,DiastolicPressure,CholesterolLevel,Smoker,Diabetic,Diagnosis,TreatmentCost,AdmissionDate,DischargeDate,Outcome FROM Test_Data.Patient WHERE Diagnosis LIKE ? AND CAST(Diabetic AS VARCHAR) LIKE ? AND CAST(Smoker AS VARCHAR) LIKE ? AND Age BETWEEN ? AND ? ORDER BY PatientCode")
  If $$$ISERR(sc) Quit {"error":($SYSTEM.Status.GetErrorText(sc))}
  Set rs=stmt.%Execute(limit,diagnosisPattern,diabeticFilter,smokerFilter,minimumAge,maximumAge)
  While rs.%Next() {
    Set patient={
      "patientCode":(rs.PatientCode),
      "age":(rs.Age),
      "gender":(rs.Gender),
      "bmi":(rs.BMI),
      "bloodPressure":(rs.SystolicPressure_"/"_rs.DiastolicPressure),
      "cholesterol":(rs.CholesterolLevel),
      "smoker":(rs.Smoker),
      "diabetic":(rs.Diabetic),
      "diagnosis":(rs.Diagnosis),
      "treatmentCost":(rs.TreatmentCost),
      "admissionDate":($ZDATE(rs.AdmissionDate,3)),
      "dischargeDate":($ZDATE(rs.DischargeDate,3)),
      "outcome":(rs.Outcome)
    }
    Do rows.%Push(patient)
  }
  Do out.%Set("row_count",rows.%Size())
  Quit out
}

Method SummarizePatients(diagnosis As %String="",diabetic As %String="",smoker As %String="") As %DynamicObject [ WebMethod ]
{
  Set diagnosisPattern=$SELECT(diagnosis="":"%",1:diagnosis_"%")
  Set diabeticFilter=$SELECT(diabetic="":"%",diabetic="Yes":1,diabetic="No":0,1:"invalid")
  Set smokerFilter=$SELECT(smoker="":"%",smoker="Yes":1,smoker="No":0,1:"invalid")
  If diabeticFilter="invalid"!(smokerFilter="invalid") Quit {"error":"diabetic and smoker must be Yes, No, or empty"}
  Set stmt=##class(%SQL.Statement).%New()
  Set sc=stmt.%Prepare("SELECT COUNT(*) AS PatientCount,COALESCE(AVG(Age),0) AS AverageAge,COALESCE(AVG(BMI),0) AS AverageBMI,COALESCE(AVG(TreatmentCost),0) AS AverageTreatmentCost,COALESCE(SUM(TreatmentCost),0) AS TotalTreatmentCost FROM Test_Data.Patient WHERE Diagnosis LIKE ? AND CAST(Diabetic AS VARCHAR) LIKE ? AND CAST(Smoker AS VARCHAR) LIKE ?")
  If $$$ISERR(sc) Quit {"error":($SYSTEM.Status.GetErrorText(sc))}
  Set rs=stmt.%Execute(diagnosisPattern,diabeticFilter,smokerFilter)
  If 'rs.%Next() {
    Set empty={}
    Do empty.%Set("patientCount",0)
    Do empty.%Set("averageAge",0)
    Do empty.%Set("averageBMI",0)
    Do empty.%Set("averageTreatmentCost",0)
    Do empty.%Set("totalTreatmentCost",0)
    Quit empty
  }
  Set out={}
  Do out.%Set("patientCount",rs.PatientCount)
  Do out.%Set("averageAge",rs.AverageAge)
  Do out.%Set("averageBMI",rs.AverageBMI)
  Do out.%Set("averageTreatmentCost",rs.AverageTreatmentCost)
  Do out.%Set("totalTreatmentCost",rs.TotalTreatmentCost)
  Quit out
}

}
