#ifdef OVERWORLD
float CloudSampleBase(vec2 coord, vec2 wind, float cloudGradient, float sunCoverage, float dither, float multiplier) {
	coord.xy *= 0.004;

	#if CLOUD_BASE == 0
	float noiseBase = texture2D(noisetex, coord * 0.25 + wind).r;
	#else
	float noiseBase = texture2D(noisetex, coord * 0.5 + wind).g;
	noiseBase = pow(1.0 - noiseBase, 2.0) * 0.5 + 0.25;
	#endif

	float detailZ = floor(cloudGradient * float(CLOUD_THICKNESS)) * 0.04;
	float noiseDetailLow = texture2D(noisetex, coord.xy * 0.5 - wind * 2.0 + detailZ).b;
	float noiseDetailHigh = texture2D(noisetex, coord.xy * 0.5 - wind * 2.0 + detailZ + 0.04).b;
	float noiseDetail = mix(noiseDetailLow, noiseDetailHigh, fract(cloudGradient * float(CLOUD_THICKNESS)));

	float noiseCoverage = abs(cloudGradient - 0.125);
	noiseCoverage *= cloudGradient > 0.125 ? (2.14 - CLOUD_AMOUNT * 0.1) : 8.0;
	noiseCoverage = noiseCoverage * noiseCoverage * 4.0;
	
	float noise = mix(noiseBase, noiseDetail, 0.0476 * CLOUD_DETAIL) * 21.0 - noiseCoverage;
	noise = mix(noise, 21.0, 0.33 * rainStrength);
		
	noise = max(noise - (sunCoverage * 3.0 + CLOUD_AMOUNT), 0.0);
	noise *= CLOUD_DENSITY * multiplier;
	noise *= (1.0 - 0.75 * rainStrength);
	noise = noise / sqrt(noise * noise + 0.5);

	return noise;
}

float CloudSampleSkybox(vec2 coord, vec2 wind, float cloudGradient, float sunCoverage, float dither) {
	return CloudSampleBase(coord, wind, cloudGradient, sunCoverage, dither, 0.125);
}

float CloudSampleVolumetric(vec2 coord, vec2 wind, float cloudGradient, float sunCoverage, float dither) {
	coord.xy /= CLOUD_VOLUMETRIC_SCALE;
	return CloudSampleBase(coord, wind, cloudGradient, sunCoverage, dither, 0.2);
}

float InvLerp(float v, float l, float h) {
	return clamp((v - l) / (h - l), 0.0, 1.0);
}

