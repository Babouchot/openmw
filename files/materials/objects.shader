#include "core.h"

#include "shadows.h"


#define FOG @shPropertyBool(fog)
#define MRT @shPropertyNotBool(is_transparent) && @shPropertyBool(mrt_output) && @shGlobalSettingBool(mrt_output)
#define LIGHTING @shPropertyBool(lighting)

#define SHADOWS_PSSM LIGHTING && @shGlobalSettingBool(shadows_pssm)
#define SHADOWS LIGHTING && @shGlobalSettingBool(shadows)

#if FOG || MRT || SHADOWS_PSSM
#define NEED_DEPTH
#endif

#define HAS_VERTEXCOLOR @shPropertyBool(has_vertex_colour)

#ifdef SH_VERTEX_SHADER

    // ------------------------------------- VERTEX ---------------------------------------

    SH_BEGIN_PROGRAM
        shUniform(float4x4 wvp) @shAutoConstant(wvp, worldviewproj_matrix)
        shInput(float2, uv0)
        shOutput(float2, UV)
        shNormalInput(float4)
#ifdef NEED_DEPTH
        shOutput(float, depthPassthrough)
#endif

#if LIGHTING
        shOutput(float3, normalPassthrough)
        shOutput(float3, objSpacePositionPassthrough)
#endif

#if HAS_VERTEXCOLOR
        shColourInput(float4)
        shOutput(float4, colorPassthrough)
#endif

#if SHADOWS
        shOutput(float4, lightSpacePos0)
        shUniform(float4x4 texViewProjMatrix0) @shAutoConstant(texViewProjMatrix0, texture_viewproj_matrix)
        shUniform(float4x4 worldMatrix) @shAutoConstant(worldMatrix, world_matrix)
#endif

#if SHADOWS_PSSM
    @shForeach(3)
        shOutput(float4, lightSpacePos@shIterator)
        shUniform(float4x4 texViewProjMatrix@shIterator) @shAutoConstant(texViewProjMatrix@shIterator, texture_viewproj_matrix, @shIterator)
    @shEndForeach
        shUniform(float4x4 worldMatrix) @shAutoConstant(worldMatrix, world_matrix)
#endif
    SH_START_PROGRAM
    {
	    shOutputPosition = shMatrixMult(wvp, shInputPosition);
	    UV = uv0;
#if LIGHTING
        normalPassthrough = normal.xyz;
#endif

#ifdef NEED_DEPTH
        depthPassthrough = shOutputPosition.z;
#endif

#if LIGHTING
        objSpacePositionPassthrough = shInputPosition.xyz;
#endif

#if HAS_VERTEXCOLOR
        colorPassthrough = colour;
#endif

#if SHADOWS
        lightSpacePos0 = shMatrixMult(texViewProjMatrix0, shMatrixMult(worldMatrix, shInputPosition));
#endif
#if SHADOWS_PSSM
        float4 wPos = shMatrixMult(worldMatrix, shInputPosition);
    @shForeach(3)
        lightSpacePos@shIterator = shMatrixMult(texViewProjMatrix@shIterator, wPos);
    @shEndForeach
#endif
    }

#else

    // ----------------------------------- FRAGMENT ------------------------------------------

    SH_BEGIN_PROGRAM
		shSampler2D(diffuseMap)
		shInput(float2, UV)
#if MRT
        shDeclareMrtOutput(1)
#endif

#ifdef NEED_DEPTH
        shInput(float, depthPassthrough)
#endif

#if MRT
        shUniform(float far) @shAutoConstant(far, far_clip_distance)
#endif

#if LIGHTING
        shInput(float3, normalPassthrough)
        shInput(float3, objSpacePositionPassthrough)
        shUniform(float4 lightAmbient)                       @shAutoConstant(lightAmbient, ambient_light_colour)
        //shUniform(float passIteration)                       @shAutoConstant(passIteration, pass_iteration_number)
        shUniform(float4 materialAmbient)                    @shAutoConstant(materialAmbient, surface_ambient_colour)
        shUniform(float4 materialDiffuse)                    @shAutoConstant(materialDiffuse, surface_diffuse_colour)
        shUniform(float4 materialEmissive)                   @shAutoConstant(materialEmissive, surface_emissive_colour)
    @shForeach(8)
        shUniform(float4 lightPosObjSpace@shIterator)        @shAutoConstant(lightPosObjSpace@shIterator, light_position_object_space, @shIterator)
        shUniform(float4 lightAttenuation@shIterator)        @shAutoConstant(lightAttenuation@shIterator, light_attenuation, @shIterator)
        shUniform(float4 lightDiffuse@shIterator)            @shAutoConstant(lightDiffuse@shIterator, light_diffuse_colour, @shIterator)
    @shEndForeach
