Class Test.Skill.CalculationReview Extends %AI.Agent.Skill
{
XData SUMMARY [ MimeType="text/yaml" ]
{
name: calculation-review
description: Perform and verify a small calculation using an available tool.
parameters:
  - name: request
    description: Calculation requested by the user
    type: string
    required: true
tags:
  - arithmetic
  - verification
  - tutorial
}

XData INSTRUCTIONS [ MimeType="text/markdown" ]
{
Use an available calculation tool instead of calculating mentally. Report the operands, operation, and tool result. Check the result once using the inverse operation. Keep the answer short and never claim a tool was used unless it was executed.
}
}