vec4 DrawCloudSkybox(vec3 viewPos, float z, float dither, vec3 lightCol, vec3 ambientCol, bool fadeFaster) {
	if (z < 1.0) return vec4(0.0);

	#ifdef TAA
	dither = fract(dither + frameCounter * 0.618);
	#endif

	int samples = CLOUD_THICKNESS * 2;
	
	float cloud = 0.0, cloudLighting = 0.0;

	float sampleStep = 1.0 / samples;
	float currentStep = dither * sampleStep;
	
	vec3 nViewPos = normalize(viewPos);
	float VoU = dot(nViewPos, upVec);
	float VoL = dot(nViewPos, lightVec);
	
	float sunCoverage = pow(clamp(abs(VoL) * 2.0 - 1.0, 0.0, 1.0), 12.0) * (1.0 - rainStrength);

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.0005,
		sin(frametime * CLOUD_SPEED * 0.001) * 0.005
	) * CLOUD_HEIGHT / 15.0;

	vec3 cloudColor = vec3(0.0);

	if (VoU > 0.025) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);

		float halfVoL = VoL * shadowFade * 0.5 + 0.5;
		float halfVoLSqr = halfVoL * halfVoL;
		float scattering = pow(halfVoL, 6.0);
		float noiseLightFactor = (2.0 - 1.5 * VoL * shadowFade) * CLOUD_DENSITY * 0.5;

		for(int i = 0; i < samples; i++) {
			if (cloud > 0.99) break;
			vec3 planeCoord = wpos * ((CLOUD_HEIGHT + currentStep * CLOUD_THICKNESS) / wpos.y);
			vec2 coord = cameraPosition.xz * 0.0625 + planeCoord.xz;

			float noise = CloudSampleSkybox(coord, wind, currentStep, sunCoverage, dither);

			float sampleLighting = pow(currentStep, 1.125 * halfVoLSqr + 0.875) * 0.8 + 0.2;
			sampleLighting *= 1.0 - pow(noise, noiseLightFactor);

			cloudLighting = mix(cloudLighting, sampleLighting, noise * (1.0 - cloud * cloud));
			cloud = mix(cloud, 1.0, noise);

			currentStep += sampleStep;
		}
		cloudLighting = mix(cloudLighting, 1.0, (1.0 - cloud * cloud) * scattering * 0.5);
		cloudColor = mix(
			ambientCol * (0.35 * sunVisibility + 0.5),
			lightCol * (0.85 + 1.15 * scattering),
			cloudLighting
		);
		cloudColor *= 1.0 - 0.6 * rainStrength;
		// cloudColor = vec3(cloudLighting);

		cloud *= clamp(1.0 - exp(-16.0 / max(FOG_DENSITY, 0.5) * VoU + 0.5), 0.0, 1.0);
		cloud *= 1.0 - 0.6 * rainStrength;

		if (fadeFaster) {
			cloud *= 1.0 - pow(1.0 - VoU, 4.0);
		}
	}
	cloudColor *= CLOUD_BRIGHTNESS * (0.5 - 0.25 * (1.0 - sunVisibility) * (1.0 - rainStrength));
	// cloudColor *= voidFade;
	#if MC_VERSION >= 11800
	cloudColor *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	cloudColor *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif
	
	#ifdef UNDERGROUND_SKY
	cloud *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
	#endif
	
	return vec4(cloudColor, cloud * cloud * CLOUD_OPACITY);
}

vec3 GetReflectedCameraPos(vec3 worldPos, vec3 normal) {
	vec4 worldNormal = gbufferModelViewInverse * vec4(normal, 1.0);
	worldNormal.xyz /= worldNormal.w;

	vec3 cameraPos = cameraPosition + 2.0 * worldNormal.xyz * dot(worldPos, worldNormal.xyz);
	cameraPos = cameraPos + reflect(worldPos, worldNormal.xyz); //bobbing stabilizer, works like magic

	return cameraPos;
}

