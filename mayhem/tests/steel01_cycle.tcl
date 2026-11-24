# Steel01 (fy=50, E0=1000, b=0.1) tested at strain 0.1 (beyond yield strain 0.05):
# stress = fy + b*E0*(eps - fy/E0) = 50 + 100*(0.1-0.05) = 55
model testUniaxial
uniaxialMaterial Steel01 1 50.0 1000.0 0.1
uniaxialTest 1
foreach e {0.02 0.05 0.08 0.1} { strainUniaxialTest $e }
puts "RESULT [format %.6e [stressUniaxialTest]]"
