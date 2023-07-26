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
uniform int frameCounter;
uniform int isEyeInWater;
uniform int worldTime;

uniform float blindFactor, darknessFactor, nightVision;
uniform float darknessLightFactor;
uniform float far, near;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float shadowFade;
uniform float timeAngle, timeBrightness;
uniform float viewWidth, viewHeight, aspectRatio;

uniform ivec2 eyeBrightnessSmooth;

uniform vec3 cameraPosition;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

#ifdef LIGHT_SHAFT
uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D noisetex;
#endif

#if REFRACTION > 0
uniform sampler2D colortex6;
#endif

#ifdef MULTICOLORED_BLOCKLIGHT
uniform vec3 previousCameraPosition;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform sampler2D colortex8;
uniform sampler2D colortex9;
#endif

//Optifine Constants//
const bool colortex5Clear = false;

#ifdef MULTICOLORED_BLOCKLIGHT
const bool colortex9Clear = false;
#endif

//Common Variables//
float eBS = eyeBrightnessSmooth.y / 240.0;
float sunVisibility = clamp(dot(sunVec, upVec) + 0.05, 0.0, 0.1) * 10.0;

#ifdef WORLD_TIME_ANIMATION
float frametime = float(worldTime) * 0.05 * ANIMATION_SPEED;
#else
float frametime = frameTimeCounter * ANIMATION_SPEED;
#endif

//Common Functions//
float GetLuminance(vec3 color) {
	return dot(color,vec3(0.299, 0.587, 0.114));
}

float GetLinearDepth(float depth) {
   return (2.0 * near) / (far + near - depth * (far - near));
}

#ifdef MULTICOLORED_BLOCKLIGHT
vec2 Reprojection(vec3 pos) {
	pos = pos * 2.0 - 1.0;

	vec4 viewPosPrev = gbufferProjectionInverse * vec4(pos, 1.0);
	viewPosPrev /= viewPosPrev.w;
	viewPosPrev = gbufferModelViewInverse * viewPosPrev;

	vec3 cameraOffset = cameraPosition - previousCameraPosition;
	cameraOffset *= float(pos.z > 0.56);

	vec4 previousPosition = viewPosPrev + vec4(cameraOffset, 0.0);
	previousPosition = gbufferPreviousModelView * previousPosition;
	previousPosition = gbufferPreviousProjection * previousPosition;
	return previousPosition.xy / previousPosition.w * 0.5 + 0.5;
}

vec2 OffsetDist(float x) {
	float n = fract(x * 8.0) * 6.283;
    return vec2(cos(n), sin(n)) * x * x;
}

vec3 GetMultiColoredBlocklight(vec2 coord, float z, float dither) {
	vec2 prevCoord = Reprojection(vec3(coord, z));
	float lz = GetLinearDepth(z);

	float distScale = clamp((far - near) * lz + near, 4.0, 128.0);
	float fovScale = gbufferProjection[1][1] / 1.37;

	vec2 blurstr = vec2(1.0 / aspectRatio, 1.0) * 2.5 * fovScale / distScale;
	
	vec3 lightAlbedo = texture2D(colortex8, coord).rgb;
	vec3 previousColoredLight = vec3(0.0);

	#ifdef MCBL_ANTI_BLEED
	float linearZ = GetLinearDepth(z);
	#endif

	float mask = clamp(2.0 - 2.0 * max(abs(prevCoord.x - 0.5), abs(prevCoord.y - 0.5)), 0.0, 1.0);

	for(int i = 0; i < 4; i++) {
		vec2 offset = OffsetDist((dither + i) * 0.25) * blurstr;
		offset = floor(offset * vec2(viewWidth, viewHeight) + 0.5) / vec2(viewWidth, viewHeight);

		#ifdef MCBL_ANTI_BLEED
		vec2 sampleZPos = coord + offset;
		float sampleZ0 = texture2D(depthtex0, sampleZPos).r;
		float sampleZ1 = texture2D(depthtex1, sampleZPos).r;
		float linearSampleZ = GetLinearDepth(sampleZ1 >= 1.0 ? sampleZ0 : sampleZ1);

		float sampleWeight = clamp(abs(linearZ - linearSampleZ) * far / 16.0, 0.0, 1.0);
		sampleWeight = 1.0 - sampleWeight * sampleWeight;
		#else
		float sampleWeight = 1.0;
		#endif

		previousColoredLight += texture2D(colortex9, prevCoord.xy + offset).rgb * sampleWeight;
	}

	previousColoredLight *= 0.25;
	previousColoredLight *= previousColoredLight * mask;

	return sqrt(mix(previousColoredLight, lightAlbedo * lightAlbedo / 0.1, 0.1));
}
#endif

//Includes//
#include "/lib/color/dimensionColor.glsl"
#include "/lib/color/skyColor.glsl"
#include "/lib/color/waterColor.glsl"
#include "/lib/util/dither.glsl"
#include "/lib/atmospherics/waterFog.glsl"