vec4 DrawCloudVolumetric(vec3 viewPos, vec3 cameraPos, float z, float dither, vec3 lightCol, vec3 ambientCol, inout float closestLength, bool fadeFaster) {
	#ifdef TAA
	dither = fract(dither + frameCounter * 0.618);
	#endif

	vec3 nViewPos = normalize(viewPos);
	vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 nWorldPos = normalize(worldPos);
	float viewLength = length(viewPos);

	float cloudHeight = CLOUD_HEIGHT * CLOUD_VOLUMETRIC_SCALE + 70;
	// float cloudHeight = CLOUD_HEIGHT * CLOUD_VOLUMETRIC_SCALE + cameraPosition.y;
	// float cloudHeight = 63;

	float lowerY = cloudHeight;
	float upperY = cloudHeight + CLOUD_THICKNESS * CLOUD_VOLUMETRIC_SCALE;

	float lowerPlane = (lowerY - cameraPos.y) / nWorldPos.y;
	float upperPlane = (upperY - cameraPos.y) / nWorldPos.y;

	float nearestPlane = max(min(lowerPlane, upperPlane), 0.0);
	float furthestPlane = max(lowerPlane, upperPlane);

	float maxClosestLength = closestLength;
	float closestLengthThreshold = 0.5 * dither + 0.35;

	if (furthestPlane < 0) return vec4(0.0);

	float planeDifference = furthestPlane - nearestPlane;

	vec3 startPos = cameraPos + nearestPlane * nWorldPos;

	float sampleLength = CLOUD_THICKNESS * CLOUD_VOLUMETRIC_SCALE / 2.0;
	sampleLength /= (3.0 * nWorldPos.y * nWorldPos.y) + 1.0;
	vec3 sampleStep = nWorldPos * sampleLength;
	int samples = int(min(planeDifference / sampleLength, 32) + 1 + dither);

	vec3 samplePos = startPos + sampleStep * dither;
	float sampleTotalLength = nearestPlane + sampleLength * dither;

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.0005,
		sin(frametime * CLOUD_SPEED * 0.001) * 0.005
	) * CLOUD_HEIGHT / 15.0;

	float cloud = 0.0;
	float cloudFaded = 0.0;
	float cloudLighting = 0.0;

	float VoU = dot(nViewPos, upVec);
	float VoL = dot(nViewPos, lightVec);

	float sunCoverage = mix(abs(VoL), max(VoL, 0.0), shadowFade);
	sunCoverage = pow(clamp(sunCoverage * 2.0 - 1.0, 0.0, 1.0), 12.0) * (1.0 - rainStrength);

	float halfVoL = VoL * shadowFade * 0.5 + 0.5;
	float halfVoLSqr = halfVoL * halfVoL;

	float scattering = pow(halfVoL, 6.0);
	float noiseLightFactor = (2.0 - 1.5 * VoL * shadowFade) * CLOUD_DENSITY * 1.0;

	float viewLengthSoftMin = viewLength - sampleLength;
	float viewLengthSoftMax = viewLength + sampleLength;

	for (int i = 0; i < samples; i++) {
		if (cloudFaded > 0.99) break;
		if (sampleTotalLength > viewLengthSoftMax && z < 1.0) break;

		float cloudGradient = InvLerp(samplePos.y, lowerY, upperY);
		float xzNormalizedDistance = length(samplePos.xz - cameraPos.xz) / CLOUD_VOLUMETRIC_SCALE;

		float noise = CloudSampleVolumetric(samplePos.xz, wind, cloudGradient, sunCoverage, dither);

		float sampleLighting = pow(cloudGradient, 1.125 * halfVoLSqr + 0.875) * 0.8 + 0.2;
		sampleLighting *= 1.0 - pow(noise, noiseLightFactor);

		cloudLighting = mix(cloudLighting, sampleLighting, noise * (1.0 - cloud * cloud));
		cloud = mix(cloud, 1.0, noise);

		noise *= pow(InvLerp(xzNormalizedDistance, 512.0, 32.0), 12.0);
		if (z < 1.0) {
			noise *= InvLerp(sampleTotalLength, viewLengthSoftMax, viewLengthSoftMin);
		}

		if (closestLength == maxClosestLength && noise > closestLengthThreshold) {
			closestLength = sampleTotalLength;
		}

		cloudFaded = mix(cloudFaded, 1.0, noise);
		
		samplePos += sampleStep;
		sampleTotalLength += sampleLength;
	}
	cloudLighting = mix(cloudLighting, 1.0, (1.0 - cloud * cloud) * scattering * 0.5);
	
	vec3 cloudColor = mix(
		ambientCol * (0.35 * sunVisibility + 0.5),
		lightCol * (0.85 + 1.15 * scattering),
		cloudLighting
	);
	cloudColor *= 1.0 - 0.6 * rainStrength;
	cloudColor *= CLOUD_BRIGHTNESS * (0.5 - 0.25 * (1.0 - sunVisibility) * (1.0 - rainStrength));

	cloudFaded *= 1.0 - 0.6 * rainStrength;
	cloudFaded *= cloudFaded * CLOUD_OPACITY;

	return vec4(cloudColor, cloudFaded);
}

float GetNoise(vec2 pos) {
	return fract(sin(dot(pos, vec2(12.9898, 4.1414))) * 43758.5453);
}

