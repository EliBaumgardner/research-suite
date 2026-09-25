### How to Systematically Solve Problems 
**These are negotiable principles for solving problems in the project but generally should always be adhered to**

- Verify that you have fully applied of these principles after applying them
- Carefully analyze the entire API the code affects
- Closely observe the structure of the API the code affects
- Understand the data flow of the relevant API section
- Verify that the relevant code follows all rules in the Key Design Rules section
- Verify that the relevant code does not change behavior unexpectantly, or introduce new bugs
- Analyze the broader API the smaller section of the API affects (a class is composed in another class, both should be understood)
- Closely observe the general design of the broader API and verify the relevant code follows it fully
- Reapply the same principles from the second step to the broader API and repeat
