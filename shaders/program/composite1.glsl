/* 
BSL Shaders v8 Series by Capt Tatsu 
https://bitslablab.com 
*/ 

//Settings//
#include "/lib/settings.glsl"

//Fragment Shader///////////////////////////////////////////////////////////////////////////////////
#ifdef FSH

//Varyings//
varying vec2 texCoord;

varying vec3 sunVec, upVec;

//Uniforms//
uniform int isEyeInWater;
uniform int worldTime;

uniform float blindFactor, darknessFactor;
uniform float rainStrength;
uniform float shadowFade, voidFade;
uniform float timeAngle, timeBrightness;
uniform float viewWidth, viewHeight;

uniform ivec2 eyeBrightnessSmooth;

uniform sampler2D colortex0;
uniform sampler2D colortex1;

//Common Variables//
float eBS = eyeBrightnessSmooth.y / 240.0;
float sunVisibility = clamp(dot(sunVec, upVec) + 0.05, 0.0, 0.1) * 10.0;

vec2 vlOffsets[4] = vec2[4](
	vec2( 1.5,  0.5),
	vec2(-0.5,  1.5),
	vec2(-1.5, -0.5),
	vec2( 0.5, -1.5)
);

//Includes//
#include "/lib/color/dimensionColor.glsl"

//Program//
void main() {
    vec4 color = texture2D(colortex0, texCoord.xy);
	
	vec3 vl = texture2D(colortex1, texCoord.xy + vlOffsets[0] / vec2(viewWidth, viewHeight)).rgb;
		 vl+= texture2D(colortex1, texCoord.xy + vlOffsets[1] / vec2(viewWidth, viewHeight)).rgb;
		 vl+= texture2D(colortex1, texCoord.xy + vlOffsets[2] / vec2(viewWidth, viewHeight)).rgb;
		 vl+= texture2D(colortex1, texCoord.xy + vlOffsets[3] / vec2(viewWidth, viewHeight)).rgb;
		 vl*= vl * 0.0625;

	#ifdef OVERWORLD
    vl *= lightCol * 0.25;
	#endif

	#ifdef END
    vl *= endCol.rgb * 0.1;
	#endif

    vl *= LIGHT_SHAFT_STRENGTH * (1.0 - rainStrength * eBS * 0.875) * shadowFade *
		  (1.0 - max(blindFactor, darknessFactor));
	
	color.rgb += vl;
	
	/*DRAWBUFFERS:0*/
	gl_FragData[0] = color;
}

#endif

//Vertex Shader/////////////////////////////////////////////////////////////////////////////////////
#ifdef VSH

//Varyings//
varying vec2 texCoord;

varying vec3 sunVec, upVec;

//Uniforms//
uniform float timeAngle;

uniform mat4 gbufferModelView;

//Program//
void main() {
	texCoord = gl_MultiTexCoord0.xy;
	
	gl_Position = ftransform();

	const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
	float ang = fract(timeAngle - 0.25);
	ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
	sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

	upVec = normalize(gbufferModelView[1].xyz);
}

#endif