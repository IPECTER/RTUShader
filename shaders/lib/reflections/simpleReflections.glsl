vec4 SimpleReflection(vec3 viewPos, vec3 normal, float dither) {
    vec4 color = vec4(0.0);
	float border = 0.0;

    vec4 pos = Raytrace(depthtex1, viewPos, normal, dither, border, 4, 1.0, 0.1, 2.0);
	border = clamp(13.333 * (1.0 - border), 0.0, 1.0);
	
	if (pos.z < 1.0 - 1e-5) {
		#if MC_VERSION > 10800
		color.a = texture2D(gaux2, pos.st).a;
		if (color.a > 0.001) color.rgb = texture2D(gaux2, pos.st).rgb;
		#else
		color.a = texture2DLod(gaux2, pos.st, 0).a;
		if (color.a > 0.001) color.rgb = texture2DLod(gaux2, pos.st, 0).rgb;
		#endif
		
		color.a *= border;
	}
	
    return color;
}