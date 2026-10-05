module

public import RealWorldTests.Unit

public section

def main : IO UInt32 := RealWorldTests.run RealWorldTests.unitSuites