#endif
        
#if FOG
        shUniform(float3 fogColor) @shAutoConstant(fogColor, fog_colour)
        shUniform(float4 fogParams) @shAutoConstant(fogParams, fog_params)
#endif

#ifdef HAS_VERTEXCOLOR
        shInput(float4, colorPassthrough)
#endif

#if SHADOWS
        shInput(float4, lightSpacePos0)
        shSampler2D(shadowMap0)
        shUniform(float2 invShadowmapSize0)   @shAutoConstant(invShadowmapSize0, inverse_texture_size, 1)
#endif
#if SHADOWS_PSSM
    @shForeach(3)
        shInput(float4, lightSpacePos@shIterator)
        shSampler2D(shadowMap@shIterator)
        shUniform(float2 invShadowmapSize@shIterator)  @shAutoConstant(invShadowmapSize@shIterator, inverse_texture_size, @shIterator(1))
    @shEndForeach
    shUniform(float4 pssmSplitPoints)  @shSharedParameter(pssmSplitPoints)
#endif

#if SHADOWS || SHADOWS_PSSM
        shUniform(float4 shadowFar_fadeStart) @shSharedParameter(shadowFar_fadeStart)
#endif
    SH_START_PROGRAM
    {
        shOutputColour(0) = shSample(diffuseMap, UV);

#if LIGHTING
        float3 normal = normalize(normalPassthrough);
        float3 lightDir, diffuse;
        float d;
        float3 ambient = materialAmbient.xyz * lightAmbient.xyz;
    
    @shForeach(8)
    
        // shadows only for the first (directional) light
#if @shIterator == 0
    #if SHADOWS
            float shadow = depthShadowPCF (shadowMap0, lightSpacePos0, invShadowmapSize0);
    #endif
    #if SHADOWS_PSSM
            float shadow = pssmDepthShadow (lightSpacePos0, invShadowmapSize0, shadowMap0, lightSpacePos1, invShadowmapSize1, shadowMap1, lightSpacePos2, invShadowmapSize2, shadowMap2, depthPassthrough, pssmSplitPoints);
    #endif

    #if SHADOWS || SHADOWS_PSSM
            float fadeRange = shadowFar_fadeStart.x - shadowFar_fadeStart.y;
            float fade = 1-((depthPassthrough - shadowFar_fadeStart.y) / fadeRange);
            shadow = (depthPassthrough > shadowFar_fadeStart.x) ? 1 : ((depthPassthrough > shadowFar_fadeStart.y) ? 1-((1-shadow)*fade) : shadow);
    #endif

    #if !SHADOWS && !SHADOWS_PSSM
            float shadow = 1.0;
    #endif
#endif
    
        lightDir = lightPosObjSpace@shIterator.xyz - (objSpacePositionPassthrough.xyz * lightPosObjSpace@shIterator.w);
        d = length(lightDir);
        
        lightDir = normalize(lightDir);

#if @shIterator == 0 && (SHADOWS || SHADOWS_PSSM)
        diffuse += materialDiffuse.xyz * lightDiffuse@shIterator.xyz * (1.0 / ((lightAttenuation@shIterator.y) + (lightAttenuation@shIterator.z * d) + (lightAttenuation@shIterator.w * d * d))) * max(dot(normal, lightDir), 0) * shadow;
#else
        diffuse += materialDiffuse.xyz * lightDiffuse@shIterator.xyz * (1.0 / ((lightAttenuation@shIterator.y) + (lightAttenuation@shIterator.z * d) + (lightAttenuation@shIterator.w * d * d))) * max(dot(normal, lightDir), 0);
#endif
    @shEndForeach
    
#if HAS_VERTEXCOLOR
        ambient *= colorPassthrough.xyz;
#endif

        shOutputColour(0).xyz *= (ambient + diffuse + materialEmissive.xyz);
#endif


#if HAS_VERTEXCOLOR && !LIGHTING
        shOutputColour(0).xyz *= colorPassthrough.xyz;
#endif

#if FOG
        float fogValue = shSaturate((depthPassthrough - fogParams.y) * fogParams.w);
        shOutputColour(0).xyz = shLerp (shOutputColour(0).xyz, fogColor, fogValue);
#endif

        // prevent negative color output (for example with negative lights)
        shOutputColour(0).xyz = max(shOutputColour(0).xyz, float3(0,0,0));

#if MRT
        shOutputColour(1) = float4(depthPassthrough / far,1,1,1);
#endif
    }

#endif
