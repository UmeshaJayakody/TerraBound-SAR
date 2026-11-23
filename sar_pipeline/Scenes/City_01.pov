#version 3.5;

#include "colors.inc"
#include "finish.inc"

global_settings{SAR_Output_Data 1 SAR_Intersection 0}

// Auto-generated box-city scene (Make_Box_City_Scene.m)

#declare Cam = camera {
  orthographic
  location <0,80,-80>
  look_at <0,0,0>
  right 100*x
  up 100*y
}

camera{Cam}

light_source {
  <0,80,-80>
  color rgb <1,1,1>
  parallel
  point_at <0,0,0>
}

plane {
  <0,1,0>
  0
  pigment {color White}
  finish {reflection {0.5} ambient 0 diffuse 0.1 specular 0}
}

box{
  <-9,0,-9>
  <9,25,9>
  translate <-30,0,10>
  pigment {color White}
  finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

box{
  <-10,0,-7.5>
  <10,40,7.5>
  translate <0,0,0>
  pigment {color White}
  finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

box{
  <-8,0,-8>
  <8,20,8>
  translate <30,0,15>
  pigment {color White}
  finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

box{
  <-7,0,-7>
  <7,15,7>
  translate <-15,0,-20>
  pigment {color White}
  finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

box{
  <-9,0,-9>
  <9,30,9>
  translate <20,0,-15>
  pigment {color White}
  finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}
}

