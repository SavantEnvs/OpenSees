# Elastic cantilever, tip load P: v = P L^3 / (3 E I) = 5 * 1000 / (3 * 2.0e4 * 10) = 8.333333e-03
model basic -ndm 2 -ndf 3
node 1 0.0 0.0
node 2 5.0 0.0
node 3 10.0 0.0
fix 1 1 1 1
geomTransf Linear 1
element elasticBeamColumn 1 1 2 1.0 2.0e4 10.0 1
element elasticBeamColumn 2 2 3 1.0 2.0e4 10.0 1
timeSeries Linear 1
pattern Plain 1 1 { load 3 0.0 5.0 0.0 }
constraints Plain; numberer RCM; system ProfileSPD
test NormDispIncr 1.0e-10 10; algorithm Linear
integrator LoadControl 1.0; analysis Static
analyze 1
puts "RESULT [format %.6e [nodeDisp 3 2]]"