#ifdef LIGHT_SHAFT
#include "/lib/atmospherics/volumetricLight.glsl"
#endif

#ifdef OUTLINE_ENABLED
#include "/lib/color/blocklightColor.glsl"
#include "/lib/util/outlineOffset.glsl"
#include "/lib/util/outlineMask.glsl"
#include "/lib/atmospherics/sky.glsl"
#include "/lib/atmospherics/fog.glsl"
#include "/lib/post/outline.glsl"
#endif

//Program//
void main() {
    vec4 color = texture2D(colortex0, texCoord);
    vec3 translucent = texture2D(colortex1,texCoord).rgb;
	float z0 = texture2D(depthtex0, texCoord).r;
	float z1 = texture2D(depthtex1, texCoord).r;

	vec4 screenPos = vec4(texCoord.x, texCoord.y, z0, 1.0);
	vec4 viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
	viewPos /= viewPos.w;

	#if REFRACTION > 0
	if (z1 > z0) {
		vec3 distort = texture2D(colortex6, texCoord).xyz;
		float fovScale = gbufferProjection[1][1] / 1.37;
		distort.xy = distort.xy * 2.0 - 1.0;
		distort.xy *= vec2(1.0 / aspectRatio, 1.0) * fovScale / max(length(viewPos.xyz), 8.0);

		vec2 newCoord = texCoord + distort.xy;
		#if MC_VERSION > 10800
		float distortMask = texture2D(colortex6, newCoord).b * distort.b;
		#else
		float distortMask = texture2DLod(colortex6, newCoord, 0).b * distort.b;
		#endif

		if (distortMask == 1.0 && z0 > 0.56) {
			z0 = texture2D(depthtex0, newCoord).r;
			z1 = texture2D(depthtex1, newCoord).r;
			#if MC_VERSION > 10800
			color.rgb = texture2D(colortex0, newCoord).rgb;
			#else
			color.rgb = texture2DLod(colortex0, newCoord, 0).rgb;
			#endif
		}

		screenPos = vec4(newCoord.x, newCoord.y, z0, 1.0);
		viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
		viewPos /= viewPos.w;
	}
	#endif
	
	#if ALPHA_BLEND == 0
	color.rgb *= color.rgb;
	#endif
	
	#ifdef OUTLINE_ENABLED
	vec4 outerOutline = vec4(0.0), innerOutline = vec4(0.0);
	float outlineMask = GetOutlineMask();
	if (outlineMask > 0.5 || isEyeInWater > 0.5)
		Outline(color.rgb, true, outerOutline, innerOutline);

	if(z1 > z0) {
		float worldDistance = length(viewPos.xyz) / far;
		float distantFade = 1.0 - smoothstep(0.6, 1.1, worldDistance);
		innerOutline.a *= distantFade;
		
		color.rgb = mix(color.rgb, innerOutline.rgb, innerOutline.a);
	}
	#endif

	if (isEyeInWater == 1.0) {
		vec4 waterFog = GetWaterFog(viewPos.xyz);
		waterFog.a = mix(waterAlpha * 0.5, 1.0, waterFog.a);
		color.rgb = mix(sqrt(color.rgb), sqrt(waterFog.rgb), waterFog.a);
		color.rgb *= color.rgb;
	}

	#ifdef OUTLINE_ENABLED
	color.rgb = mix(color.rgb, outerOutline.rgb, outerOutline.a);
	#endif
	
	#ifdef LIGHT_SHAFT
	float blueNoise = texture2D(noisetex, gl_FragCoord.xy/512.0).b;
	vec3 vl = GetLightShafts(z0, z1, translucent, blueNoise);
	#else
	vec3 vl = vec3(0.0);
    #endif

	color.rgb *= clamp(1.0 - 2.0 * darknessLightFactor, 0.0, 1.0);

	vec3 reflectionColor = pow(color.rgb, vec3(0.125)) * 0.5;

	#ifdef MULTICOLORED_BLOCKLIGHT
	float dither = Bayer8(gl_FragCoord.xy);
	float lightZ = z1 >= 1.0 ? z0 : z1;
	vec3 coloredLight = GetMultiColoredBlocklight(texCoord, lightZ, dither);
	#endif
	
    /*DRAWBUFFERS:01*/
	gl_FragData[0] = color;
	gl_FragData[1] = vec4(vl, 1.0);

	#ifdef MULTICOLORED_BLOCKLIGHT
		/*DRAWBUFFERS:019*/
		gl_FragData[2] = vec4(coloredLight, 1.0);
	
		#ifdef REFLECTION_PREVIOUS
		/*DRAWBUFFERS:0195*/
		gl_FragData[3] = vec4(reflectionColor, float(z0 < 1.0));
		#endif
	#else
		#ifdef REFLECTION_PREVIOUS
		/*DRAWBUFFERS:015*/
		gl_FragData[2] = vec4(reflectionColor, float(z0 < 1.0));
		#endif
	#endif
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