void DrawStars(inout vec3 color, vec3 viewPos) {
	vec3 wpos = vec3(gbufferModelViewInverse * vec4(viewPos, 1.0));
	vec3 planeCoord = wpos / (wpos.y + length(wpos.xz));
	vec2 wind = vec2(frametime, 0.0);
	vec2 coord = planeCoord.xz * 0.4 + cameraPosition.xz * 0.0001 + wind * 0.00125;
	coord = floor(coord * 1024.0) / 1024.0;
	
	float VoU = clamp(dot(normalize(viewPos), upVec), 0.0, 1.0);
	float multiplier = sqrt(sqrt(VoU)) * 5.0 * (1.0 - rainStrength) * moonVisibility;
	
	float star = 1.0;
	if (VoU > 0.0) {
		star *= GetNoise(coord.xy);
		star *= GetNoise(coord.xy + 0.10);
		star *= GetNoise(coord.xy + 0.23);
	}
	star = clamp(star - 0.8125, 0.0, 1.0) * multiplier;
	//star *= voidFade;
	#if MC_VERSION >= 11800
	star *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	star *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif

	#ifdef UNDERGROUND_SKY
	star *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
	#endif
		
	color += star * pow(lightNight, vec3(0.8));
}

#ifdef AURORA
#include "/lib/color/auroraColor.glsl"

float AuroraSample(vec2 coord, vec2 wind, float VoU) {
	float noise = texture2D(noisetex, coord * 0.0625  + wind * 0.25).b * 3.0;
		  noise+= texture2D(noisetex, coord * 0.03125 + wind * 0.15).b * 3.0;

	noise = max(1.0 - 4.0 * (0.5 * VoU + 0.5) * abs(noise - 3.0), 0.0);

	return noise;
}

vec3 DrawAurora(vec3 viewPos, float dither, int samples) {
	#ifdef TAA
	dither = fract(dither + frameCounter * 0.618);
	#endif
	
	float sampleStep = 1.0 / samples;
	float currentStep = dither * sampleStep;

	float VoU = dot(normalize(viewPos), upVec);

	float visibility = moonVisibility * (1.0 - rainStrength) * (1.0 - rainStrength);

	#ifdef WEATHER_PERBIOME
	visibility *= isCold * isCold;
	#endif

	vec2 wind = vec2(
		frametime * CLOUD_SPEED * 0.000125,
		sin(frametime * CLOUD_SPEED * 0.05) * 0.00025
	);

	vec3 aurora = vec3(0.0);

	if (VoU > 0.0 && visibility > 0.0) {
		vec3 wpos = normalize((gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz);
		for(int i = 0; i < samples; i++) {
			vec3 planeCoord = wpos * ((8.0 + currentStep * 7.0) / wpos.y) * 0.004;

			vec2 coord = cameraPosition.xz * 0.00004 + planeCoord.xz;
			coord += vec2(coord.y, -coord.x) * 0.3;

			float noise = AuroraSample(coord, wind, VoU);
			
			if (noise > 0.0) {
				noise *= texture2D(noisetex, coord * 0.125 + wind * 0.25).b;
				noise *= 0.5 * texture2D(noisetex, coord + wind * 16.0).b + 0.75;
				noise = noise * noise * 3.0 * sampleStep;
				noise *= max(sqrt(1.0 - length(planeCoord.xz) * 3.75), 0.0);

				vec3 auroraColor = mix(auroraLowCol, auroraHighCol, pow(currentStep, 0.4));
				aurora += noise * auroraColor * exp2(-6.0 * i * sampleStep);
			}
			currentStep += sampleStep;
		}
	}
	// visibility *= voidFade;
	#if MC_VERSION >= 11800
	visibility *= clamp((cameraPosition.y + 70.0) / 8.0, 0.0, 1.0);
	#else
	visibility *= clamp((cameraPosition.y + 6.0) / 8.0, 0.0, 1.0);
	#endif

	#ifdef UNDERGROUND_SKY
	visibility *= mix(clamp((cameraPosition.y - 48.0) / 16.0, 0.0, 1.0), 1.0, eBS);
	#endif

	return aurora * visibility;
}
#endif
#endif