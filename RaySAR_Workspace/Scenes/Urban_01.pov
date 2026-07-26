#version 3.5;

#include "colors.inc"
#include "finish.inc"

global_settings{SAR_Output_Data 1 SAR_Intersection 0}

// Auto-generated urban scene (Make_Urban_Scene.m, seed=7)

#declare Cam = camera {
  orthographic
  location <0,180,-180>
  look_at <0,0,0>
  right 180*x
  up 180*y
}

camera{Cam}

light_source {
  <0,180,-180>
  color rgb <1,1,1>
  parallel
  point_at <0,0,0>
}

plane {
  <0,1,0>
  0
  pigment {color White}
  finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}
}

// Streets
box{<-70,0,-55.5> <70,0.02,-49.5> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<-70,0,-20.5> <70,0.02,-14.5> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<-70,0,14.5> <70,0.02,20.5> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<-70,0,49.5> <70,0.02,55.5> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<-55.5,0,-70> <-49.5,0.02,70> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<-20.5,0,-70> <-14.5,0.02,70> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<14.5,0,-70> <20.5,0.02,70> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}
box{<49.5,0,-70> <55.5,0.02,70> pigment{color Gray30} finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}}

// Buildings
union{
  box{<-8.19205,0,-9.61733> <8.19205,44.2296,9.61733>}
  rotate <0,2.69471,0>
  translate <-56.2073,0,-50.0507>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-8.49941,0,-9.39615> <8.49941,38.1309,9.39615>}
  box{<-16.4988,0,8.89615> <-7.99941,27.2734,18.2923>}
  rotate <0,-8.33412,0>
  translate <-21.2446,0,-54.5262>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-10.656,0,-6.1245> <10.656,31.0192,6.1245>}
  box{<-20.8121,0,5.6245> <-10.156,25.417,11.749>}
  rotate <0,31.5091,0>
  translate <14.9921,0,-52.9189>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-9.75205,0,-9.34507> <9.75205,26.3714,9.34507>}
  rotate <0,-20.6606,0>
  translate <49.2902,0,-52.2951>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-7.82945,0,-10.1896> <7.82945,36.9027,10.1896>}
  rotate <0,-13.0204,0>
  translate <-53.6166,0,-17.6977>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-7.76489,0,-9.287> <7.76489,22.9623,9.287>}
  rotate <0,-2.86349,0>
  translate <-19.4596,0,-17.9126>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-6.90226,0,-9.70559> <6.90226,24.7831,9.70559>}
  rotate <0,-5.14825,0>
  translate <16.7387,0,-13.9438>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-6.00713,0,-6.46131> <6.00713,34.8288,6.46131>}
  rotate <0,1.70419,0>
  translate <52.7004,0,-18.2447>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-6.26564,0,-7.54426> <6.26564,30.7408,7.54426>}
  rotate <0,-18.5416,0>
  translate <-48.5147,0,19.1005>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-8.36162,0,-10.2074> <8.36162,14.5889,10.2074>}
  rotate <0,-13.3886,0>
  translate <-13.6058,0,20.5485>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-6.68438,0,-7.71768> <6.68438,21.3549,7.71768>}
  box{<6.18438,0,7.21768> <12.8688,16.357,14.9354>}
  rotate <0,-13.9707,0>
  translate <19.6162,0,17.376>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-8.61195,0,-8.30315> <8.61195,37.2375,8.30315>}
  rotate <0,27.1102,0>
  translate <54.9054,0,20.0934>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-6.20328,0,-10.3784> <6.20328,19.6797,10.3784>}
  rotate <0,-1.69649,0>
  translate <-49.8708,0,56.3422>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-9.29374,0,-6.34626> <9.29374,22.4975,6.34626>}
  rotate <0,21.8981,0>
  translate <-15.5991,0,49.4125>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-10.1061,0,-9.80258> <10.1061,10.25,9.80258>}
  rotate <0,-5.58202,0>
  translate <18.3737,0,54.4964>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

union{
  box{<-9.03885,0,-10.1423> <9.03885,42.9633,10.1423>}
  box{<8.53885,0,-19.7845> <17.5777,37.1058,-9.64227>}
  rotate <0,-26.0297,0>
  translate <48.6106,0,52.8626>
  pigment {color White} finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

// Cars
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,92.8223,0> translate<-38.629,0,-52.2005> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,2.96951,0> translate<49.9766,0,-54.3653> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,93.767,0> translate<66.5196,0,-53.403> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,92.1923,0> translate<57.2855,0,-18.7099> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,3.07835,0> translate<48.3483,0,-18.8269> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,87.8153,0> translate<6.95998,0,-18.8411> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,88.6162,0> translate<43.1019,0,15.6791> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,90.2472,0> translate<-61.0929,0,16.0979> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,88.3136,0> translate<27.5374,0,17.2082> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,-2.58397,0> translate<12.6484,0,54.2626> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,-0.413965,0> translate<-68.5188,0,53.8226> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
box{<-0.9,0,-2.1> <0.9,1.5,2.1> rotate<0,3.72627,0> translate<38.0019,0,53.9648> pigment{color White} finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}}
