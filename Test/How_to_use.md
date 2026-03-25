## This is a using guidance (developing)

### **Test.jl**
This is the main document including model and optimizer.
After running this file the result will be stored in *"result01.csv"*.
Each running will cover previous result.

Now the variables are all hardcode.

### **Initialise.jl**
Including data handling and Demand, Wind, Solar 7 days trace generation.
Can interactive with *"config.json"*.
Mapping Generators to Bus, finding traces from Bus names then.
Will assign all variables into *"Test.jl"*

### **config.json**
Configuration file include start days and which kind of traces model uses.
