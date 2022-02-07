#ifdef OVERWORLD
vec3 GetFogColor(vec3 viewPos) {
	vec3 nViewPos = normalize(viewPos);
	float lViewPos = length(viewPos) / 64.0;
	lViewPos = 1.0 - exp(-lViewPos * lViewPos);

    float VoU = clamp(dot(nViewPos,  upVec), -1.0, 1.0);
    float VoL = clamp(dot(nViewPos, sunVec), -1.0, 1.0);

	float density = 0.4;
    float nightDensity = 0.65;
    float weatherDensity = 1.5;
    float groundDensity = 0.08 * (4.0 - 3.0 * sunVisibility) *
                          (10.0 * rainStrength * rainStrength + 1.0);
    
    float exposure = exp2(timeBrightness * 0.75 - 1.00);
    float nightExposure = exp2(-3.5);

	float baseGradient = exp(-(VoU * 0.5 + 0.5) * 0.5 / density);

	float groundVoU = clamp(-VoU * 0.5 + 0.5, 0.0, 1.0);
    float ground = 1.0 - exp(-groundDensity / groundVoU);

    vec3 fog = fogCol * baseGradient / (SKY_I * SKY_I);
    fog = fog / sqrt(fog * fog + 1.0) * exposure * sunVisibility * (SKY_I * SKY_I);

	float sunMix = (VoL * 0.5 + 0.5) * pow(clamp(1.0 - VoU, 0.0, 1.0), 2.0 - sunVisibility) *
                   pow(1.0 - timeBrightness * 0.6, 3.0);
    float horizonMix = pow(1.0 - abs(VoU), 2.5) * 0.125 * (1.0 - timeBrightness * 0.5);
    float lightMix = (1.0 - (1.0 - sunMix) * (1.0 - horizonMix)) * lViewPos;

	vec3 lightFog = pow(lightSun, vec3(4.0 - sunVisibility)) * baseGradient;
	lightFog = lightFog / (1.0 + lightFog * rainStrength);

    fog = mix(
        sqrt(fog * (1.0 - lightMix)), 
        sqrt(lightFog), 
        lightMix
    );
    fog *= fog;

	float nightGradient = exp(-(VoU * 0.5 + 0.5) * 0.35 / nightDensity);
    vec3 nightFog = lightNight * lightNight * nightGradient * nightExposure;
    fog = mix(nightFog, fog, sunVisibility * sunVisibility);

    float rainGradient = exp(-(VoU * 0.5 + 0.5) * 0.125 / weatherDensity);
    vec3 weatherFog = weatherCol.rgb * weatherCol.rgb;
    weatherFog *= GetLuminance(ambientCol / (weatherFog)) * (0.2 * sunVisibility + 0.2);
    fog = mix(fog, weatherFog * rainGradient, rainStrength);
	fog = mix(minLightCol * 0.5, fog * eBS, eBS);

    //fog *= voidFade;
	#if MC_VERSION >= 11800
	fog *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	fog *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif

	return fog;
}
#endif

void NormalFog(inout vec3 color, vec3 viewPos) {
	#if DISTANT_FADE > 0
	#if DISTANT_FADE_STYLE == 0
	float fogFactor = length(viewPos);
	#else
	vec4 worldPos = gbufferModelViewInverse * vec4(viewPos, 1.0);
	worldPos.xyz /= worldPos.w;
	float fogFactor = length(worldPos.xz);
	#endif
	#endif
	
	#ifdef OVERWORLD
	float fog = length(viewPos) * FOG_DENSITY / 256.0;
	float clearDay = sunVisibility * (1.0 - rainStrength);
	fog *= mix(1.0, (0.5 * rainStrength + 1.0) / (4.0 * clearDay + 1.0) * eBS, eBS);
	fog = 1.0 - exp(-2.0 * pow(fog, 0.15 * clearDay * eBS + 1.25));
	vec3 fogColor = GetFogColor(viewPos);

	#if DISTANT_FADE == 1 || DISTANT_FADE == 3
	if(isEyeInWater == 0.0){
		#if MC_VERSION >= 11800
		float fogOffset = 0.0;
		#else
		float fogOffset = 12.0;
		#endif
		float vanillaFog = 1.0 - (far - (fogFactor + fogOffset)) * 5.0 / (FOG_DENSITY * far);
		vanillaFog = clamp(vanillaFog, 0.0, 1.0);
	
		if(vanillaFog > 0.0){
			vec3 vanillaFogColor = GetSkyColor(viewPos, false);
			vanillaFogColor *= (4.0 - 3.0 * eBS) * (1.0 + nightVision);

			fogColor *= fog;
			
			fog = mix(fog, 1.0, vanillaFog);
			if(fog > 0.0) fogColor = mix(fogColor, vanillaFogColor, vanillaFog) / fog;
		}
	}
	#endif
	#endif

	#ifdef NETHER
	float viewLength = length(viewPos);
	float fog = 2.0 * pow(viewLength * FOG_DENSITY / 256.0, 1.5);
	#if DISTANT_FADE == 2 || DISTANT_FADE == 3
	fog += 6.0 * pow(fogFactor * 1.5 / far, 4.0);
	#endif
	fog = 1.0 - exp(-fog);
	vec3 fogColor = netherCol.rgb * 0.04;
	#endif

	#ifdef END
	float fog = length(viewPos) * FOG_DENSITY / 128.0;
	#if DISTANT_FADE == 2 || DISTANT_FADE == 3
	fog += 6.0 * pow(fogFactor * 1 / far, 6.0);
	#endif
	fog = 1.0 - exp(-0.8 * fog * fog);
	vec3 fogColor = endCol.rgb * 0.00625;
	#ifndef LIGHT_SHAFT
	fogColor *= 2.5;
	#endif
	#endif

	color = mix(color, fogColor, fog);
}

void BlindFog(inout vec3 color, vec3 viewPos) {
	float fog = length(viewPos) * (blindFactor * 0.2);
	fog = (1.0 - exp(-6.0 * fog * fog * fog)) * blindFactor;
	color = mix(color, vec3(0.0), fog);
}

vec3 denseFogColor[2] = vec3[2](
	vec3(1.0, 0.3, 0.01),
	vec3(0.1, 0.16, 0.2)
);

void DenseFog(inout vec3 color, vec3 viewPos) {
	float fog = length(viewPos) * 0.5;
	fog = (1.0 - exp(-4.0 * fog * fog * fog));
	color = mix(color, denseFogColor[isEyeInWater - 2], fog);
}

void Fog(inout vec3 color, vec3 viewPos) {
	NormalFog(color, viewPos);
	if (isEyeInWater > 1) DenseFog(color, viewPos);
	if (blindFactor > 0.0) BlindFog(color, viewPos);
}