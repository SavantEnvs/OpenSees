# Spring-mass SDOF: omega^2 = k / m = 400 / 4 = 100
model basic -ndm 1 -ndf 1
node 1 0.0
node 2 0.0 -mass 4.0
fix 1 1
uniaxialMaterial Elastic 1 400.0
element zeroLength 1 1 2 -mat 1 -dir 1
puts "RESULT [format %.6e [lindex [eigen -fullGenLapack 1] 0]]"
