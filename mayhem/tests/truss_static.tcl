# Elastic truss under an axial tip load: u = P L / (E A) = 10 * 2 / (1000 * 0.5) = 0.04
model basic -ndm 2 -ndf 2
node 1 0.0 0.0
node 2 2.0 0.0
fix 1 1 1
fix 2 0 1
uniaxialMaterial Elastic 1 1000.0
element truss 1 1 2 0.5 1
timeSeries Linear 1
pattern Plain 1 1 { load 2 10.0 0.0 }
constraints Plain; numberer Plain; system BandGeneral
test NormDispIncr 1.0e-10 10; algorithm Newton
integrator LoadControl 1.0; analysis Static
analyze 1
puts "RESULT [format %.6e [nodeDisp 2 1]]"
